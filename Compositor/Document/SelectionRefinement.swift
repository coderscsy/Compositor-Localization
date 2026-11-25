import AppKit
import CoreGraphics
import CoreImage

/// Translates an 8-bit grayscale mask buffer (width × height, 255 = selected) into a crisp `CGPath` via `wand_trace`.
nonisolated enum MaskOutlineTracer {
    static func trace(mask: [UInt8], width: Int, height: Int, threshold: UInt8 = 128) -> CGPath {
        guard width >= 1, height >= 1, mask.count == width * height else { return CGMutablePath() }
        var binary = [UInt8](repeating: 0, count: mask.count)
        for i in 0..<mask.count where mask[i] >= threshold { binary[i] = 255 }
        var pts: UnsafeMutablePointer<Int32>?
        var ptCount: size_t = 0
        var loops: UnsafeMutablePointer<Int32>?
        var loopCount: size_t = 0
        let status = binary.withUnsafeBufferPointer { buf in
            wand_trace(buf.baseAddress, width, height, &pts, &ptCount, &loops, &loopCount)
        }
        defer {
            if let pts { free(pts) }
            if let loops { free(loops) }
        }
        guard status == 0, let pts, let loops, loopCount > 0 else { return CGMutablePath() }
        let path = CGMutablePath()
        var cursor = 0
        for l in 0..<loopCount {
            let count = Int(loops[l])
            guard count >= 3, cursor + count <= ptCount else { continue }
            for i in 0..<count {
                let px = CGFloat(pts[(cursor + i) * 2])
                let py = CGFloat(pts[(cursor + i) * 2 + 1])
                if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
                else { path.addLine(to: CGPoint(x: px, y: py)) }
            }
            path.closeSubpath()
            cursor += count
        }
        return path
    }

    static func grayscaleBytes(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard let ctx = try? BrushRaster.context(width: width, height: height, mask: true) else { return nil }
        BrushRaster.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), mask: false, context: ctx)
        guard let ptr = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = ptr + y * ctx.bytesPerRow
            for x in 0..<width { bytes[y * width + x] = row[x] }
        }
        return bytes
    }
}

/// Interactive Quick Mask (`Q`) editing state: 255 = selected (clear), 0 = masked (50% ruby overlay).
final class QuickMaskState {
    let width: Int
    let height: Int
    var mask: [UInt8]
    private(set) var overlayImage: CGImage?
    private var lastPoint: CGPoint?

    init(width: Int, height: Int, selection: DocumentSelection?) {
        self.width = width
        self.height = height
        if let selection, !selection.isEmpty,
           let cov = try? selection.coverage(width: width, height: height),
           let bytes = MaskOutlineTracer.grayscaleBytes(of: cov, width: width, height: height) {
            mask = bytes
        } else {
            // No active selection -> start fully unselected (masked) so painting with white selects areas.
            mask = [UInt8](repeating: 0, count: width * height)
        }
        rebuildOverlay()
    }

    func beginStroke(at point: CGPoint, diameter: CGFloat, hardness: CGFloat, opacity: CGFloat, select: Bool) {
        lastPoint = point
        dab(at: point, diameter: diameter, hardness: hardness, opacity: opacity, select: select)
        rebuildOverlay()
    }

    func continueStroke(to point: CGPoint, diameter: CGFloat, hardness: CGFloat, opacity: CGFloat, select: Bool) {
        guard let from = lastPoint else {
            beginStroke(at: point, diameter: diameter, hardness: hardness, opacity: opacity, select: select)
            return
        }
        let dist = hypot(point.x - from.x, point.y - from.y)
        let step = max(1, diameter * 0.15)
        let count = max(1, Int((dist / step).rounded(.up)))
        for i in 1...count {
            let t = CGFloat(i) / CGFloat(count)
            let p = CGPoint(x: from.x + (point.x - from.x) * t, y: from.y + (point.y - from.y) * t)
            dab(at: p, diameter: diameter, hardness: hardness, opacity: opacity, select: select)
        }
        lastPoint = point
        rebuildOverlay()
    }

    func endStroke() { lastPoint = nil }

