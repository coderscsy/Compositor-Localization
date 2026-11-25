import AppKit
import CoreGraphics

/// Non-destructive vector mask attached to a layer (`.comp` format version 32).
/// Stored in document pixel coordinates so it clips crisply at any zoom or export resolution.
nonisolated struct LayerVectorMask: Codable, Equatable, Sendable {
    var path: VectorPath
    var isEnabled: Bool = true
    var inverted: Bool = false

    var isValid: Bool { path.isValid }

    /// Clips `context` (assumed in `transform` space mapping document coordinates to context coordinates)
    /// to this vector mask. Caller must bracket with `saveGState()` / `restoreGState()`.
    func clipContext(_ context: CGContext, documentSize: CGSize, transform: CGAffineTransform = .identity) {
        guard isEnabled, !path.isEmpty else { return }
        let cg = path.cgPath(transform: transform, closeForFill: true)
        if inverted {
            let outer = CGMutablePath()
            outer.addRect(CGRect(origin: .zero, size: documentSize).applying(transform).insetBy(dx: -4, dy: -4))
            outer.addPath(cg)
            context.addPath(outer)
            context.clip(using: .evenOdd)
        } else {
            context.addPath(cg)
            context.clip(using: .winding)
        }
    }

    /// Rasterizes this vector mask into an 8-bit grayscale mask image (white = visible, black = hidden)
    /// at document resolution `(width, height)`, top-left origin.
    func rasterizedMask(width: Int, height: Int) -> CGImage? {
        guard width >= 1, height >= 1,
              let ctx = try? BrushRaster.context(width: width, height: height, mask: true) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.setFillColor(gray: inverted ? 1 : 0, alpha: 1)
        ctx.fill(bounds)
        guard !path.isEmpty else { return ctx.makeImage() }
        ctx.setShouldAntialias(true)
        ctx.setFillColor(gray: inverted ? 0 : 1, alpha: 1)
        ctx.addPath(path.cgPath(closeForFill: true))
        ctx.fillPath(using: .winding)
        return ctx.makeImage()
    }

    func translated(dx: CGFloat, dy: CGFloat) -> LayerVectorMask {
        var copy = self
        copy.path = path.translated(dx: dx, dy: dy)
        return copy
    }

    func scaled(sx: CGFloat, sy: CGFloat) -> LayerVectorMask {
        var copy = self
        for s in copy.path.subpaths.indices {
            for a in copy.path.subpaths[s].anchors.indices {
                copy.path.subpaths[s].anchors[a].point.x *= sx
                copy.path.subpaths[s].anchors[a].point.y *= sy
                if var h = copy.path.subpaths[s].anchors[a].handleIn {
                    h.x *= sx; h.y *= sy
                    copy.path.subpaths[s].anchors[a].handleIn = h
                }
                if var h = copy.path.subpaths[s].anchors[a].handleOut {
                    h.x *= sx; h.y *= sy
                    copy.path.subpaths[s].anchors[a].handleOut = h
                }
            }
        }
        return copy
    }
}

/// Photoshop-style vector path / shape boolean operations.
nonisolated enum VectorBooleanOperation: String, CaseIterable, Sendable {
    case unite = "Unite"
    case subtract = "Subtract Front"
    case intersect = "Intersect"
    case exclude = "Exclude Overlapping"

    func apply(_ base: CGPath, _ other: CGPath) -> CGPath {
        switch self {
        case .unite: base.union(other)
        case .subtract: base.subtracting(other)
        case .intersect: base.intersection(other)
        case .exclude: base.symmetricDifference(other)
        }
    }
}

extension ImageLayer {
    /// Document-space `CGPath` for a live closed shape layer (accounting for layer origin, size, rotation, and flip).
    nonisolated func documentShapeCGPath() -> CGPath? {
        guard let style = liveShape?.style, style.kind.isClosed else { return nil }
        let size = transform.size
        guard size.width >= 1, size.height >= 1 else { return nil }
        let localBounds = CGRect(origin: .zero, size: size)
        let localPath = style.kind.path(in: localBounds, cornerRadius: style.cornerRadius,
                                        smoothing: style.smoothing == true,
                                        sides: style.effectiveSides, starInnerRatio: style.effectiveStarInnerRatio)
        let center = transform.center
        var t = CGAffineTransform(translationX: center.x, y: center.y)
        if transform.rotation != 0 { t = t.rotated(by: transform.rotation) }
        if transform.flipX || transform.flipY { t = t.scaledBy(x: transform.flipX ? -1 : 1, y: transform.flipY ? -1 : 1) }
        t = t.translatedBy(x: -size.width / 2, y: -size.height / 2)
        return localPath.copy(using: &t)
    }
}

