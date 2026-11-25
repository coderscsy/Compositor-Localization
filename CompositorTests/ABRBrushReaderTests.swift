import Foundation
import Testing
@testable import Compositor

struct ABRBrushReaderTests {
    @Test func readsLegacyUnicodeAndPackBitsRows() throws {
        let packed: [UInt8] = [0, 4, 0, 2, 2, 10, 20, 30, 254, 40]
        var sampled = [UInt8](repeating: 0, count: 4) + be16(25) + unicode("画筆")
        sampled += [1] + [UInt8](repeating: 0, count: 8) + bitmap(width: 3, height: 2, compression: 1, payload: packed)
        let computed = be16(1) + be32(14) + [UInt8](repeating: 0, count: 14)
        let file = Data(be16(2) + be16(2) + computed + be16(2) + be32(sampled.count) + sampled)
        let brush = try #require(ABRBrushReader.read(file).first)
        #expect(brush.name == "画筆")
        #expect(brush.width == 3)
        #expect(brush.height == 2)
        #expect(brush.spacing == 0.25)
        #expect(brush.samples == [10, 20, 30, 40, 40, 40])
    }

    @Test func bindsModernPresetsByIdentifierAcrossSectionOrdering() throws {
        let shape = descriptor("sampledBrush", entries: [
            ("sampledData", text("sample-a")), ("Dmtr", unit("#Pxl", 80)), ("Angl", unit("#Ang", -25)),
            ("Spcn", unit("#Prc", 35)), ("Rndn", unit("#Prc", 75)), ("flipX", flag(true))
        ])
        let dynamics = descriptor("null", entries: [("jitter", unit("#Prc", 30))])
        let options = descriptor("paintbrushTool", entries: [("flow", integer(40)), ("Opct", integer(65))])
        let brush = descriptor("brushPreset", entries: [
            ("Nm  ", text("Ink Detail")), ("Brsh", object(shape)), ("useTipDynamics", flag(true)),
            ("szVr", object(dynamics)), ("useScatter", flag(true)), ("scatterDynamics", object(dynamics)),
            ("Cnt ", integer(3)), ("bothAxes", flag(true)), ("toolOptions", object(options))
        ])
        let root = descriptor("null", entries: [("Brsh", list([object(brush)]))])
        let samples = modernRecord("sample-a", subversion: 2, payload: bitmap(width: 3, height: 1, payload: [10, 20, 30]))
        let archive = be16(10) + be16(2) + section("desc", be32(16) + root) + section("samp", samples)
        // A Data slice may have a nonzero start index.
        let package = Data([0xcc, 0xbb] + archive).dropFirst(2)
        let decoded = try ABRBrushReader.read(package)

        let result = try #require(decoded.first)
        #expect(decoded.count == 1)
        #expect(result.name == "Ink Detail")
        #expect(result.samples == [30, 20, 10])
        #expect(result.spacing == 0.35)
        #expect(result.diameter == 80)
        #expect(result.angle == -25)
        #expect(result.roundness == 0.75)
        #expect(result.flow == 0.40)
        #expect(result.opacity == 0.65)
        #expect(result.sizeJitter == 0.30)
        #expect(result.scatter == 0.30)
        #expect(result.scatterCount == 3)
        #expect(result.scatterBothAxes == true)
    }

    @Test func acceptsAdditionalModernVersionsAndExpandsPackedBits() throws {
        for version in [6, 7, 9, 10] {
            let samples = modernRecord("id", subversion: 1, payload: bitmap(width: 3, height: 2, depth: 1, payload: [0xa0, 0x40]))
            let file = Data(be16(version) + be16(1) + section("samp", samples))
            let brush = try #require(ABRBrushReader.read(file).first)
            #expect(brush.samples == [255, 0, 255, 0, 255, 0])
        }
    }

    @Test func normalizesSixteenBitCoverageAndDownsamplesLargeTips() throws {
        let sixteenBit = modernFile(bitmap(width: 3, height: 1, depth: 16,
                                           payload: [0, 0, 0x40, 0, 0x80, 0]))
        let normalized = try #require(ABRBrushReader.read(sixteenBit).first)
        #expect(normalized.samples == [0, 128, 255])

        let large = modernFile(bitmap(width: 5000, height: 1, payload: [UInt8](repeating: 127, count: 5000)))
        let downsampled = try #require(ABRBrushReader.read(large).first)
        #expect(downsampled.width == 4096 && downsampled.height == 1)
        #expect(downsampled.samples == [UInt8](repeating: 127, count: 4096))
    }