    private func dab(at center: CGPoint, diameter: CGFloat, hardness: CGFloat, opacity: CGFloat, select: Bool) {
        let r = max(1, diameter / 2)
        let ir = Int(ceil(r))
        let cx = Int(center.x.rounded()), cy = Int(center.y.rounded())
        let x0 = max(0, cx - ir), x1 = min(width - 1, cx + ir)
        let y0 = max(0, cy - ir), y1 = min(height - 1, cy + ir)
        guard x0 <= x1, y0 <= y1 else { return }
        let h = Float(min(0.99, max(0, hardness)))
        let op = Float(min(1, max(0.01, opacity)))
        let target: Float = select ? 255 : 0
        let invR = 1.0 / Float(r)

        for y in y0...y1 {
            let dy = Float(y) - Float(center.y)
            let row = y * width
            for x in x0...x1 {
                let dx = Float(x) - Float(center.x)
                let u = hypotf(dx, dy) * invR
                guard u < 1 else { continue }
                let w: Float
                if u <= h { w = 1 }
                else {
                    let t = (1 - u) / (1 - h)
                    w = t * t * (3 - 2 * t)
                }
                let alpha = w * op
                let idx = row + x
                let cur = Float(mask[idx])
                mask[idx] = UInt8(max(0, min(255, (cur + (target - cur) * alpha).rounded())))
            }
        }
    }

    /// Rebuilds the translucent ruby RGBA overlay image (unselected pixels tinted 50% red).
    func rebuildOverlay() {
        guard let ctx = try? BrushRaster.context(width: width, height: height, mask: false),
              let ptr = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return }
        let stride = ctx.bytesPerRow
        for y in 0..<height {
            let dst = ptr + y * stride
            let row = y * width
            for x in 0..<width {
                let masked = 255 - Int(mask[row + x]) // 255 = fully masked (ruby), 0 = selected (clear)
                let a = (masked * 128) / 255
                // Premultiplied ruby red (225, 35, 45).
                dst[x * 4] = UInt8((225 * a) / 255)
                dst[x * 4 + 1] = UInt8((35 * a) / 255)
                dst[x * 4 + 2] = UInt8((45 * a) / 255)
                dst[x * 4 + 3] = UInt8(a)
            }
        }
        overlayImage = ctx.makeImage()
    }

    func buildSelection() -> DocumentSelection? {
        let path = MaskOutlineTracer.trace(mask: mask, width: width, height: height, threshold: 128)
        let sel = DocumentSelection(path: path, antialiased: true, feather: 0)
        return sel.isEmpty ? nil : sel
    }
}

/// Preview view modes for the Select & Mask workspace.
nonisolated enum SelectAndMaskViewMode: String, CaseIterable, Sendable {
    case overlay = "Overlay"
    case onBlack = "On Black"
    case onWhite = "On White"
    case blackAndWhite = "Black & White"
}

/// Output destinations for the Select & Mask workspace.
nonisolated enum SelectAndMaskOutput: String, CaseIterable, Sendable {
    case selection = "Selection"
    case layerMask = "Layer Mask"
    case newLayerWithMask = "New Layer with Mask"
}

/// Parameters for Select & Mask edge refinement.
nonisolated struct SelectAndMaskSettings: Equatable, Sendable {
    var viewMode: SelectAndMaskViewMode = .overlay
    /// Edge smoothing radius in pixels (0…50).
    var smooth: Double = 0
    /// Edge feather radius in pixels (0…100).
    var feather: Double = 0
    /// Edge contrast boost percentage (0…100).
    var contrast: Double = 0
    /// Edge shift percentage (-100…100, negative contracts, positive expands).
    var shiftEdge: Double = 0
    /// Removes background color fringes along semi-transparent edge pixels.
    var decontaminateColors: Bool = false
    var decontaminateAmount: Double = 50
    var outputMode: SelectAndMaskOutput = .selection
}

/// Live editing state for the floating Select & Mask workspace.
struct SelectAndMaskSession {
    let documentID: UUID
    let layerID: UUID?
    let width: Int
    let height: Int
    let compositeImage: CGImage
    let baseMask: CGImage
    var settings = SelectAndMaskSettings()

    private static let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

