import CoreGraphics
import Foundation

/// Self-contained RFC 9649 WebP Lossless (`VP8L`) encoder with canonical Huffman coding.
/// Produces standard `.webp` files with full 32-bit RGBA transparency that decode natively
/// in macOS ImageIO, Safari, Chrome, and Photoshop without external libraries.
nonisolated enum WebPEncoder {
    /// Encodes `image` as a lossless WebP (`RIFF/WEBP/VP8L`) file.
    static func encode(_ image: CGImage) throws -> Data {
        let width = image.width, height = image.height
        guard (1...16383).contains(width), (1...16383).contains(height) else { throw ExportError.tooLarge }

        // Copy into top-left premultiplied RGBA8 (preserving upright orientation), then unpremultiply to straight RGBA8.
        let ctx = try BrushRaster.copy(image)
        guard let ptr = ctx.data?.assumingMemoryBound(to: UInt8.self) else { throw ExportError.render }
        let stride = ctx.bytesPerRow
        let count = width * height

        var red = [UInt8](repeating: 0, count: count)
        var green = [UInt8](repeating: 0, count: count)
        var blue = [UInt8](repeating: 0, count: count)
        var alpha = [UInt8](repeating: 0, count: count)

        var rFreq = [Int](repeating: 0, count: 256)
        var gFreq = [Int](repeating: 0, count: 280) // VP8L green tree alphabet is 256 + 24 length codes
        var bFreq = [Int](repeating: 0, count: 256)
        var aFreq = [Int](repeating: 0, count: 256)

        var idx = 0
        for y in 0..<height {
            let row = ptr + y * stride
            for x in 0..<width {
                let a = row[x * 4 + 3]
                let r: UInt8, g: UInt8, b: UInt8
                if a == 0 {
                    r = 0; g = 0; b = 0
                } else if a == 255 {
                    r = row[x * 4]; g = row[x * 4 + 1]; b = row[x * 4 + 2]
                } else {
                    let ai = Int(a), half = ai / 2
                    r = UInt8(min(255, (Int(row[x * 4]) * 255 + half) / ai))
                    g = UInt8(min(255, (Int(row[x * 4 + 1]) * 255 + half) / ai))
                    b = UInt8(min(255, (Int(row[x * 4 + 2]) * 255 + half) / ai))
                }
                red[idx] = r; green[idx] = g; blue[idx] = b; alpha[idx] = a
                rFreq[Int(r)] += 1; gFreq[Int(g)] += 1; bFreq[Int(b)] += 1; aFreq[Int(a)] += 1
                idx += 1
            }
        }

        // Build canonical Huffman codes (max length 15) for each RGBA channel.
        let gTree = HuffmanTree.build(frequencies: gFreq, maxBits: 15)
        let rTree = HuffmanTree.build(frequencies: rFreq, maxBits: 15)
        let bTree = HuffmanTree.build(frequencies: bFreq, maxBits: 15)
        let aTree = HuffmanTree.build(frequencies: aFreq, maxBits: 15)

        // Assemble VP8L bitstream (LSB-first).
        var bits = BitWriter()
        // VP8L signature byte (0x2F) + 32-bit header: width-1 (14), height-1 (14), alpha_used (1), version (3).
        bits.write(0x2F, count: 8)
        bits.write(UInt32(width - 1), count: 14)
        bits.write(UInt32(height - 1), count: 14)
        bits.write(1, count: 1) // alpha_is_used = 1
        bits.write(0, count: 3) // version = 0

        bits.write(0, count: 1) // transform_present = 0
        bits.write(0, count: 1) // color_cache_used = 0
        bits.write(0, count: 1) // meta_huffman_used = 0

        // Write 5 prefix trees: Green(280), Red(256), Blue(256), Alpha(256), Distance(40, unused).
        gTree.write(to: &bits)
        rTree.write(to: &bits)
        bTree.write(to: &bits)
        aTree.write(to: &bits)
        // Unused distance tree: 1-symbol simple code with symbol 0.
        bits.write(1, count: 1) // is_simple = 1
        bits.write(0, count: 1) // num_symbols - 1 = 0
        bits.write(0, count: 1) // is_first_8bits = 0
        bits.write(0, count: 1) // symbol0 = 0

        // Emit pixel stream in exact VP8L channel order: G, R, B, A.
        let gCodes = gTree.codes, gLens = gTree.lengths
        let rCodes = rTree.codes, rLens = rTree.lengths
        let bCodes = bTree.codes, bLens = bTree.lengths
        let aCodes = aTree.codes, aLens = aTree.lengths

        for i in 0..<count {
            let gi = Int(green[i])
            if gLens[gi] > 0 { bits.write(gCodes[gi], count: gLens[gi]) }
            let ri = Int(red[i])
            if rLens[ri] > 0 { bits.write(rCodes[ri], count: rLens[ri]) }
            let bi = Int(blue[i])
            if bLens[bi] > 0 { bits.write(bCodes[bi], count: bLens[bi]) }
            let ai = Int(alpha[i])
            if aLens[ai] > 0 { bits.write(aCodes[ai], count: aLens[ai]) }
        }

        let vp8l = bits.finish()
        let paddedVP8LSize = vp8l.count + (vp8l.count & 1)
        let riffPayloadSize = UInt32(4 + 4 + 4 + paddedVP8LSize)

        var out = Data(capacity: 20 + paddedVP8LSize)
        out.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendLE32(&out, riffPayloadSize)
        out.append(contentsOf: [0x57, 0x45, 0x42, 0x50]) // "WEBP"
        out.append(contentsOf: [0x56, 0x50, 0x38, 0x4C]) // "VP8L"
        appendLE32(&out, UInt32(vp8l.count))
        out.append(vp8l)
        if vp8l.count & 1 == 1 { out.append(0) }
        return out
    }

    private static func appendLE32(_ data: inout Data, _ v: UInt32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    // MARK: - LSB-first BitWriter

    private struct BitWriter {
        private var bytes: [UInt8] = []
        private var buffer: UInt64 = 0
        private var bitCount: Int = 0

        mutating func write(_ value: UInt32, count: Int) {
            guard count > 0 else { return }
            buffer |= UInt64(value) << bitCount
            bitCount += count
            while bitCount >= 8 {
                bytes.append(UInt8(buffer & 0xFF))
                buffer >>= 8
                bitCount -= 8
            }
        }

        mutating func finish() -> Data {
            if bitCount > 0 {
                bytes.append(UInt8(buffer & 0xFF))
                buffer = 0
                bitCount = 0
            }
            return Data(bytes)
        }
    }

    // MARK: - VP8L Canonical Prefix Code Tree

    private struct HuffmanTree {
        let alphabetSize: Int
        let lengths: [Int]
        /// Bit-reversed canonical Huffman codes ready for LSB-first emission.
        let codes: [UInt32]
        let simpleSymbols: [Int]?

        static func build(frequencies: [Int], maxBits: Int) -> HuffmanTree {
            let n = frequencies.count
            let present = frequencies.indices.filter { frequencies[$0] > 0 }

            if present.isEmpty {
                return HuffmanTree(alphabetSize: n, lengths: [Int](repeating: 0, count: n),
                                   codes: [UInt32](repeating: 0, count: n), simpleSymbols: [0])
            }
            if present.count == 1 {
                return HuffmanTree(alphabetSize: n, lengths: [Int](repeating: 0, count: n),
                                   codes: [UInt32](repeating: 0, count: n), simpleSymbols: [present[0]])
            }
            if present.count == 2 {
                let s0 = present[0], s1 = present[1]
                var lens = [Int](repeating: 0, count: n)
                var codes = [UInt32](repeating: 0, count: n)
                lens[s0] = 1; codes[s0] = 0
                lens[s1] = 1; codes[s1] = 1
                return HuffmanTree(alphabetSize: n, lengths: lens, codes: codes, simpleSymbols: [s0, s1])
            }

            // Build Huffman tree using a simple sorted array (n <= 280, takes microseconds).
            final class Node {
                let freq: Int
                let symbol: Int
                let left: Node?
                let right: Node?
                init(freq: Int, symbol: Int, left: Node? = nil, right: Node? = nil) {
                    self.freq = freq; self.symbol = symbol; self.left = left; self.right = right
                }
            }
            var nodes = present.map { Node(freq: frequencies[$0], symbol: $0) }
            while nodes.count > 1 {
                nodes.sort { $0.freq < $1.freq }
                let a = nodes.removeFirst()
                let b = nodes.removeFirst()
                nodes.append(Node(freq: a.freq + b.freq, symbol: -1, left: a, right: b))
            }

            var lens = [Int](repeating: 0, count: n)
            func walk(_ node: Node, depth: Int) {
                if node.symbol >= 0 {
                    lens[node.symbol] = max(1, depth)
                } else {
                    if let l = node.left { walk(l, depth: depth + 1) }
                    if let r = node.right { walk(r, depth: depth + 1) }
                }
            }
            walk(nodes[0], depth: 0)

            // Enforce max code length <= maxBits (15) while maintaining exact Kraft sum == 2^maxBits.
            var needsClamp = false
            for i in 0..<n where lens[i] > maxBits { lens[i] = maxBits; needsClamp = true }
            if needsClamp {
                let target = 1 << maxBits
                func kraftSum() -> Int {
                    var s = 0
                    for l in lens where l > 0 { s += 1 << (maxBits - l) }
                    return s
                }
                // Overshoot: lengthen deepest < maxBits symbols to reduce Kraft sum.
                while kraftSum() > target {
                    if let idx = present.filter({ lens[$0] < maxBits }).max(by: { lens[$0] < lens[$1] }) {
                        lens[idx] += 1
                    } else { break }
                }
                // Undershoot: shorten highest-frequency symbols that fit within remaining budget.
                let sortedByFreq = present.sorted { frequencies[$0] > frequencies[$1] }
                while kraftSum() < target {
                    let deficit = target - kraftSum()
                    var improved = false
                    for idx in sortedByFreq where lens[idx] > 1 {
                        let gain = 1 << (maxBits - lens[idx])
                        if gain <= deficit {
                            lens[idx] -= 1
                            improved = true
                            break
                        }
                    }
                    if !improved { break }
                }
            }

            let codes = canonicalReversedCodes(lengths: lens, maxBits: maxBits)
            return HuffmanTree(alphabetSize: n, lengths: lens, codes: codes, simpleSymbols: nil)
        }

        private static func canonicalReversedCodes(lengths: [Int], maxBits: Int) -> [UInt32] {
            var blCount = [Int](repeating: 0, count: maxBits + 1)
            for l in lengths where l > 0 { blCount[l] += 1 }
            var nextCode = [UInt32](repeating: 0, count: maxBits + 1)
            var code: UInt32 = 0
            for bits in 1...maxBits {
                code = (code + UInt32(blCount[bits - 1])) << 1
                nextCode[bits] = code
            }
            var reversed = [UInt32](repeating: 0, count: lengths.count)
            for (sym, len) in lengths.enumerated() where len > 0 {
                let c = nextCode[len]
                nextCode[len] += 1
                reversed[sym] = reverseBits(c, count: len)
            }
            return reversed
        }

        private static func reverseBits(_ v: UInt32, count: Int) -> UInt32 {
            var x = v, r: UInt32 = 0
            for _ in 0..<count {
                r = (r << 1) | (x & 1)
                x >>= 1
            }
            return r
        }

        /// Writes this tree in VP8L format (Simple Code for 1–2 symbols, Normal Code with 4-bit code-length alphabet for 3+).
        func write(to bits: inout BitWriter) {
            if let syms = simpleSymbols {
                bits.write(1, count: 1) // is_simple = 1
                bits.write(UInt32(syms.count - 1), count: 1) // 0 for 1 symbol, 1 for 2 symbols
                let s0 = syms[0]
                let first8 = s0 > 1 ? 1 : 0
                bits.write(UInt32(first8), count: 1)
                bits.write(UInt32(s0), count: first8 == 1 ? 8 : 1)
                if syms.count == 2 {
                    bits.write(UInt32(syms[1]), count: 8)
                }
                return
            }

            // Normal code:
            // kCodeLengthCodeOrder = [17, 18, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]
            // Assign fixed 4-bit code lengths to symbols 0..15 (16 symbols -> Kraft sum = 16/16 = 1.0)
            // and 0 to symbols 17, 18, 16.
            bits.write(0, count: 1) // is_simple = 0
            bits.write(14, count: 4) // num_code_lengths = 14 + 4 = 18 (covers indices 0..17, i.e., 17, 18, 0..15)
            bits.write(0, count: 3) // length for symbol 17 = 0
            bits.write(0, count: 3) // length for symbol 18 = 0
            for _ in 0..<16 {
                bits.write(4, count: 3) // length for symbols 0..15 = 4 bits
            }
            bits.write(0, count: 1) // use_max_symbol = 0 (reads full alphabetSize)
            // For symbols 0..15 all having length 4, canonical code of symbol `l` is `l`, bit-reversed over 4 bits.
            for l in lengths {
                bits.write(Self.reverseBits(UInt32(l), count: 4), count: 4)
            }
        }
    }
}
