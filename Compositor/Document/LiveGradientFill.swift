import AppKit
import CoreGraphics
import Foundation

/// Built-in multi-stop gradient presets for both the Gradient tool and Live Gradient Fill layers.
nonisolated struct GradientPreset: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let stops: [GradientOverlayStop]

    static let builtIn: [GradientPreset] = [
        GradientPreset(id: "black-white", name: "Black to White", stops: [
            GradientOverlayStop(position: 0, red: 0, green: 0, blue: 0, alpha: 1),
            GradientOverlayStop(position: 1, red: 1, green: 1, blue: 1, alpha: 1),
        ]),
        GradientPreset(id: "sunset", name: "Sunset", stops: [
            GradientOverlayStop(position: 0, red: 0.96, green: 0.28, blue: 0.32, alpha: 1),
            GradientOverlayStop(position: 0.5, red: 0.99, green: 0.65, blue: 0.24, alpha: 1),
            GradientOverlayStop(position: 1, red: 0.42, green: 0.16, blue: 0.58, alpha: 1),
        ]),
        GradientPreset(id: "ocean", name: "Ocean", stops: [
            GradientOverlayStop(position: 0, red: 0.05, green: 0.18, blue: 0.46, alpha: 1),
            GradientOverlayStop(position: 0.55, red: 0.08, green: 0.56, blue: 0.72, alpha: 1),
            GradientOverlayStop(position: 1, red: 0.54, green: 0.92, blue: 0.88, alpha: 1),
        ]),
        GradientPreset(id: "spectrum", name: "Spectrum", stops: [
            GradientOverlayStop(position: 0.0, red: 1, green: 0, blue: 0, alpha: 1),
            GradientOverlayStop(position: 0.2, red: 1, green: 1, blue: 0, alpha: 1),
            GradientOverlayStop(position: 0.4, red: 0, green: 1, blue: 0, alpha: 1),
            GradientOverlayStop(position: 0.6, red: 0, green: 1, blue: 1, alpha: 1),
            GradientOverlayStop(position: 0.8, red: 0, green: 0, blue: 1, alpha: 1),
            GradientOverlayStop(position: 1.0, red: 1, green: 0, blue: 1, alpha: 1),
        ]),
    ]
}

/// Non-destructive live Gradient Fill layer parameters (persisted in format v29).
/// Re-renders crisply whenever edited or resized, while storing its raster in `ImageLayer.asset`
/// so all blend modes, masks, effects, and exports work seamlessly.
nonisolated struct LiveGradientFill: Codable, Equatable, Sendable {
    var shape: GradientShape = .linear
    var angle: Double = 90
    var scale: Double = 100
    var reversed: Bool = false
    var stops: [GradientOverlayStop] = GradientPreset.builtIn[0].stops

    var isValid: Bool {
        angle.isFinite && (-360...360).contains(angle)
            && scale.isFinite && (10...200).contains(scale)
            && (2...16).contains(stops.count)
            && stops.allSatisfy(\.isValid)
    }

    var resolvedStops: [StyleGradientStop] {
        let sorted = stops.sorted { $0.position < $1.position }
        let ordered = reversed ? sorted.reversed().map {
            GradientOverlayStop(position: 1 - $0.position, red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha)
        } : sorted
        return ordered.map {
            StyleGradientStop(position: Float($0.position),
                              r: Float($0.red), g: Float($0.green), b: Float($0.blue), a: Float($0.alpha))
        }
    }

    /// Renders this fill across a `width × height` canvas.
    func render(width: Int, height: Int) throws -> CGImage {
        guard isValid, width > 0, height > 0, width * height <= DocumentLimits.maxSurfacePixels else {
            throw ExportError.render
        }
        let ctx = try BrushRaster.context(width: width, height: height, mask: false)
        guard let raw = ctx.data else { throw ExportError.render }
        let bytes = raw.assumingMemoryBound(to: UInt8.self)
        let cx = Float(width) * 0.5
        let cy = Float(height) * 0.5
        let rad = Float(angle * .pi / 180.0)
        let dx = cosf(rad)
        let dy = -sinf(rad)
        let factor = Float(max(0.1, scale / 100.0))
        let halfSpan = max(1, 0.5 * (abs(dx) * Float(width) + abs(dy) * Float(height)) * factor)
        let startX: Float
        let startY: Float
        let endX: Float
        let endY: Float
        switch shape {
        case .linear:
            startX = cx - dx * halfSpan
            startY = cy - dy * halfSpan
            endX = cx + dx * halfSpan
            endY = cy + dy * halfSpan
        case .radial, .angle, .reflected, .diamond:
            startX = cx
            startY = cy
            endX = cx + dx * halfSpan
            endY = cy + dy * halfSpan
        }
        let cStops = resolvedStops
        cStops.withUnsafeBufferPointer { buf in
            gradient_render_fill(bytes, Int32(ctx.bytesPerRow), Int32(width), Int32(height),
                                 startX, startY, endX, endY,
                                 shape.kernelIndex, 1.0, 1,
                                 buf.baseAddress, Int32(buf.count))
        }
        guard let image = ctx.makeImage() else { throw ExportError.render }
        return image
    }
}