    @Test func boundsCorruptAndOversizedRecords() {
        let truncated = Data(be16(6) + be16(1) + Array("8BIMsamp".utf8) + be32(100) + [0])
        #expect(throws: ABRBrushReader.Failure.malformed) { try ABRBrushReader.read(truncated) }

        let brokenBitmap = bitmap(width: 2, height: 1, compression: 1, payload: [0, 2, 2, 0])
        let broken = modernFile(brokenBitmap)
        #expect(throws: ABRBrushReader.Failure.malformed) { try ABRBrushReader.read(broken) }

        let huge = modernFile(bitmap(width: 8193, height: 1, payload: []))
        #expect(throws: ABRBrushReader.Failure.tooLarge) { try ABRBrushReader.read(huge) }

        #expect(throws: ABRBrushReader.Failure.unsupportedVersion) { try ABRBrushReader.read(Data(be16(3) + be16(0))) }
        #expect(throws: ABRBrushReader.Failure.noSampledBrushes) { try ABRBrushReader.read(Data(be16(2) + be16(0))) }
    }

    private func be16(_ value: Int) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }

    private func be32(_ value: Int) -> [UInt8] {
        be16(value >> 16) + be16(value)
    }

    private func pad4(_ bytes: [UInt8]) -> [UInt8] {
        bytes + [UInt8](repeating: 0, count: (4 - bytes.count % 4) % 4)
    }

    private func unicode(_ value: String) -> [UInt8] {
        be32(value.utf16.count + 1) + value.utf16.flatMap { be16(Int($0)) } + [0, 0]
    }

    private func identifier(_ value: String) -> [UInt8] {
        be32(value.utf8.count == 4 ? 0 : value.utf8.count) + Array(value.utf8)
    }

    private func descriptor(_ name: String, entries: [(String, [UInt8])]) -> [UInt8] {
        var result = be32(0) + identifier(name) + be32(entries.count)
        for (key, value) in entries { result += identifier(key) + value }
        return result
    }

    private func text(_ value: String) -> [UInt8] { Array("TEXT".utf8) + unicode(value) }
    private func object(_ value: [UInt8]) -> [UInt8] { Array("Objc".utf8) + value }
    private func flag(_ value: Bool) -> [UInt8] { Array("bool".utf8) + [value ? 1 : 0] }
    private func integer(_ value: Int) -> [UInt8] { Array("long".utf8) + be32(value) }

    private func list(_ entries: [[UInt8]]) -> [UInt8] {
        Array("VlLs".utf8) + be32(entries.count) + entries.flatMap { $0 }
    }

    private func unit(_ unit: String, _ value: Double) -> [UInt8] {
        let bits = value.bitPattern
        let high = Int(bits >> 32)
        let low = Int(bits & 0xffffffff)
        return Array(("UntF" + unit).utf8) + be32(high) + be32(low)
    }

    private func bitmap(width: Int, height: Int, depth: Int = 8, compression: UInt8 = 0, payload: [UInt8]) -> [UInt8] {
        let bounds = be32(-5) + be32(-10) + be32(height - 5) + be32(width - 10)
        return bounds + be16(depth) + [compression] + payload
    }

    private func section(_ key: String, _ payload: [UInt8]) -> [UInt8] {
        Array(("8BIM" + key).utf8) + be32(payload.count) + pad4(payload)
    }

    private func modernRecord(_ id: String, subversion: Int, payload: [UInt8]) -> [UInt8] {
        let prefix = [UInt8(id.utf8.count)] + Array(id.utf8)
        let record = prefix + [UInt8](repeating: 0, count: subversion == 1 ? 10 : 264) + payload
        return be32(record.count) + pad4(record)
    }

    private func modernFile(_ bitmap: [UInt8]) -> Data {
        Data(be16(6) + be16(1) + section("samp", modernRecord("id", subversion: 1, payload: bitmap)))
    }
}