    /// Applies Smooth, Shift Edge, Feather, and Contrast to `baseMask` and returns an 8-bit grayscale mask image.
    func refinedMask() -> CGImage? {
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        var ci = CIImage(cgImage: baseMask).clampedToExtent()

        // 1. Smooth (Gaussian blur + subtle re-sharpening to round jagged corners).
        if settings.smooth > 0.1 {
            let sigma = settings.smooth * 0.5
            ci = ci.applyingGaussianBlur(sigma: sigma).cropped(to: extent).clampedToExtent()
        }

        // 2. Shift Edge (-100…100% -> ±15 px morphological erode/dilate via CIMorphologyMinimum/Maximum).
        if abs(settings.shiftEdge) > 0.5 {
            let radius = abs(settings.shiftEdge) / 100.0 * 15.0
            let name = settings.shiftEdge > 0 ? "CIMorphologyMaximum" : "CIMorphologyMinimum"
            if let f = CIFilter(name: name) {
                f.setValue(ci, forKey: kCIInputImageKey)
                f.setValue(radius, forKey: kCIInputRadiusKey)
                if let out = f.outputImage { ci = out.cropped(to: extent).clampedToExtent() }
            }
        }

        // 3. Feather (Gaussian blur).
        if settings.feather > 0.1 {
            ci = ci.applyingGaussianBlur(sigma: settings.feather * 0.5).cropped(to: extent).clampedToExtent()
        }

        // 4. Contrast (steepen transition around 0.5 via CIColorControls).
        if settings.contrast > 0.5 {
            let c = 1.0 + (settings.contrast / 100.0) * 6.0
            if let f = CIFilter(name: "CIColorControls") {
                f.setValue(ci, forKey: kCIInputImageKey)
                f.setValue(c, forKey: kCIInputContrastKey)
                if let out = f.outputImage { ci = out.cropped(to: extent) }
            }
        }

        ci = ci.cropped(to: extent)
        guard let cg = Self.ciContext.createCGImage(ci, from: extent) else { return nil }
        // Convert cleanly into 8-bit grayscale top-left mask (preserving upright orientation).
        guard let ctx = try? BrushRaster.context(width: width, height: height, mask: true) else { return nil }
        BrushRaster.draw(cg, in: extent, mask: false, context: ctx)
        return ctx.makeImage()
    }

