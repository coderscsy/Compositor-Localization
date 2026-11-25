import AppKit
import Testing
@testable import Compositor

@MainActor
struct BrushLibraryTests {
    @Test func importingCopiesTheBrushAndRestoresItWithoutTheOriginal() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = folder.appending(path: "Sample.abr")
        let storage = folder.appending(path: "Support/Brush Presets.plist")
        // An original 3×2 sampled tip in ABR v1 (uncompressed).
        let record: [UInt8] = [
            0, 0, 0, 0, 0, 36,                 // Miscellaneous, spacing
            1, 0, 0, 0, 0, 0, 2, 0, 3,       // Antialiasing and short bounds
            0, 0, 0, 0, 0, 0, 0, 0,           // Top and left
            0, 0, 0, 2, 0, 0, 0, 3,           // Bottom and right
            0, 8, 0, 255, 0, 0, 50, 100, 255  // Depth, encoding and coverage
        ]
        let data = Data([0, 1, 0, 1, 0, 2, 0, 0, 0, UInt8(record.count)] + record)
        try data.write(to: archive)

        let library = BrushLibrary(file: storage)
        #expect(library.importError == nil)
        await library.importFiles([archive])
        let preset = try #require(library.presets.first { !$0.isBuiltIn })
        #expect(library.importError == nil)
        #expect(preset.name == "Sample")
        #expect(preset.spacing == 0.36)
        #expect(preset.tip?.coverage == Data([255, 0, 0, 50, 100, 255]))
        try FileManager.default.removeItem(at: archive)

        let loaded = BrushLibrary(file: storage)
        let restored = try #require(loaded.presets.first { !$0.isBuiltIn })
        #expect(restored.id == preset.id)
        #expect(restored.tip == preset.tip)
        var settings = BrushSettings(red: 1, erasing: true)
        restored.apply(to: &settings)
        #expect(settings.red == 1 && settings.erasing && settings.diameter == 3 && settings.tip == preset.tip)

        settings.angle = 45
        settings.scatterCount = 3
        settings.sizeJitter = 0.24
        loaded.savePreset(name: "  My Brush  ", settings: settings)
        loaded.removePreset(restored)
        let saved = try #require(BrushLibrary(file: storage).presets.first { !$0.isBuiltIn })
        #expect(saved.name == "My Brush")
        #expect(saved.angle == 45 && saved.scatterCount == 3 && saved.sizeJitter == 0.24)
        #expect(saved.tip == restored.tip)
    }

    @Test func aCorruptLibraryIsNeverOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = folder.appending(path: "Brush Presets.plist")
        let corrupt = Data([1, 2, 3])
        try corrupt.write(to: storage)
        let library = BrushLibrary(file: storage)
        #expect(library.importError != nil)
        library.savePreset(name: "New Preset", settings: BrushSettings())
        #expect(library.importError != nil)
        let builtInsOnly = library.presets.allSatisfy(\.isBuiltIn)
        #expect(builtInsOnly)
        #expect(try Data(contentsOf: storage) == corrupt)
    }
}
