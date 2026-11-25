import AppKit
import CoreGraphics
import Foundation

/// Blend modes available on painting tools (Brush and Paint Bucket), matching Photoshop's tool blend modes.
nonisolated enum BrushBlendMode: String, Codable, CaseIterable, Sendable {
    case normal = "Normal"
    case multiply = "Multiply"
    case screen = "Screen"
    case overlay = "Overlay"
    case softLight = "Soft Light"
    case hardLight = "Hard Light"
    case darken = "Darken"
    case lighten = "Lighten"
    case colorDodge = "Color Dodge"
    case colorBurn = "Color Burn"
    case behind = "Behind"
    case clear = "Clear"

    /// Kernel index for `style_blend_solid` (nil for `.behind` and `.clear`, which use Porter-Duff alpha rules).
    var styleKernelIndex: Int32? {
        switch self {
        case .normal: 0
        case .multiply: 1
        case .screen: 2
        case .overlay: 3
        case .softLight: 4
        case .hardLight: 5
        case .darken: 6
        case .lighten: 7
        case .colorDodge: 8
        case .colorBurn: 9
        case .behind, .clear: nil
        }
    }
}

/// Built-in Photoshop-style brush tip presets.
nonisolated struct BrushPreset: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let diameter: CGFloat
    let hardness: CGFloat
    let opacity: CGFloat
    let flow: CGFloat
    let roundness: CGFloat
    let angle: CGFloat
    let spacing: CGFloat
    let scatter: CGFloat
    let airbrush: Bool

    static let builtIn: [BrushPreset] = [
        BrushPreset(id: "soft-round", name: "Soft Round", diameter: 60, hardness: 0, opacity: 1, flow: 1,
                    roundness: 1, angle: 0, spacing: 0.10, scatter: 0, airbrush: false),
        BrushPreset(id: "hard-round", name: "Hard Round", diameter: 40, hardness: 1, opacity: 1, flow: 1,
                    roundness: 1, angle: 0, spacing: 0.05, scatter: 0, airbrush: false),
        BrushPreset(id: "airbrush-soft", name: "Airbrush Soft", diameter: 80, hardness: 0, opacity: 1, flow: 0.20,
                    roundness: 1, angle: 0, spacing: 0.12, scatter: 0, airbrush: true),
        BrushPreset(id: "calligraphy-flat", name: "Calligraphy Flat", diameter: 36, hardness: 1, opacity: 1, flow: 1,
                    roundness: 0.28, angle: 35, spacing: 0.04, scatter: 0, airbrush: false),
        BrushPreset(id: "dry-charcoal", name: "Dry Charcoal", diameter: 48, hardness: 0.65, opacity: 0.85, flow: 0.35,
                    roundness: 0.65, angle: -20, spacing: 0.16, scatter: 0.18, airbrush: false),
        BrushPreset(id: "spatter", name: "Spatter", diameter: 32, hardness: 0.85, opacity: 0.9, flow: 0.65,
                    roundness: 0.85, angle: 0, spacing: 0.45, scatter: 0.75, airbrush: false),
    ]
}

/// Modes grouped under the Fill / Gradient tool (`G`).
nonisolated enum FillToolMode: String, CaseIterable, Sendable {
    case gradient = "Gradient"
    case paintBucket = "Paint Bucket"
}

nonisolated struct PaintBucketSettings: Equatable, Sendable {
    var tolerance: Int = 32
    var contiguous: Bool = true
    var sampleAllLayers: Bool = false
    var opacity: CGFloat = 1
    var blendMode: BrushBlendMode = .normal
}

extension EditorSession {
    func applyBrushPreset(_ preset: BrushPreset) {
        brushSettings.diameter = preset.diameter
        brushSettings.hardness = preset.hardness
        brushSettings.opacity = preset.opacity
        brushSettings.flow = preset.flow
        brushSettings.roundness = preset.roundness
        brushSettings.angle = preset.angle
        brushSettings.spacing = preset.spacing
        brushSettings.scatter = preset.scatter
        brushSettings.airbrush = preset.airbrush
        brushSettings.antialiased = true
        brushPresetID = preset.id
    }

