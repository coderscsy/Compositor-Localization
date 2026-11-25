import AppKit
import CoreGraphics

/// A named user-created document snapshot stored in the History panel.
struct HistoryDocumentSnapshot: Identifiable, Equatable {
    let id: UUID
    var name: String
    let timestamp: Date
    let document: CanvasDocument
    let activeLayerID: UUID?

    init(id: UUID = UUID(), name: String, timestamp: Date = Date(), document: CanvasDocument, activeLayerID: UUID?) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.document = document
        self.activeLayerID = activeLayerID
    }
}

/// Live cursor coordinates and sampled RGBA / Hex / HSB / CMYK pixel readout for the Info panel.
nonisolated struct PointerColorInfo: Equatable, Sendable {
    let point: CGPoint
    let r: Int
    let g: Int
    let b: Int
    let a: Int

    var hex: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }

    var hsb: (h: Int, s: Int, b: Int) {
        let rf = Double(r) / 255.0, gf = Double(g) / 255.0, bf = Double(b) / 255.0
        let maxC = max(rf, gf, bf), minC = min(rf, gf, bf)
        let delta = maxC - minC
        var hue: Double = 0
        if delta > 1e-6 {
            if maxC == rf { hue = 60.0 * (((gf - bf) / delta).truncatingRemainder(dividingBy: 6.0)) }
            else if maxC == gf { hue = 60.0 * (((bf - rf) / delta) + 2.0) }
            else { hue = 60.0 * (((rf - gf) / delta) + 4.0) }
            if hue < 0 { hue += 360.0 }
        }
        let sat = maxC > 1e-6 ? (delta / maxC) * 100.0 : 0
        let bri = maxC * 100.0
        return (Int(hue.rounded()) % 360, Int(sat.rounded()), Int(bri.rounded()))
    }

    var cmyk: (c: Int, m: Int, y: Int, k: Int) {
        let rf = Double(r) / 255.0, gf = Double(g) / 255.0, bf = Double(b) / 255.0
        let k = 1.0 - max(rf, gf, bf)
        if k >= 0.9999 { return (0, 0, 0, 100) }
        let c = (1.0 - rf - k) / (1.0 - k)
        let m = (1.0 - gf - k) / (1.0 - k)
        let y = (1.0 - bf - k) / (1.0 - k)
        return (Int((c * 100).rounded()), Int((m * 100).rounded()), Int((y * 100).rounded()), Int((k * 100).rounded()))
    }
}

/// Display channel modes for the persistent Histogram panel.
nonisolated enum HistogramChannel: String, CaseIterable, Sendable {
    case rgb = "RGB"
    case luminosity = "Luminosity"
    case red = "Red"
    case green = "Green"
    case blue = "Blue"
    case colors = "Colors"
}