extension EditorSession {
    /// Creates a new non-destructive Gradient Fill layer above the active layer and opens its live editor.
    func addGradientFillLayer(_ initial: LiveGradientFill? = nil) {
        guard canEditLayers, let document else { return }
        finishOpacityEdit()
        var fill = initial ?? LiveGradientFill(
            shape: gradientSettings.shape,
            angle: 90,
            scale: 100,
            reversed: gradientSettings.reversed,
            stops: gradientStops(mask: false)
        )
        if !fill.isValid { fill = LiveGradientFill() }
        do {
            let rendered = try fill.render(width: document.width, height: document.height)
            let thumb = try PixelInvert.thumbnail(of: rendered)
            let name = L10n.text("Gradient Fill")
            let asset = ImportedImage(image: rendered, thumbnail: thumb, name: name)
            let parentID = activeLayer.map { $0.isGroup ? $0.id : $0.parentID } ?? nil
            let layer = ImageLayer(id: UUID(), asset: asset, name: name, isVisible: true,
                                   transform: LayerTransform(origin: .zero, size: document.size),
                                   parentID: parentID, isGroup: false,
                                   gradientFill: fill)
            beginEdit("Gradient Fill Layer")
            insertLayerAboveActive(layer)
            activeLayerID = layer.id
            selectedLayerIDs = [layer.id]
            isMaskSelected = false
            endEdit()
        } catch {
            brushError = error.localizedDescription
        }
    }

    /// Updates a live Gradient Fill layer non-destructively in place.
    func updateLiveGradientFill(_ fill: LiveGradientFill, on id: UUID? = nil) {
        guard canEditLayers, fill.isValid, let document,
              let targetID = id ?? activeLayerID,
              let index = document.layers.firstIndex(where: { $0.id == targetID }),
              document.layers[index].gradientFill != nil else { return }
        guard !effectiveLock(for: targetID).blocksPixels else { return }
        do {
            let rendered = try fill.render(width: document.width, height: document.height)
            let thumb = try PixelInvert.thumbnail(of: rendered)
            let name = document.layers[index].name
            let asset = ImportedImage(image: rendered, thumbnail: thumb, name: name)
            beginEdit("Edit Gradient Fill")
            self.document?.layers[index].gradientFill = fill
            self.document?.layers[index].asset = asset
            self.document?.layers[index].transform = LayerTransform(origin: .zero, size: document.size)
            endEdit()
        } catch {
            brushError = error.localizedDescription
        }
    }

    private func insertLayerAboveActive(_ layer: ImageLayer) {
        guard var doc = document else { return }
        if let activeID = activeLayerID, let index = doc.layers.firstIndex(where: { $0.id == activeID }) {
            doc.layers.insert(layer, at: index + 1)
        } else {
            doc.layers.append(layer)
        }
        document = doc
    }
}