    func startAirbrushTimer(at point: CGPoint, pressure: CGFloat) {
        stopAirbrushTimer()
        guard tool == .brush, brushSettings.airbrush, brushStroke != nil else { return }
        airbrushPoint = point
        airbrushPressure = pressure
        airbrushTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let stroke = self.brushStroke, self.brushSettings.airbrush else {
                    self?.stopAirbrushTimer()
                    return
                }
                do {
                    try stroke.airbrushPulse(at: self.airbrushPoint, pressure: self.airbrushPressure)
                    self.brushRevision += 1
                    self.refreshCanvasPreview?()
                } catch {
                    self.stopAirbrushTimer()
                }
            }
        }
    }

    func stopAirbrushTimer() {
        airbrushTimer?.invalidate()
        airbrushTimer = nil
    }

    /// Flood-fills matching pixels starting at `point` (document pixels) on the active layer or mask.
    func applyPaintBucket(at point: CGPoint) {
        guard canPaint, let layer = activeLayer, let document else {
            brushError = paintRefusal
            return
        }
        let width = document.width, height = document.height
        let seedX = Int(floor(point.x)), seedY = Int(floor(point.y))
        guard (0..<width).contains(seedX), (0..<height).contains(seedY) else { return }
        finishOpacityEdit()
        pauseGIFForEditing(for: layer.id)

        do {
            // 1. Render sampling image in document pixels (either active layer/mask alone, or all visible layers).
            let sampleCtx = try BrushRaster.context(width: width, height: height, mask: false)
            sampleCtx.clear(CGRect(x: 0, y: 0, width: width, height: height))
            if isMaskSelected {
                if let mask = selectedMask(for: layer) {
                    let bg = LayerMask.background(of: mask.asset.thumbnail)
                    sampleCtx.setFillColor(CGColor(srgbRed: bg, green: bg, blue: bg, alpha: 1))
                    sampleCtx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    let placed = displayedMaskPlacement(for: layer) ?? displayedTransform(for: layer)
                    LayerRenderer.draw(mask.asset.image, transform: placed, center: placed.center, in: sampleCtx)
                }
            } else if paintBucketSettings.sampleAllLayers {
                drawLiveComposite(document, in: sampleCtx)
            } else if let asset = displayedAsset(for: layer) {
                let transform = displayedTransform(for: layer)
                LayerRenderer.draw(asset.image, transform: transform, center: transform.center, in: sampleCtx)
            }
            guard let sampleData = sampleCtx.data?.assumingMemoryBound(to: UInt8.self) else { throw ExportError.render }

            // 2. Run C flood-fill matcher (`wand_mask`).
            let maskCtx = try BrushRaster.context(width: width, height: height, mask: true)
            guard let maskBytes = maskCtx.data?.assumingMemoryBound(to: UInt8.self) else { throw ExportError.render }
            let count = wand_mask(sampleData, width, height, sampleCtx.bytesPerRow,
                                  seedX, seedY, 0,
                                  Int32(min(255, max(0, paintBucketSettings.tolerance))),
                                  paintBucketSettings.contiguous ? 1 : 0,
                                  maskBytes)
            guard count > 0 else { return }

            // Intersect with active selection if present.
            if let clip = try selection?.clip(canvas: document.size) {
                let selCtx = try BrushRaster.context(width: width, height: height, mask: true)
                selCtx.setFillColor(gray: 0, alpha: 1)
                selCtx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                selCtx.saveGState()
                clip.apply(to: selCtx)
                selCtx.setFillColor(gray: 1, alpha: 1)
                selCtx.fill(CGRect(x: 0, y: 0, width: width, height: height))
                selCtx.restoreGState()
                if let selBytes = selCtx.data?.assumingMemoryBound(to: UInt8.self) {
                    for i in 0..<(width * height) {
                        maskBytes[i] = UInt8((Int(maskBytes[i]) * Int(selBytes[i]) + 127) / 255)
                    }
                }
            }
            guard let fillMask = maskCtx.makeImage() else { throw ExportError.render }

            // 3. Apply fill to the active layer or mask.
            let canvasRect = CGRect(x: 0, y: 0, width: width, height: height)
            let lockTransparent = !isMaskSelected && effectiveLock(for: layer.id).locksTransparentPixels
            let mode = isMaskSelected ? .normal : paintBucketSettings.blendMode
            let alpha = min(1, max(0.01, paintBucketSettings.opacity))
            let color = isMaskSelected
                ? PaletteColor(red: maskPaintWhite ? 1 : 0, green: maskPaintWhite ? 1 : 0, blue: maskPaintWhite ? 1 : 0)
                : foregroundColor

            if isMaskSelected {
                let targetCtx = try BrushRaster.context(width: width, height: height, mask: true)
                let bg = selectedMask(for: layer).map { LayerMask.background(of: $0.asset.thumbnail) } ?? 1
                targetCtx.setFillColor(gray: bg, alpha: 1)
                targetCtx.fill(canvasRect)
                if let existing = selectedMask(for: layer) {
                    let placed = displayedMaskPlacement(for: layer) ?? displayedTransform(for: layer)
                    LayerRenderer.draw(existing.asset.image, transform: placed, center: placed.center, in: targetCtx)
                }
                BrushRaster.fill(CGColor(gray: color.red, alpha: 1), coverage: fillMask, in: canvasRect, alpha: alpha, context: targetCtx)
                guard let result = targetCtx.makeImage() else { throw ExportError.render }
                let maskAsset = try LayerMask.asset(from: result)
                beginEdit("Paint Bucket")
                if let index = self.document?.layers.firstIndex(where: { $0.id == layer.id }) {
                    let prev = self.document?.layers[index].mask
                    self.document?.layers[index].mask = LayerMask(
                        asset: maskAsset,
                        isEnabled: prev?.isEnabled ?? true,
                        placement: LayerTransform(origin: .zero, size: document.size),
                        isLinked: prev?.isLinked ?? true
                    )
                }
                endEdit()
                return
            }

            let targetCtx = try BrushRaster.context(width: width, height: height, mask: false)
            targetCtx.clear(canvasRect)
            if let existing = displayedAsset(for: layer) {
                let transform = displayedTransform(for: layer)
                LayerRenderer.draw(existing.image, transform: transform, center: transform.center, in: targetCtx)
            }
            guard let dstRaw = targetCtx.data else { throw ExportError.render }
            let dstBytes = dstRaw.assumingMemoryBound(to: UInt8.self)

            // Extract existing alpha if transparency is locked.
            var clipCtx: CGContext?
            var clipBytes: UnsafeMutablePointer<UInt8>?
            if lockTransparent {
                let c = try BrushRaster.context(width: width, height: height, mask: true)
                let cb = c.data!.assumingMemoryBound(to: UInt8.self)
                layer_extract_alpha(dstBytes, targetCtx.bytesPerRow, cb, c.bytesPerRow, width, height)
                clipCtx = c
                clipBytes = cb
            }

            switch mode {
            case .behind:
                if !lockTransparent {
                    targetCtx.saveGState()
                    targetCtx.setBlendMode(.destinationOver)
                    BrushRaster.fill(color.nsColor.cgColor, coverage: fillMask, in: canvasRect, alpha: alpha, context: targetCtx)
                    targetCtx.restoreGState()
                }
            case .clear:
                targetCtx.saveGState()
                if lockTransparent {
                    targetCtx.setBlendMode(.sourceAtop)
                    BrushRaster.fill(backgroundColor.nsColor.cgColor, coverage: fillMask, in: canvasRect, alpha: alpha, context: targetCtx)
                } else {
                    targetCtx.setBlendMode(.destinationOut)
                    BrushRaster.fill(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), coverage: fillMask, in: canvasRect, alpha: alpha, context: targetCtx)
                }
                targetCtx.restoreGState()
            default:
                if let kIndex = mode.styleKernelIndex {
                    style_blend_solid(dstBytes, Int32(targetCtx.bytesPerRow),
                                      maskBytes, Int32(maskCtx.bytesPerRow),
                                      clipBytes, Int32(clipCtx?.bytesPerRow ?? 0),
                                      Int32(width), Int32(height),
                                      Float(color.red), Float(color.green), Float(color.blue),
                                      Float(alpha), kIndex)
                }
            }
            _ = clipCtx

            guard let fullImage = targetCtx.makeImage() else { throw ExportError.render }
            let newAsset = try ImportedImage.fromRendered(fullImage, name: layer.name)
            let newTransform = LayerTransform(origin: .zero, size: document.size)
            let edited = try layerByEditingPixels(layer, asset: newAsset, transform: newTransform, mask: layer.mask)
            beginEdit("Paint Bucket")
            if let index = self.document?.layers.firstIndex(where: { $0.id == layer.id }) {
                self.document?.layers[index] = edited
            }
            endEdit()
        } catch {
            brushError = error.localizedDescription
        }
    }
}

private extension ImportedImage {
    static func fromRendered(_ image: CGImage, name: String) throws -> ImportedImage {
        let thumb = try PixelInvert.thumbnail(of: image)
        return ImportedImage(image: image, thumbnail: thumb, name: name)
    }
}