    /// Decontaminates edge color fringes by pulling opaque interior RGB colors outward into semi-transparent rim pixels.
    func decontaminatedImage(from source: CGImage, mask: CGImage) -> CGImage? {
        guard settings.decontaminateColors, settings.decontaminateAmount > 0 else { return source }
        let w = width, h = height
        guard let srcCtx = try? BrushRaster.context(width: w, height: h, mask: false),
              let mBytes = MaskOutlineTracer.grayscaleBytes(of: mask, width: w, height: h) else { return source }
        BrushRaster.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h), mask: false, context: srcCtx)
        guard let ptr = srcCtx.data?.assumingMemoryBound(to: UInt8.self) else { return source }
        let stride = srcCtx.bytesPerRow
        let orig = Array(UnsafeBufferPointer(start: ptr, count: h * stride))
        let strength = Float(min(1, max(0, settings.decontaminateAmount / 100.0)))
        let radius = 3

        for y in 0..<h {
            for x in 0..<w {
                let m = mBytes[y * w + x]
                // Only process semi-transparent edge band (8…245).
                guard m >= 8 && m <= 245 else { continue }
                var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0, sumW: Float = 0
                for dy in -radius...radius {
                    let ny = y + dy
                    guard ny >= 0 && ny < h else { continue }
                    for dx in -radius...radius {
                        let nx = x + dx
                        guard nx >= 0 && nx < w else { continue }
                        let nm = mBytes[ny * w + nx]
                        guard nm > 235 else { continue }
                        let p = ny * stride + nx * 4
                        let a = Float(orig[p + 3])
                        guard a > 200 else { continue }
                        let invA = 255.0 / a
                        sumR += Float(orig[p]) * invA
                        sumG += Float(orig[p + 1]) * invA
                        sumB += Float(orig[p + 2]) * invA
                        sumW += 1
                    }
                }
                guard sumW > 0 else { continue }
                let p = y * stride + x * 4
                let a = Float(orig[p + 3])
                guard a > 0 else { continue }
                let aNorm = a / 255.0
                let cleanR = (sumR / sumW) * aNorm
                let cleanG = (sumG / sumW) * aNorm
                let cleanB = (sumB / sumW) * aNorm
                ptr[p] = UInt8(max(0, min(255, (Float(orig[p]) * (1 - strength) + cleanR * strength).rounded())))
                ptr[p + 1] = UInt8(max(0, min(255, (Float(orig[p + 1]) * (1 - strength) + cleanG * strength).rounded())))
                ptr[p + 2] = UInt8(max(0, min(255, (Float(orig[p + 2]) * (1 - strength) + cleanB * strength).rounded())))
            }
        }
        return srcCtx.makeImage()
    }

    /// Generates a preview image for the Select & Mask panel in the chosen `viewMode`.
    func previewImage() -> CGImage? {
        guard let mask = refinedMask() else { return compositeImage }
        if settings.viewMode == .blackAndWhite { return mask }
        let src = settings.decontaminateColors ? (decontaminatedImage(from: compositeImage, mask: mask) ?? compositeImage) : compositeImage
        let w = width, h = height
        guard let outCtx = try? BrushRaster.context(width: w, height: h, mask: false),
              let srcCtx = try? BrushRaster.context(width: w, height: h, mask: false),
              let mBytes = MaskOutlineTracer.grayscaleBytes(of: mask, width: w, height: h) else { return src }
        BrushRaster.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h), mask: false, context: srcCtx)
        guard let sp = srcCtx.data?.assumingMemoryBound(to: UInt8.self),
              let dp = outCtx.data?.assumingMemoryBound(to: UInt8.self) else { return src }
        let sStride = srcCtx.bytesPerRow, dStride = outCtx.bytesPerRow

        for y in 0..<h {
            let sr = sp + y * sStride
            let dr = dp + y * dStride
            let mr = y * w
            for x in 0..<w {
                let m = Float(mBytes[mr + x]) / 255.0
                let r = Float(sr[x * 4]), g = Float(sr[x * 4 + 1]), b = Float(sr[x * 4 + 2]), a = Float(sr[x * 4 + 3])
                switch settings.viewMode {
                case .overlay:
                    let tint = (1 - m) * 0.5
                    dr[x * 4] = UInt8(min(255, r * (1 - tint) + 225 * tint))
                    dr[x * 4 + 1] = UInt8(min(255, g * (1 - tint) + 35 * tint))
                    dr[x * 4 + 2] = UInt8(min(255, b * (1 - tint) + 45 * tint))
                    dr[x * 4 + 3] = UInt8(max(a, tint * 255))
                case .onBlack:
                    dr[x * 4] = UInt8(r * m)
                    dr[x * 4 + 1] = UInt8(g * m)
                    dr[x * 4 + 2] = UInt8(b * m)
                    dr[x * 4 + 3] = 255
                case .onWhite:
                    let inv = (1 - m) * 255
                    dr[x * 4] = UInt8(min(255, r * m + inv))
                    dr[x * 4 + 1] = UInt8(min(255, g * m + inv))
                    dr[x * 4 + 2] = UInt8(min(255, b * m + inv))
                    dr[x * 4 + 3] = 255
                case .blackAndWhite:
                    break
                }
            }
        }
        return outCtx.makeImage()
    }
}

extension EditorSession {
    // MARK: - Quick Mask Mode (Q)

    var isInQuickMaskMode: Bool { quickMask != nil }

    func toggleQuickMask() {
        guard let document, canEditSelection else { return }
        if let qm = quickMask {
            quickMask = nil
            let nextSel = qm.buildSelection()
            setSelection(nextSel, name: "Quick Mask")
        } else {
            quickMask = QuickMaskState(width: document.width, height: document.height, selection: document.selection)
            if tool != .brush { selectTool(.brush) }
        }
    }

    func quickMaskBrushDown(at point: CGPoint) {
        guard let qm = quickMask else { return }
        let select = brushMode == .paint && foregroundColor.luminance >= 0.5
        qm.beginStroke(at: point, diameter: brushSettings.diameter, hardness: brushSettings.hardness,
                       opacity: brushSettings.opacity, select: select)
        quickMaskRevision += 1
    }

    func quickMaskBrushDragged(to point: CGPoint) {
        guard let qm = quickMask else { return }
        let select = brushMode == .paint && foregroundColor.luminance >= 0.5
        qm.continueStroke(to: point, diameter: brushSettings.diameter, hardness: brushSettings.hardness,
                          opacity: brushSettings.opacity, select: select)
        quickMaskRevision += 1
    }

    func quickMaskBrushUp() {
        quickMask?.endStroke()
        quickMaskRevision += 1
    }