extension EditorSession {
    // MARK: - Vector Mask Operations

    var canAddVectorMask: Bool {
        guard canEditLayers, let layer = activeLayer, !effectiveLock(for: layer.id).blocksStructure else { return false }
        return activePath?.isEmpty == false || selection?.isEmpty == false
    }

    var hasActiveLayerVectorMask: Bool {
        activeLayer?.vectorMask != nil
    }

    /// Attaches a non-destructive vector mask to the active layer from the active path (or active selection if no path is active).
    func addVectorMaskFromActivePath() {
        guard canEditLayers, let layer = activeLayer,
              let index = document?.layers.firstIndex(where: { $0.id == layer.id }),
              !effectiveLock(for: layer.id).blocksStructure else { return }
        let sourcePath: VectorPath?
        if let active = activePath, !active.isEmpty {
            sourcePath = active
        } else if let sel = document?.selection, !sel.isEmpty {
            sourcePath = VectorPath.fromCGPath(sel.path, name: L10n.text("Vector Mask"))
        } else {
            sourcePath = nil
        }
        guard let maskPath = sourcePath, !maskPath.isEmpty else { return }
        finishOpacityEdit()
        beginEdit("Add Vector Mask")
        document?.layers[index].vectorMask = LayerVectorMask(path: maskPath, isEnabled: true, inverted: false)
        endEdit()
    }

    /// Attaches a specific document path as the active layer's vector mask.
    func addVectorMask(from pathID: UUID) {
        guard canEditLayers, let layer = activeLayer,
              let index = document?.layers.firstIndex(where: { $0.id == layer.id }),
              !effectiveLock(for: layer.id).blocksStructure,
              let path = document?.paths.first(where: { $0.id == pathID }), !path.isEmpty else { return }
        finishOpacityEdit()
        beginEdit("Add Vector Mask")
        document?.layers[index].vectorMask = LayerVectorMask(path: path, isEnabled: true, inverted: false)
        endEdit()
    }

    func toggleVectorMaskEnabled() {
        guard canEditLayers, let layer = activeLayer, layer.vectorMask != nil,
              let index = document?.layers.firstIndex(where: { $0.id == layer.id }),
              !effectiveLock(for: layer.id).blocksStructure else { return }
        finishOpacityEdit()
        beginEdit("Toggle Vector Mask")
        document?.layers[index].vectorMask?.isEnabled.toggle()
        endEdit()
    }

    func invertVectorMask() {
        guard canEditLayers, let layer = activeLayer, layer.vectorMask != nil,
              let index = document?.layers.firstIndex(where: { $0.id == layer.id }),
              !effectiveLock(for: layer.id).blocksStructure else { return }
        finishOpacityEdit()
        beginEdit("Invert Vector Mask")
        document?.layers[index].vectorMask?.inverted.toggle()
        endEdit()
    }

    func removeVectorMask() {
        guard canEditLayers, let layer = activeLayer, layer.vectorMask != nil,
              let index = document?.layers.firstIndex(where: { $0.id == layer.id }),
              !effectiveLock(for: layer.id).blocksStructure else { return }
        finishOpacityEdit()
        beginEdit("Remove Vector Mask")
        document?.layers[index].vectorMask = nil
        endEdit()
    }

    /// Converts the active layer's vector mask into an editable pixel `LayerMask` and clears the vector mask.
    func rasterizeVectorMask() {
        guard canEditLayers, let document, let layer = activeLayer,
              let vm = layer.vectorMask,
              let index = document.layers.firstIndex(where: { $0.id == layer.id }),
              !effectiveLock(for: layer.id).blocksStructure,
              let maskImage = vm.rasterizedMask(width: document.width, height: document.height),
              let thumb = try? PixelInvert.thumbnail(of: maskImage) else { return }
        finishOpacityEdit()
        beginEdit("Rasterize Vector Mask")
        let asset = ImportedImage(image: maskImage, thumbnail: thumb, name: L10n.text("Vector Mask"))
        let placement = LayerTransform(origin: .zero, size: document.size)
        self.document?.layers[index].mask = LayerMask(asset: asset, isEnabled: vm.isEnabled, placement: placement, isLinked: true)
        self.document?.layers[index].vectorMask = nil
        endEdit()
    }

    // MARK: - Shape & Path Boolean Operations

    var canCombineSelectedShapes: Bool {
        guard canEditLayers, let document else { return false }
        let selectedShapes = document.layers.filter { selectedLayerIDs.contains($0.id) && $0.liveShape?.style.kind.isClosed == true }
        guard selectedShapes.count >= 2 else { return false }
        return !selectedShapes.contains(where: { effectiveLock(for: $0.id).blocksStructure })
    }

