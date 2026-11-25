import Foundation

nonisolated struct ABRSampledBrush: Sendable {
    /// Empty when an archive stores only a tip identifier or omits the name.
    let name: String
    let width: Int
    let height: Int
    /// One coverage byte per pixel, left to right and top to bottom.
    let samples: [UInt8]
    let spacing: Double?
    let diameter: Double?
    let angle: Double?
    let roundness: Double?
    let flow: Double?
    let opacity: Double?
    let sizeJitter: Double?
    let angleJitter: Double?
    let opacityJitter: Double?
    let scatter: Double?
    let scatterCount: Int?
    let scatterBothAxes: Bool?
}

/// Imports sampled tips from the original ABR records and the later sectioned format.
/// The modern layout is based on the independently documented GIMP and ag-psd readers.
nonisolated enum ABRBrushReader {
    enum Failure: Error, Equatable {
        case unsupportedVersion
        case noSampledBrushes
        case malformed
        case tooLarge
    }

    static let maximumFileBytes = 128 * 1024 * 1024
    private static let maximumTipSide = 4096
    private static let maximumSourceSide = 8192
    private static let maximumCoverage = 64 * 1024 * 1024
    private static let maximumBrushCount = 512

    static func read(_ data: Data) throws -> [ABRSampledBrush] {
        guard data.count <= maximumFileBytes else { throw Failure.tooLarge }
        var input = Cursor(data)
        let version = try input.int16()
        let countOrSubversion = try input.int16()
        let brushes: [ABRSampledBrush]
        switch version {
        case 1, 2:
            brushes = try readLegacy(&input, version: version, count: countOrSubversion)
        case 6, 7, 9, 10:
            guard countOrSubversion == 1 || countOrSubversion == 2 else { throw Failure.unsupportedVersion }
            brushes = try readSections(&input, subversion: countOrSubversion)
        default:
            throw Failure.unsupportedVersion
        }
        guard !brushes.isEmpty else { throw Failure.noSampledBrushes }
        return brushes
    }

    private static func readLegacy(_ input: inout Cursor, version: Int, count: Int) throws -> [ABRSampledBrush] {
        var budget = Budget()
        var brushes: [ABRSampledBrush] = []
        for _ in 0..<count {
            let kind = try input.int16()
            let size = try input.int32()
            var record = try input.take(size)
            guard kind == 2 else { continue }
            try record.skip(4)
            let spacing = try record.int16()
            let name = version == 2 ? try record.unicode() : ""
            try record.skip(9)
            guard let bitmap = try readBitmap(&record, budget: &budget) else { continue }
            brushes.append(bitmap.brush(name: name, spacing: (1...999).contains(spacing) ? Double(spacing) / 100 : nil))
        }
        return brushes
    }

    private static func readSections(_ input: inout Cursor, subversion: Int) throws -> [ABRSampledBrush] {
        var budget = Budget()
        var samples: [(id: String, bitmap: Bitmap)] = []
        var presets: [Preset] = []
        while input.remaining >= 12 {
            guard try input.code() == "8BIM" else { throw Failure.malformed }
            let kind = try input.code()
            let length = try input.int32()
            var section = try input.take(length)
            switch kind {
            case "samp":
                while section.remaining >= 4 {
                    let recordLength = try section.int32()
                    var record = try section.take(recordLength)
                    let id = try record.pascalString().lowercased()
                    try record.skip(subversion == 1 ? 10 : 264)
                    if let bitmap = try readBitmap(&record, budget: &budget) {
                        samples.append((id, bitmap))
                    }
                    try section.skipPadding(for: recordLength)
                }
            case "desc" where length <= 8 * 1024 * 1024:
                // A proprietary descriptor can contain unsupported options. The samples stand on their own.
                let parsed = (try? readPresets(&section)) ?? []
                guard parsed.count <= maximumBrushCount - presets.count else { throw Failure.tooLarge }
                presets.append(contentsOf: parsed)
            default:
                break
            }
            // Some producers begin the next tagged section without adding alignment bytes.
            if !input.startsWith("8BIM") { try input.skipPadding(for: length) }
        }
        guard input.remaining < 4 else { throw Failure.malformed }

        let bitmaps = Dictionary(samples.filter { !$0.id.isEmpty }.map { ($0.id, $0.bitmap) },
                                 uniquingKeysWith: { first, _ in first })
        var used = Set<String>()
        var result: [ABRSampledBrush] = []
        var outputBudget = Budget()
        for preset in presets {
            guard let bitmap = bitmaps[preset.sampleID] else { continue }
            try outputBudget.consume(bitmap.samples.count)
            used.insert(preset.sampleID)
            result.append(bitmap.brush(preset: preset))
        }
        for sample in samples where !used.contains(sample.id) {
            try outputBudget.consume(sample.bitmap.samples.count)
            result.append(sample.bitmap.brush())
        }
        return result
    }

    private struct Bitmap {
        let width: Int
        let height: Int
        let samples: [UInt8]

        func brush(name: String = "", spacing: Double? = nil, preset: Preset? = nil) -> ABRSampledBrush {
            var coverage = samples
            if let preset, preset.flipX || preset.flipY {
                for y in 0..<height {
                    let sourceY = preset.flipY ? height - 1 - y : y
                    for x in 0..<width {
                        let sourceX = preset.flipX ? width - 1 - x : x
                        coverage[y * width + x] = samples[sourceY * width + sourceX]
                    }
                }
            }
            return ABRSampledBrush(name: preset?.name ?? name, width: width, height: height, samples: coverage,
                                   spacing: preset?.spacing ?? spacing, diameter: preset?.diameter,
                                   angle: preset?.angle, roundness: preset?.roundness, flow: preset?.flow,
                                   opacity: preset?.opacity, sizeJitter: preset?.sizeJitter,
                                   angleJitter: preset?.angleJitter, opacityJitter: preset?.opacityJitter,
                                   scatter: preset?.scatter, scatterCount: preset?.scatterCount,
                                   scatterBothAxes: preset?.scatterBothAxes)
        }
    }

    private static func readBitmap(_ input: inout Cursor, budget: inout Budget) throws -> Bitmap? {
        let top = try input.signed32()
        let left = try input.signed32()
        let height = try input.signed32() - top
        let width = try input.signed32() - left
        let depth = try input.int16()
        let compression = Int(try input.byte())
        guard width > 0, height > 0 else { throw Failure.malformed }
        guard depth == 1 || depth == 8 || depth == 16, compression == 0 || compression == 1 else { return nil }
        guard width <= maximumSourceSide, height <= maximumSourceSide else { throw Failure.tooLarge }

        let scale = min(1, Double(maximumTipSide) / Double(max(width, height)))
        let outputWidth = max(1, Int((Double(width) * scale).rounded()))
        let outputHeight = max(1, Int((Double(height) * scale).rounded()))
        let rowBytes = (width * depth + 7) / 8
        let minimumBytes = compression == 0 ? rowBytes * height : height * (2 + 2 * ((rowBytes + 127) / 128))
        guard input.remaining >= minimumBytes else { throw Failure.malformed }
        try budget.consume(outputWidth * outputHeight)

        let decoded: [UInt8]
        do {
            decoded = try PSDChannelCoder.decode(compression: compression, width: rowBytes, height: height,
                                                 data: input.remainingData)
        } catch {
            throw Failure.malformed
        }
        var range16 = 32_768
        if depth == 16 {
            // Photoshop's nominal 16-bit scale is 0...32768. Some writers use the entire unsigned range.
            for offset in stride(from: 0, to: decoded.count, by: 2)
                where Int(decoded[offset]) * 256 + Int(decoded[offset + 1]) > range16 {
                range16 = 65_535
                break
            }
        }
        func pixel(_ x: Int, _ y: Int) -> Int {
            let row = y * rowBytes
            switch depth {
            case 1:
                return decoded[row + x / 8] & (0x80 >> (x % 8)) == 0 ? 0 : 255
            case 16:
                let offset = row + x * 2
                let sample = Int(decoded[offset]) * 256 + Int(decoded[offset + 1])
                return (sample * 255 + range16 / 2) / range16
            default:
                return Int(decoded[row + x])
            }
        }
        if depth == 8, outputWidth == width, outputHeight == height {
            return Bitmap(width: width, height: height, samples: decoded)
        }
        var coverage = [UInt8]()
        coverage.reserveCapacity(outputWidth * outputHeight)
        for y in 0..<outputHeight {
            let firstY = y * height / outputHeight
            let lastY = (y + 1) * height / outputHeight
            for x in 0..<outputWidth {
                let firstX = x * width / outputWidth
                let lastX = (x + 1) * width / outputWidth
                var total = 0
                for row in firstY..<lastY {
                    for column in firstX..<lastX { total += pixel(column, row) }
                }
                let area = (lastX - firstX) * (lastY - firstY)
                coverage.append(UInt8((total + area / 2) / area))
            }
        }
        return Bitmap(width: outputWidth, height: outputHeight, samples: coverage)
    }

    private struct Budget {
        private var bytes = 0
        private var count = 0

        mutating func consume(_ added: Int) throws {
            guard count < maximumBrushCount, added <= maximumCoverage - bytes else { throw Failure.tooLarge }
            count += 1
            bytes += added
        }
    }

    private struct Preset {
        let sampleID: String
        let name: String
        let spacing: Double?
        let diameter: Double?
        let angle: Double?
        let roundness: Double?
        let flow: Double?
        let opacity: Double?
        let sizeJitter: Double?
        let angleJitter: Double?
        let opacityJitter: Double?
        let scatter: Double?
        let scatterCount: Int?
        let scatterBothAxes: Bool?
        let flipX: Bool
        let flipY: Bool
    }

    private static func readPresets(_ section: inout Cursor) throws -> [Preset] {
        guard try section.int32() == 16 else { return [] }
        var budget = 60_000
        let root = try Descriptor.read(&section, depth: 0, budget: &budget)
        guard case .list(let brushes) = root.values["Brsh"] else { return [] }
        return brushes.compactMap { brush in
            guard case .object(let preset) = brush,
                  case .object(let tip) = preset.values["Brsh"], tip.kind == "sampledBrush",
                  let id = tip.text("sampledData")?.lowercased(), !id.isEmpty else { return nil }
            let name = preset.text("Nm  ").flatMap { $0.isEmpty ? nil : $0 } ?? tip.text("Nm  ") ?? ""
            let options = preset.object("toolOptions")
            let spacing = tip.flag("Intr") == false ? nil : tip.fraction("Spcn", maximum: 999)
            let usesShapeDynamics = preset.flag("useTipDynamics") == true
            let usesTransfer = preset.flag("usePaintDynamics") == true
            let usesScatter = preset.flag("useScatter") == true
            return Preset(sampleID: id, name: name, spacing: spacing,
                          diameter: tip.number("Dmtr", unit: "#Pxl", in: 1...10_000),
                          angle: tip.number("Angl", unit: "#Ang", in: -360...360),
                          roundness: tip.fraction("Rndn"),
                          flow: options?.fraction("flow"), opacity: options?.fraction("Opct"),
                          sizeJitter: usesShapeDynamics ? preset.object("szVr")?.fraction("jitter") : nil,
                          angleJitter: usesShapeDynamics ? preset.object("angleDynamics")?.fraction("jitter") : nil,
                          opacityJitter: usesTransfer ? preset.object("opVr")?.fraction("jitter") : nil,
                          scatter: usesScatter ? preset.object("scatterDynamics")?.fraction("jitter", maximum: 1000) : nil,
                          scatterCount: usesScatter ? preset.number("Cnt ", unit: "", in: 1...16).map { Int($0) } : nil,
                          scatterBothAxes: usesScatter ? preset.flag("bothAxes") : nil,
                          flipX: tip.flag("flipX") == true, flipY: tip.flag("flipY") == true)
        }
    }

    /// Reads just enough of an Action Descriptor to bind user-facing names and tip geometry to their samples.
    private struct Descriptor {
        indirect enum Value {
            case text(String)
            case flag(Bool)
            case unit(String, Double)
            case object(Descriptor)
            case list([Value])
            case ignored

            static func read(_ input: inout Cursor, depth: Int, budget: inout Int) throws -> Self {
                guard depth < 24, budget > 0 else { throw Failure.malformed }
                budget -= 1
                switch try input.code() {
                case "TEXT":
                    return .text(try input.unicode())
                case "bool":
                    return .flag(try input.byte() != 0)
                case "UntF":
                    let unit = try input.code()
                    return .unit(unit, try input.double())
                case "Objc", "GlbO":
                    return .object(try Descriptor.read(&input, depth: depth + 1, budget: &budget))
                case "VlLs":
                    let count = try input.int32()
                    guard count <= budget, count <= input.remaining / 4 else { throw Failure.malformed }
                    var list: [Value] = []
                    for _ in 0..<count { try list.append(read(&input, depth: depth + 1, budget: &budget)) }
                    return .list(list)
                case "long":
                    return .unit("", Double(try input.signed32()))
                case "doub":
                    return .unit("", try input.double())
                case "UnFl":
                    let unit = try input.code()
                    return .unit(unit, Double(Float(bitPattern: UInt32(try input.int32()))))
                case "comp":
                    try input.skip(8)
                case "enum":
                    try input.skipIdentifier()
                    try input.skipIdentifier()
                case "tdta", "alis", "Pth ":
                    let size = try input.int32()
                    try input.skip(size)
                case "type", "GlbC", "Clss":
                    try input.skipUnicode()
                    try input.skipIdentifier()
                default:
                    throw Failure.malformed
                }
                return .ignored
            }
        }

        let kind: String
        let values: [String: Value]

        static func read(_ input: inout Cursor, depth: Int, budget: inout Int) throws -> Self {
            try input.skipUnicode()
            let kind = try input.identifier()
            let count = try input.int32()
            guard count <= budget, count <= input.remaining / 12 else { throw Failure.malformed }
            var values: [String: Value] = [:]
            for _ in 0..<count {
                let key = try input.identifier()
                values[key] = try Value.read(&input, depth: depth, budget: &budget)
            }
            return Self(kind: kind, values: values)
        }

        func text(_ key: String) -> String? {
            guard case .text(let text) = values[key] else { return nil }
            return text
        }

        func flag(_ key: String) -> Bool? {
            guard case .flag(let flag) = values[key] else { return nil }
            return flag
        }

        func object(_ key: String) -> Descriptor? {
            guard case .object(let object) = values[key] else { return nil }
            return object
        }

        func number(_ key: String, unit: String, in range: ClosedRange<Double>) -> Double? {
            guard case .unit(let actualUnit, let value) = values[key],
                  actualUnit == unit || unit == "#Prc" && actualUnit.isEmpty,
                  range.contains(value) else { return nil }
            return value
        }

        func fraction(_ key: String, maximum: Double = 100) -> Double? {
            number(key, unit: "#Prc", in: 0...maximum).map { $0 / 100 }
        }
    }

    /// Big-endian reads constrained to a file, section, or individual record.
    private struct Cursor {
        private let data: Data
        private var offset: Int
        private let end: Int

        init(_ data: Data) {
            self.init(data, bounds: data.startIndex..<data.endIndex)
        }

        private init(_ data: Data, bounds: Range<Int>) {
            self.data = data
            offset = bounds.lowerBound
            end = bounds.upperBound
        }

        var remaining: Int { end - offset }
        var remainingData: Data { Data(data[offset..<end]) }

        mutating func take(_ count: Int) throws -> Self {
            let start = offset
            try skip(count)
            return Self(data, bounds: start..<offset)
        }

        mutating func skip(_ count: Int) throws {
            guard count >= 0, count <= remaining else { throw Failure.malformed }
            offset += count
        }

        mutating func skipPadding(for count: Int) throws {
            try skip(min((4 - count % 4) % 4, remaining))
        }

        mutating func byte() throws -> UInt8 {
            guard remaining > 0 else { throw Failure.malformed }
            defer { offset += 1 }
            return data[offset]
        }

        mutating func int16() throws -> Int {
            try Int(byte()) << 8 | Int(byte())
        }

        mutating func int32() throws -> Int {
            try int16() << 16 | int16()
        }

        mutating func signed32() throws -> Int {
            Int(Int32(bitPattern: UInt32(try int32())))
        }

        mutating func double() throws -> Double {
            Double(bitPattern: try UInt64(int32()) << 32 | UInt64(int32()))
        }

        func startsWith(_ text: String) -> Bool {
            let count = text.utf8.count
            return count <= remaining && data[offset..<(offset + count)].elementsEqual(text.utf8)
        }

        mutating func code() throws -> String {
            try ascii(4)
        }

        mutating func pascalString() throws -> String {
            let count = Int(try byte())
            return try ascii(count)
        }

        mutating func identifier() throws -> String {
            let count = try int32()
            guard count <= 4_096 else { throw Failure.malformed }
            return try ascii(count == 0 ? 4 : count)
        }

        mutating func skipIdentifier() throws {
            let count = try int32()
            try skip(count == 0 ? 4 : count)
        }

        mutating func unicode() throws -> String {
            let count = try int32()
            guard count <= 4_096 else { throw Failure.malformed }
            let start = offset
            try skip(count * 2)
            if count == 0 { return "" }
            guard let text = String(data: data[start..<offset], encoding: .utf16BigEndian) else { throw Failure.malformed }
            return text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
        }

        mutating func skipUnicode() throws {
            let count = try int32()
            try skip(count * 2)
        }

        private mutating func ascii(_ count: Int) throws -> String {
            let start = offset
            try skip(count)
            return String(decoding: data[start..<offset], as: UTF8.self)
        }
    }
}