    // MARK: - Border, Smooth, Select Similar

    /// Creates a ring selection `width` pixels wide straddling the current selection boundary.
    func borderSelection(by width: Int) {
        guard let document, let current = selection, canModifySelection, width > 0, width <= 200 else { return }
        let canvas = CGPath(rect: CGRect(origin: .zero, size: document.size), transform: nil)
        let ring = current.path.copy(strokingWithWidth: CGFloat(width), lineCap: .round, lineJoin: .round, miterLimit: 4)
            .intersection(canvas, using: .winding)
        setSelection(DocumentSelection(path: ring.withoutSlivers, antialiased: current.antialiased, feather: current.feather),
                     name: "Border Selection")
    }

    /// Rounds and smooths jagged corners of the current selection by blurring and re-thresholding its coverage mask.
    func smoothSelection(by radius: Int) {
        guard let document, let current = selection, canModifySelection, radius > 0, radius <= 100 else { return }
        let w = document.width, h = document.height
        guard let cov = try? current.coverage(width: w, height: h) else { return }
        let extent = CGRect(x: 0, y: 0, width: w, height: h)
        let blurred = CIImage(cgImage: cov).clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius) * 0.65)
            .cropped(to: extent)
        guard let smoothedImg = try? PixelAdjust.render(blurred, width: w, height: h, isMask: true),
              let bytes = MaskOutlineTracer.grayscaleBytes(of: smoothedImg, width: w, height: h) else { return }
        let traced = MaskOutlineTracer.trace(mask: bytes, width: w, height: h, threshold: 128)
        setSelection(DocumentSelection(path: traced.withoutSlivers, antialiased: current.antialiased, feather: current.feather),
                     name: "Smooth Selection")
    }

    /// Selects all pixels across the document matching the sampled colors inside the current selection within `tolerance`.
    func selectSimilar(tolerance: Int = 32) async {
        guard let document, let current = selection, canModifySelection,
              let snapshot = projectSnapshot() else { return }
        let w = document.width, h = document.height
        guard let rendered = try? await ImageExporter.shared.render(snapshot),
              let cov = try? current.coverage(width: w, height: h),
              let covBytes = MaskOutlineTracer.grayscaleBytes(of: cov, width: w, height: h),
              let rgbaCtx = try? BrushRaster.context(width: w, height: h, mask: false) else { return }
        BrushRaster.draw(rendered.image, in: CGRect(x: 0, y: 0, width: w, height: h), mask: false, context: rgbaCtx)
        guard let ptr = rgbaCtx.data?.assumingMemoryBound(to: UInt8.self) else { return }
        let stride = rgbaCtx.bytesPerRow

        // Sample up to 16 distinct representative RGB colors from selected opaque pixels.
        var samples: [UInt8] = []
        let stepY = max(1, h / 32), stepX = max(1, w / 32)
        for y in Swift.stride(from: 0, to: h, by: stepY) {
            for x in Swift.stride(from: 0, to: w, by: stepX) {
                guard covBytes[y * w + x] >= 128 else { continue }
                let p = y * stride + x * 4
                let a = ptr[p + 3]
                guard a > 16 else { continue }
                let r = UInt8(min(255, Int(ptr[p]) * 255 / Int(a)))
                let g = UInt8(min(255, Int(ptr[p + 1]) * 255 / Int(a)))
                let b = UInt8(min(255, Int(ptr[p + 2]) * 255 / Int(a)))
                var dup = false
                for i in Swift.stride(from: 0, to: samples.count, by: 3) {
                    if abs(Int(samples[i]) - Int(r)) <= 8 && abs(Int(samples[i + 1]) - Int(g)) <= 8 && abs(Int(samples[i + 2]) - Int(b)) <= 8 {
                        dup = true; break
                    }
                }
                if !dup {
                    samples.append(contentsOf: [r, g, b])
                    if samples.count >= 48 { break }
                }
            }
            if samples.count >= 48 { break }
        }
        guard !samples.isEmpty else { return }

        var outMask = [UInt8](repeating: 0, count: w * h)
        let count = samples.withUnsafeBufferPointer { sBuf in
            outMask.withUnsafeMutableBufferPointer { mBuf in
                color_range_mask(ptr, w, h, stride, sBuf.baseAddress, Int32(samples.count / 3),
                                 nil, 0, Int32(max(0, min(255, tolerance))), 0, mBuf.baseAddress)
            }
        }
        guard count > 0 else { return }
        let path = MaskOutlineTracer.trace(mask: outMask, width: w, height: h, threshold: 128)
        setSelection(DocumentSelection(path: path.withoutSlivers, antialiased: current.antialiased, feather: current.feather),
                     name: "Select Similar")
    }

    // MARK: - Select & Mask Workspace

    var canOpenSelectAndMask: Bool {
        document != nil && canEditSelection && (selection?.isEmpty == false || activeLayer?.mask != nil)
    }

    func openSelectAndMask() async {
        guard let document, canOpenSelectAndMask, let snapshot = projectSnapshot() else { return }
        let w = document.width, h = document.height
        guard let rendered = try? await ImageExporter.shared.render(snapshot) else { return }
        let baseMask: CGImage?
        if let sel = document.selection, !sel.isEmpty {
            baseMask = try? sel.coverage(width: w, height: h)
        } else if let layer = activeLayer, let mask = layer.mask {
            let ctx = try? BrushRaster.context(width: w, height: h, mask: true)
            if let ctx {
                LayerRenderer.draw(mask.asset.image, transform: layer.maskTransform, center: layer.maskTransform.center, in: ctx)
                baseMask = ctx.makeImage()
            } else { baseMask = nil }
        } else {
            baseMask = nil
        }
        guard let baseMask else { return }
        selectAndMask = SelectAndMaskSession(documentID: document.id, layerID: activeLayerID,
                                             width: w, height: h, compositeImage: rendered.image, baseMask: baseMask)
    }

    func cancelSelectAndMask() {
        selectAndMask = nil
    }

    func applySelectAndMask() {
        guard let session = selectAndMask, let document, document.id == session.documentID,
              let refined = session.refinedMask() else {
            selectAndMask = nil
            return
        }
        let settings = session.settings
        selectAndMask = nil

        switch settings.outputMode {
        case .selection:
            if let bytes = MaskOutlineTracer.grayscaleBytes(of: refined, width: session.width, height: session.height) {
                let path = MaskOutlineTracer.trace(mask: bytes, width: session.width, height: session.height, threshold: 128)
                setSelection(DocumentSelection(path: path.withoutSlivers, antialiased: true, feather: CGFloat(settings.feather)),
                             name: "Select and Mask")
            }
        case .layerMask:
            guard let id = session.layerID ?? activeLayerID,
                  let index = document.layers.firstIndex(where: { $0.id == id }),
                  let thumb = try? PixelInvert.thumbnail(of: refined) else { return }
            finishOpacityEdit()
            beginEdit("Select and Mask")
            let maskAsset = ImportedImage(image: refined, thumbnail: thumb, name: L10n.text("Mask"))
            self.document?.layers[index].mask = LayerMask(asset: maskAsset, isEnabled: true,
                                                           placement: LayerTransform(origin: .zero, size: document.size),
                                                           isLinked: true)
            self.document?.selection = nil
            endEdit()
        case .newLayerWithMask:
            let baseImg = settings.decontaminateColors
                ? (session.decontaminatedImage(from: session.compositeImage, mask: refined) ?? session.compositeImage)
                : session.compositeImage
            guard let thumb = try? PixelInvert.thumbnail(of: baseImg),
                  let mThumb = try? PixelInvert.thumbnail(of: refined) else { return }
            finishOpacityEdit()
            beginEdit("Select and Mask")
            let newLayer = ImageLayer(
                id: UUID(),
                asset: ImportedImage(image: baseImg, thumbnail: thumb, name: L10n.text("Refined")),
                name: L10n.text("Refined Selection"),
                isVisible: true,
                transform: LayerTransform(origin: .zero, size: document.size),
                mask: LayerMask(asset: ImportedImage(image: refined, thumbnail: mThumb, name: L10n.text("Mask")),
                                isEnabled: true, placement: LayerTransform(origin: .zero, size: document.size), isLinked: true)
            )
            self.document?.layers.append(newLayer)
            activeLayerID = newLayer.id
            selectedLayerIDs = [newLayer.id]
            self.document?.selection = nil
            endEdit()
        }
    }
}

private extension PaletteColor {
    var luminance: Double { 0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue) }
}