    /// Combines two or more selected closed shape layers using `operation`, creating a new crisp combined layer
    /// (plus saving its resulting vector path) and removing the source shape layers in one undo step.
    func combineSelectedShapes(_ operation: VectorBooleanOperation) {
        guard canEditLayers, let document else { return }
        // Bottom-to-top document order: bottom shape is the base, front shapes combine into/subtract from it.
        let targets = document.layers.filter { selectedLayerIDs.contains($0.id) && $0.liveShape?.style.kind.isClosed == true }
        guard targets.count >= 2, !targets.contains(where: { effectiveLock(for: $0.id).blocksStructure }) else { return }
        guard let baseStyle = targets.first?.liveShape?.style,
              var combined = targets.first?.documentShapeCGPath() else { return }
        for layer in targets.dropFirst() {
            guard let next = layer.documentShapeCGPath() else { continue }
            combined = operation.apply(combined, next)
        }
        let resultBounds = combined.boundingBoxOfPath.integral
        guard !combined.isEmpty, resultBounds.width >= 1, resultBounds.height >= 1 else {
            brushError = L10n.text("The boolean operation produced an empty shape.")
            return
        }
        guard Int(resultBounds.width) * Int(resultBounds.height) <= Self.maxShapePixels else {
            brushError = L10n.format("That shape is too large. A shape can cover up to %lld megapixels.", DocumentLimits.maxSurfaceMegapixels)
            return
        }
        do {
            let strokeW = baseStyle.strokeWidth ?? 0
            let pad = strokeW > 0 ? ceil(strokeW) : 0
            let renderBox = resultBounds.insetBy(dx: -pad, dy: -pad).integral
            let ctx = try BrushRaster.context(width: Int(renderBox.width), height: Int(renderBox.height), mask: false)
            ctx.translateBy(x: -renderBox.minX, y: -renderBox.minY)
            let fillCG = CGColor(srgbRed: baseStyle.red, green: baseStyle.green, blue: baseStyle.blue, alpha: 1)
            let strokeCG = baseStyle.strokeColor.map { CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
            Self.fillShape(combined, color: fillCG, stroke: strokeCG, strokeWidth: strokeW, in: ctx)
            guard let image = ctx.makeImage() else { throw ExportError.render }
            let thumb = try PixelInvert.thumbnail(of: image)
            let resultPath = VectorPath.fromCGPath(combined, name: L10n.format("%@ Shape", L10n.text(operation.rawValue)))
            let targetIDs = Set(targets.map(\.id))
            let topIndex = document.layers.lastIndex(where: { targetIDs.contains($0.id) }) ?? (document.layers.count - 1)
            let parentID = targets.last?.parentID

            finishOpacityEdit()
            beginEdit(operation.rawValue)
            let newLayer = ImageLayer(id: UUID(),
                                      asset: ImportedImage(image: image, thumbnail: thumb, name: operation.rawValue),
                                      name: L10n.format("%@ Shape", L10n.text(operation.rawValue)),
                                      isVisible: true,
                                      transform: LayerTransform(origin: renderBox.origin, size: renderBox.size),
                                      parentID: parentID)
            // Insert right above the topmost target, then remove consumed source layers.
            self.document?.layers.insert(newLayer, at: topIndex + 1)
            self.document?.layers.removeAll { targetIDs.contains($0.id) }
            if !resultPath.isEmpty {
                self.document?.paths.append(resultPath)
                activePathID = resultPath.id
            }
            activeLayerID = newLayer.id
            selectedLayerIDs = [newLayer.id]
            endEdit()
        } catch {
            brushError = error.localizedDescription
        }
    }

    /// Combines two document `VectorPath`s with a boolean operation, appending the resulting `VectorPath`.
    @discardableResult
    func combinePaths(_ baseID: UUID, with otherID: UUID, operation: VectorBooleanOperation) -> UUID? {
        guard let document,
              let a = document.paths.first(where: { $0.id == baseID }),
              let b = document.paths.first(where: { $0.id == otherID }),
              !a.isEmpty, !b.isEmpty else { return nil }
        let resultCG = operation.apply(a.cgPath(closeForFill: true), b.cgPath(closeForFill: true))
        guard !resultCG.isEmpty else { return nil }
        let name = L10n.format("%@ Path", L10n.text(operation.rawValue))
        let result = VectorPath.fromCGPath(resultCG, name: name)
        guard !result.isEmpty else { return nil }
        return addNewPath(name: result.name, subpaths: result.subpaths)
    }
}