/// Computed 256-bin channel histograms and summary statistics.
nonisolated struct HistogramStats: Equatable, Sendable {
    let red: [Int]
    let green: [Int]
    let blue: [Int]
    let luminosity: [Int]
    let pixelCount: Int

    struct Summary: Equatable, Sendable {
        let mean: Double
        let stdDev: Double
        let median: Int
    }

    func bins(for channel: HistogramChannel) -> [Int] {
        switch channel {
        case .red: red
        case .green: green
        case .blue: blue
        case .luminosity: luminosity
        case .rgb, .colors:
            (0..<256).map { (red[$0] + green[$0] + blue[$0]) / 3 }
        }
    }

    func summary(for channel: HistogramChannel) -> Summary {
        let hist = bins(for: channel)
        let total = hist.reduce(0, +)
        guard total > 0 else { return Summary(mean: 0, stdDev: 0, median: 0) }
        var sum = 0.0
        for (i, count) in hist.enumerated() { sum += Double(i) * Double(count) }
        let mean = sum / Double(total)
        var varSum = 0.0
        for (i, count) in hist.enumerated() {
            let d = Double(i) - mean
            varSum += d * d * Double(count)
        }
        let stdDev = sqrt(varSum / Double(total))
        let half = total / 2
        var accum = 0
        var median = 0
        for (i, count) in hist.enumerated() {
            accum += count
            if accum >= half { median = i; break }
        }
        return Summary(mean: mean, stdDev: stdDev, median: median)
    }

    /// Computes RGB and Rec.709 Luminosity histograms from a rendered CGImage (downsampled if very large for snappy UI).
    static func compute(from image: CGImage) -> HistogramStats {
        let maxSide = 512
        let scale = min(1.0, Double(maxSide) / Double(max(1, max(image.width, image.height))))
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        guard let ctx = try? BrushRaster.context(width: w, height: h, mask: false) else {
            return HistogramStats(red: Array(repeating: 0, count: 256),
                                  green: Array(repeating: 0, count: 256),
                                  blue: Array(repeating: 0, count: 256),
                                  luminosity: Array(repeating: 0, count: 256),
                                  pixelCount: 0)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let ptr = ctx.data?.assumingMemoryBound(to: UInt8.self) else {
            return HistogramStats(red: Array(repeating: 0, count: 256),
                                  green: Array(repeating: 0, count: 256),
                                  blue: Array(repeating: 0, count: 256),
                                  luminosity: Array(repeating: 0, count: 256),
                                  pixelCount: 0)
        }
        var rBins = [Int](repeating: 0, count: 256)
        var gBins = [Int](repeating: 0, count: 256)
        var bBins = [Int](repeating: 0, count: 256)
        var lBins = [Int](repeating: 0, count: 256)
        var count = 0
        let stride = ctx.bytesPerRow
        for y in 0..<h {
            let row = ptr + y * stride
            for x in 0..<w {
                let a = Int(row[x * 4 + 3])
                guard a > 0 else { continue }
                let r = min(255, Int(row[x * 4]) * 255 / a)
                let g = min(255, Int(row[x * 4 + 1]) * 255 / a)
                let b = min(255, Int(row[x * 4 + 2]) * 255 / a)
                let lum = min(255, max(0, Int((0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)).rounded())))
                rBins[r] += 1
                gBins[g] += 1
                bBins[b] += 1
                lBins[lum] += 1
                count += 1
            }
        }
        return HistogramStats(red: rBins, green: gBins, blue: bBins, luminosity: lBins, pixelCount: count)
    }
}

extension EditorSession {
    // MARK: - History Panel Jump & Snapshots

    /// Jumps directly to `step` (0 = initial state, `history.pastNames.count` = current state, up to `history.totalSteps`).
    func jumpToHistoryStep(_ step: Int) {
        guard canEditLayers, let snap = history.jumpTo(step: step) else { return }
        cancelCrop()
        cancelMeshWarp()
        transformEdit = nil
        document = snap.document
        activeLayerID = snap.activeLayerID
        if let id = snap.activeLayerID { selectedLayerIDs = [id] } else { selectedLayerIDs = [] }
        brushRevision += 1
    }

    @discardableResult
    func createHistorySnapshot(name: String? = nil) -> UUID? {
        guard let document else { return nil }
        let title = name ?? L10n.format("Snapshot %lld", historySnapshots.count + 1)
        let snap = HistoryDocumentSnapshot(name: title, document: document, activeLayerID: activeLayerID)
        historySnapshots.append(snap)
        return snap.id
    }

    func restoreHistorySnapshot(_ id: UUID) {
        guard canEditLayers, let snap = historySnapshots.first(where: { $0.id == id }) else { return }
        finishOpacityEdit()
        cancelCrop()
        cancelMeshWarp()
        transformEdit = nil
        beginEdit(L10n.format("Restore %@", snap.name))
        document = snap.document
        activeLayerID = snap.activeLayerID
        if let active = snap.activeLayerID { selectedLayerIDs = [active] } else { selectedLayerIDs = [] }
        endEdit()
    }

    func deleteHistorySnapshot(_ id: UUID) {
        historySnapshots.removeAll { $0.id == id }
    }

    // MARK: - Live Histogram Refresh

    func refreshHistogram() async {
        guard let snapshot = projectSnapshot() else {
            histogramStats = nil
            return
        }
        guard let rendered = try? await ImageExporter.shared.render(snapshot) else { return }
        let image = rendered.image
        let stats = await Task.detached(priority: .utility) {
            HistogramStats.compute(from: image)
        }.value
        histogramStats = stats
    }
}
