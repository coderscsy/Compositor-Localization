import AppKit
import CoreGraphics
import CoreImage

/// Composition guide overlays drawn inside the active crop frame.
nonisolated enum CropOverlayStyle: String, CaseIterable, Sendable {
    case ruleOfThirds = "Rule of Thirds"
    case goldenRatio = "Golden Ratio"
    case diagonal = "Diagonal"
    case grid = "Grid"
    case none = "None"
}

/// Four document-space corners for Perspective Crop (`[topLeft, topRight, bottomRight, bottomLeft]`).
nonisolated struct CropPerspectiveQuad: Equatable, Sendable {
    var corners: [CGPoint] // 4 points: TL, TR, BR, BL in document coordinates (top-left origin).

    init(rect: CGRect) {
        corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
    }

    init(corners: [CGPoint]) {
        self.corners = corners
    }

    var isValid: Bool {
        guard corners.count == 4, corners.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return false }
        let size = outputSize
        return size.width >= 2 && size.height >= 2
            && size.width <= DocumentLimits.maxSideExtent && size.height <= DocumentLimits.maxSideExtent
            && size.width * size.height <= DocumentLimits.maxSurfaceExtent
    }

    /// Natural upright output dimensions from average top/bottom width and left/right height.
    var outputSize: CGSize {
        guard corners.count == 4 else { return .zero }
        let top = hypot(corners[1].x - corners[0].x, corners[1].y - corners[0].y)
        let bottom = hypot(corners[2].x - corners[3].x, corners[2].y - corners[3].y)
        let left = hypot(corners[3].x - corners[0].x, corners[3].y - corners[0].y)
        let right = hypot(corners[2].x - corners[1].x, corners[2].y - corners[1].y)
        return CGSize(width: max(1, ((top + bottom) / 2).rounded()),
                      height: max(1, ((left + right) / 2).rounded()))
    }
}

/// Interactive horizon line drawn with the Straighten tool inside Crop.
struct CropStraightenLine: Equatable, Sendable {
    var start: CGPoint
    var end: CGPoint

    /// Leveling rotation angle in degrees (-45…45) that brings this line horizontal or vertical (whichever is closer).
    var angleDegrees: Double {
        CropProcessor.straightenAngle(from: start, to: end)
    }
}

