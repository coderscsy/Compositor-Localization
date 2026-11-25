import Foundation
import Observation

@MainActor @Observable
final class BrushLibrary {
    static let shared = BrushLibrary()
    private static let maximumPresets = 512
    private static let maximumTipBytes = 64 * 1024 * 1024
    private static let maximumLibraryFileBytes = maximumTipBytes + 2 * 1024 * 1024

    private let file: URL
    private var canWrite = true
    private var userPresets: [BrushPreset] = []
    private(set) var isImporting = false
    var importError: String?
    var presets: [BrushPreset] { BrushPreset.builtIns + userPresets }

    init(file: URL = .applicationSupportDirectory.appending(path: "Compositor/Brush Presets.plist")) {
        self.file = file
        do {
            let data = try Self.readFile(file, upTo: Self.maximumLibraryFileBytes)
            let stored = try PropertyListDecoder().decode([BrushPreset].self, from: data)
            guard stored.count <= Self.maximumPresets, Self.tipBytes(in: stored) <= Self.maximumTipBytes,
                  Set(stored.map(\.id)).count == stored.count,
                  stored.allSatisfy({ !$0.isBuiltIn && UUID(uuidString: $0.id) != nil }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            userPresets = stored
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            // The library is created when the first user preset is saved.
        } catch {
            canWrite = false
            importError = L10n.text("Brush presets could not be loaded.")
        }
    }

    func savePreset(name: String, settings: BrushSettings) {
        guard !isImporting else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let size = settings.tip?.coverage.count ?? 0
        guard userPresets.count < Self.maximumPresets, Self.tipBytes(in: userPresets) + size <= Self.maximumTipBytes else {
            importError = L10n.text("The brush library is full.")
            return
        }
        store(userPresets + [BrushPreset(name: String(name.prefix(256)), settings: settings)])
    }

    func removePreset(_ preset: BrushPreset) {
        guard !isImporting, userPresets.contains(where: { $0.id == preset.id }) else { return }
        store(userPresets.filter { $0.id != preset.id })
    }

    func importFiles(_ urls: [URL]) async {
        guard !isImporting, !urls.isEmpty else { return }
        isImporting = true
        importError = nil
        defer { isImporting = false }
        let availableBytes = Self.maximumTipBytes - Self.tipBytes(in: userPresets)
        let availablePresets = Self.maximumPresets - userPresets.count
        let result = await Task.detached(priority: .userInitiated) {
            Self.readPacks(urls, slots: availablePresets, bytes: availableBytes)
        }.value
        if result.presets.isEmpty || store(userPresets + result.presets) {
            importError = result.messages.isEmpty ? nil : result.messages.joined(separator: "\n")
        }
    }

    @discardableResult
    private func store(_ updated: [BrushPreset]) -> Bool {
        do {
            guard canWrite else { throw CocoaError(.fileWriteNoPermission) }
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(updated)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            userPresets = updated
            importError = nil
            return true
        } catch {
            importError = L10n.text("Brush presets could not be saved.")
            return false
        }
    }

    private nonisolated static func tipBytes(in presets: [BrushPreset]) -> Int {
        presets.reduce(0) { $0 + ($1.tip?.coverage.count ?? 0) }
    }

    private nonisolated static func readFile(_ url: URL, upTo limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        guard let size = values.fileSize, size <= limit else { throw ABRBrushReader.Failure.tooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw ABRBrushReader.Failure.tooLarge }
        return data
    }

    private nonisolated static func readPacks(_ urls: [URL], slots: Int, bytes: Int)
        -> (presets: [BrushPreset], messages: [String]) {
        var presets: [BrushPreset] = []
        var messages: [String] = []
        var remainingBytes = bytes
        var libraryFull = false
        for url in urls {
            if presets.count >= slots || remainingBytes <= 0 {
                libraryFull = true
                break
            }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let file = try readFile(url, upTo: ABRBrushReader.maximumFileBytes)
                let brushes = try ABRBrushReader.read(file)
                let stem = url.deletingPathExtension().lastPathComponent
                for (index, brush) in brushes.enumerated() {
                    if presets.count >= slots {
                        libraryFull = true
                        break
                    }
                    guard brush.samples.count <= remainingBytes else {
                        libraryFull = true
                        continue
                    }
                    guard let tip = BrushTip(width: brush.width, height: brush.height, coverage: Data(brush.samples)) else {
                        throw ABRBrushReader.Failure.malformed
                    }
                    var settings = BrushSettings()
                    settings.tip = tip
                    settings.diameter = min(2000, CGFloat(brush.diameter ?? Double(max(tip.width, tip.height))))
                    settings.spacing = CGFloat(brush.spacing ?? 0.25)
                    settings.angle = CGFloat(brush.angle ?? 0)
                    settings.roundness = CGFloat(brush.roundness ?? 1)
                    settings.flow = CGFloat(brush.flow ?? 1)
                    settings.opacity = CGFloat(brush.opacity ?? 1)
                    settings.sizeJitter = CGFloat(brush.sizeJitter ?? 0)
                    settings.angleJitter = CGFloat(brush.angleJitter ?? 0)
                    settings.opacityJitter = CGFloat(brush.opacityJitter ?? 0)
                    settings.scatter = CGFloat(brush.scatter ?? 0)
                    settings.scatterCount = brush.scatterCount ?? 1
                    settings.scatterBothAxes = brush.scatterBothAxes ?? false
                    let name = brush.name.isEmpty ? (brushes.count == 1 ? stem : "\(stem) \(index + 1)") : brush.name
                    presets.append(.init(name: String(name.prefix(256)), settings: settings))
                    remainingBytes -= tip.coverage.count
                }
            } catch {
                let key: String
                switch error as? ABRBrushReader.Failure {
                case .noSampledBrushes: key = "“%@” contains no supported brush tips."
                case .unsupportedVersion: key = "“%@” uses an unsupported ABR version."
                case .tooLarge: key = "“%@” is too large to import."
                default: key = "Could not read “%@”."
                }
                messages.append(L10n.format(key, url.lastPathComponent))
            }
        }
        if libraryFull { messages.append(L10n.text("The brush library is full.")) }
        return (presets, messages)
    }
}