/// Executes rotated crops, destructive pixel trimming, and 4-corner Perspective Crop rectification.
nonisolated enum CropProcessor {
    private static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    /// Returns the leveling angle in degrees (`-45...45`) that aligns the drawn horizon/vertical line to the nearest axis.
    static func straightenAngle(from start: CGPoint, to end: CGPoint) -> Double {
        let dx = Double(end.x - start.x), dy = Double(end.y - start.y)
        guard hypot(dx, dy) > 2 else { return 0 }
        var deg = atan2(dy, dx) * 180 / .pi
        // Snap deviation to the nearest 90° axis (so drawing along a nearly horizontal OR nearly vertical edge works).
        let nearestAxis = (deg / 90.0).rounded() * 90.0
        deg -= nearestAxis
        return max(-45, min(45, deg))
    }

    /// Applies crop `rect`, optional `angleDegrees` rotation, and optional destructive pixel deletion.
    static func applyCrop(_ snapshot: ProjectSnapshot, rect: CGRect, angleDegrees: Double,
                          deleteCroppedPixels: Bool) async throws -> ProjectSnapshot {
        let clampedAngle = max(-45, min(45, angleDegrees.isFinite ? angleDegrees : 0))
        let width = max(1, Int(rect.width.rounded()))
        let height = max(1, Int(rect.height.rounded()))
        guard (1...DocumentLimits.maxSide).contains(width), (1...DocumentLimits.maxSide).contains(height),
              width * height <= DocumentLimits.maxSurfacePixels else { throw ProjectError.tooLarge }

        // Fast path: axis-aligned non-destructive crop uses CanvasResizer directly.
        if abs(clampedAngle) < 0.001 && !deleteCroppedPixels {
            return try await CanvasResizer.shared.resize(snapshot,
                to: CanvasSizeOptions(width: width, height: height,
                                      contentOffset: CGPoint(x: -rect.minX, y: -rect.minY)))
        }

        let old = snapshot.manifest
        let rad = CGFloat(-clampedAngle * .pi / 180.0)
        let cosA = cos(rad), sinA = sin(rad)
        let cropCenter = CGPoint(x: rect.midX, y: rect.midY)
        let newCenter = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)

        func mapPoint(_ p: CGPoint) -> CGPoint {
            let dx = p.x - cropCenter.x, dy = p.y - cropCenter.y
            return CGPoint(x: newCenter.x + dx * cosA - dy * sinA,
                           y: newCenter.y + dx * sinA + dy * cosA)
        }

        var manifest = ProjectManifest(
            resolution: old.resolution, documentID: old.documentID,
            width: width, height: height, activeLayerID: old.activeLayerID, layers: [],
            guides: abs(clampedAngle) < 0.001 ? old.guides?.map { $0.offset(x: -rect.minX, y: -rect.minY) } : nil,
            paths: old.paths
        )
        var images = snapshot.images
        let masks = snapshot.masks
        let animations = snapshot.animations

        for layer in old.layers {
            var transform = layer.transform
            let oldCenter = transform.center
            let movedCenter = mapPoint(oldCenter)
            transform.origin = CGPoint(x: movedCenter.x - transform.size.width / 2,
                                       y: movedCenter.y - transform.size.height / 2)
            transform.rotation += rad
            guard transform.isValid else { throw ProjectError.tooLarge }

            let movedMaskPlacement = layer.maskPlacement.map { mp -> LayerTransform in
                var moved = mp
                let mc = mapPoint(mp.center)
                moved.origin = CGPoint(x: mc.x - mp.size.width / 2, y: mc.y - mp.size.height / 2)
                moved.rotation += rad
                return moved
            }

            var finalTransform = transform
            var finalShape = layer.shape
            var finalText = layer.text
            var finalGradient = layer.gradientFill

            // Destructive crop: clip raster pixel layers strictly to the new canvas bounds.
            if deleteCroppedPixels, layer.isGroup != true, layer.adjustment == nil,
               let asset = images[layer.id] {
                let ctx = try BrushRaster.context(width: width, height: height, mask: false)
                LayerRenderer.draw(asset.image, transform: transform, center: transform.center, in: ctx)
                if let croppedImg = ctx.makeImage(),
                   let trimmed = trimToOpaqueBounds(croppedImg) {
                    let thumb = try PixelInvert.thumbnail(of: trimmed.image)
                    images[layer.id] = ImportedImage(image: trimmed.image, thumbnail: thumb, name: asset.name)
                    finalTransform = LayerTransform(origin: trimmed.origin, size: CGSize(width: trimmed.image.width, height: trimmed.image.height))
                    finalShape = nil
                    finalText = nil
                    finalGradient = nil
                } else {
                    let emptyCtx = try BrushRaster.context(width: 1, height: 1, mask: false)
                    if let emptyImg = emptyCtx.makeImage() {
                        let thumb = try PixelInvert.thumbnail(of: emptyImg)
                        images[layer.id] = ImportedImage(image: emptyImg, thumbnail: thumb, name: asset.name)
                        finalTransform = LayerTransform(origin: .zero, size: CGSize(width: 1, height: 1))
                        finalShape = nil
                        finalText = nil
                        finalGradient = nil
                    }
                }
            }
            manifest.layers.append(ProjectLayerRecord(
                id: layer.id, name: layer.name, isVisible: layer.isVisible, transform: finalTransform,
                imageFile: layer.imageFile, parentID: layer.parentID, isGroup: layer.isGroup,
                opacity: layer.opacity, fillOpacity: layer.fillOpacity, blendMode: layer.blendMode,
                folderIsolated: layer.folderIsolated, blendIf: layer.blendIf, lock: layer.lock,
                maskFile: layer.maskFile, maskEnabled: layer.maskEnabled, maskSourceID: layer.maskSourceID,
                adjustment: layer.adjustment, maskPlacement: movedMaskPlacement, maskLinked: layer.maskLinked,
                shape: finalShape, effects: layer.effects, text: finalText, gradientFill: finalGradient,
                vectorMask: abs(clampedAngle) < 0.001 ? layer.vectorMask?.translated(dx: -rect.minX, dy: -rect.minY) : layer.vectorMask,
                gif: layer.gif
            ))
        }
        return ProjectSnapshot(manifest: manifest, images: images, masks: masks, animations: animations)
    }

    /// Rectifies the document using the 4 corners of `quad` via Core Image `CIPerspectiveCorrection`.
    static func applyPerspectiveCrop(_ snapshot: ProjectSnapshot, quad: CropPerspectiveQuad) async throws -> ProjectSnapshot {
        guard quad.isValid else { throw ProjectError.invalid }
        let outSize = quad.outputSize
        let outW = Int(outSize.width), outH = Int(outSize.height)
        let old = snapshot.manifest
        let docW = old.width, docH = old.height

        // Convert top-left document coordinates into Core Image bottom-left coordinates.
        func ciVec(_ pt: CGPoint) -> CIVector {
            CIVector(x: pt.x, y: CGFloat(docH) - pt.y)
        }
        let tl = ciVec(quad.corners[0])
        let tr = ciVec(quad.corners[1])
        let br = ciVec(quad.corners[2])
        let bl = ciVec(quad.corners[3])

        func rectify(_ cgImage: CGImage) throws -> CGImage {
            let input = CIImage(cgImage: cgImage)
            guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { throw ExportError.render }
            filter.setValue(input, forKey: kCIInputImageKey)
            filter.setValue(tl, forKey: "inputTopLeft")
            filter.setValue(tr, forKey: "inputTopRight")
            filter.setValue(br, forKey: "inputBottomRight")
            filter.setValue(bl, forKey: "inputBottomLeft")
            guard let corrected = filter.outputImage else { throw ExportError.render }
            let ext = corrected.extent
            guard ext.width > 0, ext.height > 0 else { throw ExportError.render }
            let sx = CGFloat(outW) / ext.width
            let sy = CGFloat(outH) / ext.height
            let scaled = corrected
                .transformed(by: CGAffineTransform(translationX: -ext.minX, y: -ext.minY))
                .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            guard let rendered = ciContext.createCGImage(scaled, from: CGRect(x: 0, y: 0, width: outW, height: outH)) else {
                throw ExportError.render
            }
            return rendered
        }

        var manifest = ProjectManifest(
            resolution: old.resolution, documentID: old.documentID,
            width: outW, height: outH, activeLayerID: old.activeLayerID, layers: [], guides: nil, paths: nil
        )
        var images: [UUID: ImportedImage] = [:]
        let masks: [UUID: ImportedImage] = [:]

        for layer in old.layers {
            if layer.isGroup == true || layer.adjustment != nil {
                manifest.layers.append(ProjectLayerRecord(
                    id: layer.id, name: layer.name, isVisible: layer.isVisible,
                    transform: LayerTransform(origin: .zero, size: outSize),
                    imageFile: layer.imageFile, parentID: layer.parentID, isGroup: layer.isGroup,
                    opacity: layer.opacity, fillOpacity: layer.fillOpacity, blendMode: layer.blendMode,
                    folderIsolated: layer.folderIsolated, blendIf: layer.blendIf, lock: layer.lock,
                    maskFile: nil, maskEnabled: nil, maskSourceID: layer.maskSourceID,
                    adjustment: layer.adjustment, maskPlacement: nil, maskLinked: nil,
                    shape: nil, effects: layer.effects, text: nil, gradientFill: nil, vectorMask: nil, gif: nil
                ))
                continue
            }
            if let asset = snapshot.images[layer.id] {
                let canvasCtx = try BrushRaster.context(width: docW, height: docH, mask: false)
                LayerRenderer.draw(asset.image, transform: layer.transform, center: layer.transform.center, in: canvasCtx)
                guard let placed = canvasCtx.makeImage() else { throw ExportError.render }
                let rectified = try rectify(placed)
                let thumb = try PixelInvert.thumbnail(of: rectified)
                images[layer.id] = ImportedImage(image: rectified, thumbnail: thumb, name: asset.name)
            }
            manifest.layers.append(ProjectLayerRecord(
                id: layer.id, name: layer.name, isVisible: layer.isVisible,
                transform: LayerTransform(origin: .zero, size: outSize),
                imageFile: layer.imageFile, parentID: layer.parentID, isGroup: layer.isGroup,
                opacity: layer.opacity, fillOpacity: layer.fillOpacity, blendMode: layer.blendMode,
                folderIsolated: layer.folderIsolated, blendIf: layer.blendIf, lock: layer.lock,
                maskFile: nil, maskEnabled: nil, maskSourceID: layer.maskSourceID,
                adjustment: nil, maskPlacement: nil, maskLinked: nil,
                shape: nil, effects: layer.effects, text: nil, gradientFill: nil, vectorMask: nil, gif: nil
            ))
        }
        return ProjectSnapshot(manifest: manifest, images: images, masks: masks, animations: [:])
    }

    private static func trimToOpaqueBounds(_ image: CGImage) -> (image: CGImage, origin: CGPoint)? {
        let w = image.width, h = image.height
        guard let ctx = try? BrushRaster.context(width: w, height: h, mask: false) else { return nil }
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h), mask: false, context: ctx)
        guard let ptr = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = ptr + y * ctx.bytesPerRow
            for x in 0..<w where row[x * 4 + 3] > 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard minX <= maxX, minY <= maxY else { return nil }
        let cropBox = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = image.cropping(to: cropBox) else { return nil }
        return (cropped, cropBox.origin)
    }
}
