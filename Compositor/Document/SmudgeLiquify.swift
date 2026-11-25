import AppKit

/// The Blur tool's modes. Smudge and Liquify push the active layer's pixels around under the brush.
/// The Brush tool's modes.
nonisolated enum BrushToolMode: String, CaseIterable, Sendable {
    case paint = "Paint"
    case erase = "Erase"
}

nonisolated enum BlurToolMode: String, CaseIterable, Sendable {
    case liquify = "Liquify"
    case blur = "Blur"
    case smudge = "Smudge"
    case sharpen = "Sharpen"
}

/// Photoshop-style Liquify sub-brushes.
nonisolated enum LiquifyBrushMode: String, CaseIterable, Sendable {
    case forwardWarp = "Forward Warp"
    case bloat = "Bloat"
    case pucker = "Pucker"
    case twirlCW = "Twirl CW"
    case twirlCCW = "Twirl CCW"
    case pushLeft = "Push Left"
    case reconstruct = "Reconstruct"
    case freeze = "Freeze Mask"
    case thaw = "Thaw Mask"

    var isMaskTool: Bool { self == .freeze || self == .thaw }
    var appliesOnClick: Bool { self != .forwardWarp && self != .pushLeft }
}

/// Spot Healing (automatic) vs manual-sample Healing Brush (Option-click source).
nonisolated enum HealingToolMode: String, CaseIterable, Sendable {
    case spot = "Spot Healing"
    case manual = "Healing Brush"
}

/// A Smudge or Liquify stroke in progress. It works on the active layer as the canvas shows it, at document size,
/// changing it dab by dab; the canvas shows that working copy in place of the layer. When the stroke ends, the result
/// is painted into the layer's own pixels along the stroke's path (see `EditorSession.finishWarp`).
final class WarpStroke {
    let layer: ImageLayer
    let mode: BlurToolMode
    let liquifyMode: LiquifyBrushMode
    let diameter: CGFloat
    let hardness: CGFloat
    let strength: CGFloat
    let width: Int
    let height: Int
    private(set) var context: CGContext
    private let pixels: UnsafeMutablePointer<UInt8>
    /// Every dab's center, for painting the result into the layer.
    private(set) var points: [CGPoint] = []
    /// The working copy on the GPU, where the dabs run when there is one (see MetalWarp).
    let gpu: MetalWarp?
    private var cpuImage: CGImage?
    /// The working copy as an image, fetched from the GPU the first time it's asked for after a dab.
    var image: CGImage? {
        guard let gpu else { return cpuImage }
        if cpuImage == nil {
            gpu.read(into: context)
            cpuImage = context.makeImage()
        }
        return cpuImage
    }
    private var last: CGPoint?
    /// Smudge: the color the brush carries, a (2r+1)² RGBA square.
    private var carried: [Float] = []
    private var scratch: [Float] = []
    /// Multi-brush Liquify state: untouched source pixels, per-pixel displacement offsets, and optional freeze mask (0…255).
    private var originalPixels: [UInt8] = []
    private var offsets: [SIMD2<Float>] = []
    private(set) var freezeMask: [UInt8] = []
    private var usesAdvancedLiquify: Bool {
        mode == .liquify && (liquifyMode != .forwardWarp || !freezeMask.isEmpty)
    }

    /// `deep`: a 16-bit layer's 16-bit pixels (`DeepLayer`). With the GPU the working copy is then 16-bit too, so the
    /// stroke keeps the layer's precision; the CPU dabs work at 8 bits.
    init(layer: ImageLayer, image: CGImage, deep: CGImage? = nil, transform: LayerTransform, canvas: CGSize, mode: BlurToolMode,
         liquifyMode: LiquifyBrushMode = .forwardWarp, freezeMask: [UInt8]? = nil,
         settings: BrushSettings, useGPU: Bool = true) throws {
        self.layer = layer
        self.mode = mode
        self.liquifyMode = liquifyMode
        diameter = max(2, settings.diameter)
        hardness = min(0.98, max(0, settings.hardness))
        strength = min(1, max(0.01, settings.opacity))
        width = Int(canvas.width); height = Int(canvas.height)
        if let mask = freezeMask, mask.count == width * height {
            self.freezeMask = mask
        } else if mode == .liquify && liquifyMode.isMaskTool {
            self.freezeMask = [UInt8](repeating: 0, count: width * height)
        }
        let advanced = mode == .liquify && (liquifyMode != .forwardWarp || !self.freezeMask.isEmpty)
        let allowGPU = useGPU && !advanced
        var gpu: MetalWarp?
        if allowGPU, let deep, MetalWarp.pipelines != nil {
            let wide = try DeepLayer.context(width: width, height: height, hdr: DeepLayer.isHDR(deep))
            LayerRenderer.draw(deep, transform: transform, center: transform.center, in: wide)
            gpu = MetalWarp(pixels: wide)
            context = wide
        } else {
            context = try BrushRaster.context(width: width, height: height, mask: false)
            LayerRenderer.draw(image, transform: transform, center: transform.center, in: context)
            if allowGPU { gpu = MetalWarp(pixels: context) }
        }
        if gpu == nil, context.bitsPerComponent != 8 {
            context = try BrushRaster.context(width: width, height: height, mask: false)
            LayerRenderer.draw(image, transform: transform, center: transform.center, in: context)
        }
        self.gpu = gpu
        guard let data = context.data else { throw ExportError.render }
        // Top-left rows: a document point's row is its y. Only the CPU dabs use these, on an 8-bit copy.
        pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        if advanced {
            originalPixels = Array(UnsafeBufferPointer(start: pixels, count: width * height * 4))
            offsets = [SIMD2<Float>](repeating: .zero, count: width * height)
        }
        cpuImage = context.makeImage()
    }

    private var radius: Int { Int((diameter / 2).rounded(.up)) }
    /// How much a dab moves pixels at a distance `u` (0 center, 1 rim) from its center.
    private func weight(_ u: Float) -> Float {
        guard u < 1 else { return 0 }
        let h = Float(hardness)
        guard u > h else { return 1 }
        let t = (1 - u) / (1 - h)
        return t * t * (3 - 2 * t)
    }

    /// Continues the stroke to `point`, dabbing along the way, then refreshes `image`.
    func append(_ point: CGPoint) {
        guard let from = last else {
            last = point
            if mode == .smudge {
                if let gpu { gpu.pickUp(at: point, radius: radius); gpu.commit() } else { pickUp(at: point) }
            } else if usesAdvancedLiquify, liquifyMode.appliesOnClick {
                applyAdvancedLiquify(from: point, to: point)
                points.append(point)
                cpuImage = context.makeImage()
            }
            return
        }
        let distance = hypot(point.x - from.x, point.y - from.y)
        let spacing = max(1, diameter * (mode == .smudge ? 0.005 : 0.025))
        guard distance >= spacing else { return }
        let steps = Int((distance / spacing).rounded(.up))
        var previous = from
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let next = CGPoint(x: from.x + (point.x - from.x) * t, y: from.y + (point.y - from.y) * t)
            if let gpu {
                if mode == .smudge { gpu.smudge(at: next, radius: radius, diameter: diameter, hardness: hardness, strength: strength) }
                else { gpu.push(from: previous, to: next, radius: radius, diameter: diameter, hardness: hardness, strength: strength) }
            } else if mode == .smudge {
                smudge(at: next)
            } else if usesAdvancedLiquify {
                applyAdvancedLiquify(from: previous, to: next)
            } else {
                push(from: previous, to: next)
            }
            points.append(next)
            previous = next
        }
        last = point
        if let gpu {
            gpu.commit()
            cpuImage = nil
        } else {
            cpuImage = context.makeImage()
        }
    }

    private func sampleOriginal(x sx: Float, y sy: Float, into dst: UnsafeMutablePointer<UInt8>) {
        let cx = min(Float(width - 1), max(0, sx))
        let cy = min(Float(height - 1), max(0, sy))
        let x0 = Int(cx), y0 = Int(cy)
        let x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
        let fx = cx - Float(x0), fy = cy - Float(y0)
        let p00 = (y0 * width + x0) * 4, p10 = (y0 * width + x1) * 4
        let p01 = (y1 * width + x0) * 4, p11 = (y1 * width + x1) * 4
        for k in 0..<4 {
            let top = Float(originalPixels[p00 + k]) + (Float(originalPixels[p10 + k]) - Float(originalPixels[p00 + k])) * fx
            let bot = Float(originalPixels[p01 + k]) + (Float(originalPixels[p11 + k]) - Float(originalPixels[p01 + k])) * fx
            dst[k] = UInt8(max(0, min(255, (top + (bot - top) * fy).rounded())))
        }
    }

    private func applyAdvancedLiquify(from a: CGPoint, to b: CGPoint) {
        let r = radius
        let cx = Int(b.x.rounded()), cy = Int(b.y.rounded())
        let invR = 1 / Float(diameter / 2)
        let s = Float(strength)
        let x0 = max(0, cx - r), x1 = min(width - 1, cx + r)
        let y0 = max(0, cy - r), y1 = min(height - 1, cy + r)
        guard x0 <= x1, y0 <= y1 else { return }

        if liquifyMode.isMaskTool {
            if freezeMask.count != width * height { freezeMask = [UInt8](repeating: 0, count: width * height) }
            let freezing = liquifyMode == .freeze
            for y in y0...y1 {
                for x in x0...x1 {
                    let dx = Float(x) - Float(b.x), dy = Float(y) - Float(b.y)
                    let w = weight(hypotf(dx, dy) * invR)
                    guard w > 0 else { continue }
                    let idx = y * width + x
                    let current = Float(freezeMask[idx]) / 255.0
                    let next = freezing ? min(1, current + w * s) : max(0, current - w * s)
                    freezeMask[idx] = UInt8((next * 255).rounded())
                    // Tint frozen mask area softly in ruby on the preview buffer so the user sees it live.
                    let p = idx * 4
                    let origR = Float(originalPixels[p]), origG = Float(originalPixels[p + 1]), origB = Float(originalPixels[p + 2]), origA = Float(originalPixels[p + 3])
                    let overlay = next * 0.45
                    pixels[p] = UInt8(min(255, origR * (1 - overlay) + 230 * overlay))
                    pixels[p + 1] = UInt8(min(255, origG * (1 - overlay) + 40 * overlay))
                    pixels[p + 2] = UInt8(min(255, origB * (1 - overlay) + 50 * overlay))
                    pixels[p + 3] = UInt8(max(origA, overlay * 255))
                }
            }
            return
        }

        let move = SIMD2<Float>(Float(b.x - a.x), Float(b.y - a.y))
        let leftPerp = SIMD2<Float>(move.y, -move.x) // 90° counterclockwise (left of stroke travel in screen y-down coords)
        let hasFreeze = freezeMask.count == width * height

        // Snapshot offsets in the dab area so updates don't feed back within the same dab.
        let cw = x1 - x0 + 1, ch = y1 - y0 + 1
        var oldOffsets = [SIMD2<Float>](repeating: .zero, count: cw * ch)
        for y in 0..<ch {
            for x in 0..<cw {
                oldOffsets[y * cw + x] = offsets[(y + y0) * width + (x + x0)]
            }
        }
        let sampleOffset: (Float, Float) -> SIMD2<Float> = { sx, sy in
            let cx = min(Float(self.width - 1), max(0, sx))
            let cy = min(Float(self.height - 1), max(0, sy))
            let ix0 = Int(cx), iy0 = Int(cy)
            let ix1 = min(self.width - 1, ix0 + 1), iy1 = min(self.height - 1, iy0 + 1)
            let fx = cx - Float(ix0), fy = cy - Float(iy0)
            let read: (Int, Int) -> SIMD2<Float> = { rx, ry in
                if rx >= x0 && rx <= x1 && ry >= y0 && ry <= y1 {
                    return oldOffsets[(ry - y0) * cw + (rx - x0)]
                }
                return self.offsets[ry * self.width + rx]
            }
            let v00 = read(ix0, iy0), v10 = read(ix1, iy0)
            let v01 = read(ix0, iy1), v11 = read(ix1, iy1)
            let top = v00 + (v10 - v00) * fx
            let bot = v01 + (v11 - v01) * fx
            return top + (bot - top) * fy
        }

        for y in y0...y1 {
            for x in x0...x1 {
                let dx = Float(x) - Float(b.x), dy = Float(y) - Float(b.y)
                let dist = hypotf(dx, dy)
                let w0 = weight(dist * invR)
                guard w0 > 0 else { continue }
                let idx = y * width + x
                let unfreeze: Float = hasFreeze ? (1 - Float(freezeMask[idx]) / 255.0) : 1
                let w = w0 * unfreeze
                guard w > 0.0001 else { continue }

                let cur = oldOffsets[(y - y0) * cw + (x - x0)]
                var step = SIMD2<Float>.zero
                switch liquifyMode {
                case .forwardWarp:
                    step = -move * (w * s)
                case .pushLeft:
                    step = -leftPerp * (w * s)
                case .bloat:
                    // Outward expansion: pull source coordinate smoothly toward brush center without overshooting.
                    step = SIMD2<Float>(-dx, -dy) * (w * s * 0.18)
                case .pucker:
                    // Inward contraction: push source coordinate smoothly away from brush center.
                    step = SIMD2<Float>(dx, dy) * (w * s * 0.18)
                case .twirlCW, .twirlCCW:
                    let angle = (liquifyMode == .twirlCW ? -1.0 as Float : 1.0 as Float) * w * s * 0.30
                    let ca = cosf(angle), sa = sinf(angle)
                    let rx = dx * ca - dy * sa
                    let ry = dx * sa + dy * ca
                    step = SIMD2<Float>(rx - dx, ry - dy)
                case .reconstruct:
                    let next = cur * max(0, 1 - w * s * 0.6)
                    offsets[idx] = next
                    sampleOriginal(x: Float(x) + next.x, y: Float(y) + next.y, into: pixels + idx * 4)
                    continue
                case .freeze, .thaw:
                    continue
                }

                // Prevent unfrozen pixels from dragging frozen source pixels out of a frozen region.
                if hasFreeze {
                    let sx = max(0, min(width - 1, Int((Float(x) + step.x).rounded())))
                    let sy = max(0, min(height - 1, Int((Float(y) + step.y).rounded())))
                    let srcUnfreeze = 1 - Float(freezeMask[sy * width + sx]) / 255.0
                    step *= srcUnfreeze
                }

                // Compose the incremental warp step with the existing displacement field.
                let prev = sampleOffset(Float(x) + step.x, Float(y) + step.y)
                let nextOffset = step + prev
                offsets[idx] = nextOffset
                sampleOriginal(x: Float(x) + nextOffset.x, y: Float(y) + nextOffset.y, into: pixels + idx * 4)
            }
        }
    }

    private func pickUp(at center: CGPoint) {
        let r = radius, side = 2 * r + 1
        carried = [Float](repeating: 0, count: side * side * 4)
        let cx = Int(center.x.rounded()), cy = Int(center.y.rounded())
        for dy in -r...r {
            let y = cy + dy
            guard y >= 0, y < height else { continue }
            for dx in -r...r {
                let x = cx + dx
                guard x >= 0, x < width else { continue }
                let p = (y * width + x) * 4, c = ((dy + r) * side + dx + r) * 4
                for k in 0..<4 { carried[c + k] = Float(pixels[p + k]) }
            }
        }
    }

    private func smudge(at center: CGPoint) {
        let r = radius, side = 2 * r + 1
        let cx = Int(center.x.rounded()), cy = Int(center.y.rounded())
        let keep = Float(strength), invR = 1 / Float(diameter / 2)
        for dy in -r...r {
            let y = cy + dy
            guard y >= 0, y < height else { continue }
            for dx in -r...r {
                let x = cx + dx
                guard x >= 0, x < width else { continue }
                let w = weight(Float(dx * dx + dy * dy).squareRoot() * invR)
                guard w > 0 else { continue }
                let p = (y * width + x) * 4, c = ((dy + r) * side + dx + r) * 4
                for k in 0..<4 {
                    let under = Float(pixels[p + k])
                    // What was under the brush at the last dab, laid down here at the smudge's strength, as Photoshop
                    // does: all of it drags the pixels along; less mixes them with what's here, softening the trail.
                    let painted = under + (carried[c + k] - under) * w * keep
                    pixels[p + k] = UInt8(max(0, min(255, painted.rounded())))
                    // The brush then carries what it just left, and nothing older: holding on to what it picked up
                    // at the start stamped it again at every dab, a trail of ghost copies.
                    carried[c + k] = painted
                }
            }
        }
    }

    /// Forward warp: pixels under the brush move with it, most at its center, fading to none at its rim.
    private func push(from a: CGPoint, to b: CGPoint) {
        let r = radius
        let move = SIMD2<Float>(Float(b.x - a.x), Float(b.y - a.y)) * Float(strength)
        let margin = Int(ceil(max(abs(move.x), abs(move.y)))) + 2
        let cx = Int(b.x.rounded()), cy = Int(b.y.rounded())
        // A copy of the area as it was before this dab, which the dab samples from.
        let x0 = max(0, cx - r - margin), x1 = min(width - 1, cx + r + margin)
        let y0 = max(0, cy - r - margin), y1 = min(height - 1, cy + r + margin)
        guard x0 <= x1, y0 <= y1 else { return }
        let cw = x1 - x0 + 1, ch = y1 - y0 + 1
        if scratch.count < cw * ch * 4 { scratch = [Float](repeating: 0, count: cw * ch * 4) }
        for y in 0..<ch {
            for x in 0..<cw {
                let p = ((y + y0) * width + x + x0) * 4, s = (y * cw + x) * 4
                for k in 0..<4 { scratch[s + k] = Float(pixels[p + k]) }
            }
        }
        let invR = 1 / Float(diameter / 2)
        for dy in -r...r {
            let y = cy + dy
            guard y >= y0, y <= y1 else { continue }
            for dx in -r...r {
                let x = cx + dx
                guard x >= x0, x <= x1 else { continue }
                let w = weight(Float(dx * dx + dy * dy).squareRoot() * invR)
                guard w > 0 else { continue }
                // Bilinear sample of the old pixels, from behind the brush's travel.
                let sx = min(Float(cw - 1), max(0, Float(x - x0) - move.x * w))
                let sy = min(Float(ch - 1), max(0, Float(y - y0) - move.y * w))
                let ix = min(cw - 2, Int(sx)), iy = min(ch - 2, Int(sy))
                guard ix >= 0, iy >= 0 else { continue }
                let fx = sx - Float(ix), fy = sy - Float(iy)
                let p = (y * width + x) * 4
                let s00 = (iy * cw + ix) * 4, s10 = s00 + 4, s01 = s00 + cw * 4, s11 = s01 + 4
                for k in 0..<4 {
                    let top = scratch[s00 + k] + (scratch[s10 + k] - scratch[s00 + k]) * fx
                    let bottom = scratch[s01 + k] + (scratch[s11 + k] - scratch[s01 + k]) * fx
                    pixels[p + k] = UInt8(max(0, min(255, (top + (bottom - top) * fy).rounded())))
                }
            }
        }
    }
}

extension EditorSession {
    func beginWarp(at point: CGPoint) {
        guard canPaint, !isMaskSelected, let active = activeLayer, let document else {
            brushError = isMaskSelected ? L10n.text("Smudge and Liquify work on a layer's pixels, not its mask.") : paintRefusal
            return
        }
        pauseGIFForEditing(for: active.id)
        let layer = pixelEditingLayer(for: active)
        guard let image = layer.asset?.image else { return }
        finishOpacityEdit()
        do {
            let mask: [UInt8]? = (blurMode == .liquify && liquifyFreezeMaskSize.map { $0.0 == document.width && $0.1 == document.height } == true)
                ? liquifyFreezeMask : nil
            let stroke = try WarpStroke(layer: layer, image: image, deep: try layer.asset.flatMap { try DeepLayer.flattened($0) },
                                        transform: displayedTransform(for: layer),
                                        canvas: document.size, mode: blurMode,
                                        liquifyMode: liquifyMode, freezeMask: mask,
                                        settings: brushSettings)
            stroke.append(point)
            warpStroke = stroke
            lastBrushPoint = (point, layer.id, false)
            brushRevision += 1
        } catch { brushError = error.localizedDescription }
    }

    func clearLiquifyFreezeMask() {
        liquifyFreezeMask = nil
        liquifyFreezeMaskSize = nil
        brushRevision += 1
    }

    /// Paints the finished Smudge or Liquify result into the layer's pixels along the stroke, as one undo step.
    func finishWarp() {
        guard let warp = warpStroke else { return }
        warpStroke = nil
        brushRevision += 1
        if warp.mode == .liquify, warp.liquifyMode.isMaskTool {
            if warp.freezeMask.contains(where: { $0 > 0 }) {
                liquifyFreezeMask = warp.freezeMask
                liquifyFreezeMaskSize = (warp.width, warp.height)
            } else {
                liquifyFreezeMask = nil
                liquifyFreezeMaskSize = nil
            }
            return
        }
        guard !warp.points.isEmpty, let result = warp.image,
              let current = document?.layers.first(where: { $0.id == warp.layer.id }),
              pixelEditTargetMatches(current, original: warp.layer) else { return }
        do {
            var settings = brushSettings
            // A hard tip a little wider than the brush covers everything the stroke moved.
            settings.diameter = warp.diameter + 4
            settings.hardness = 1
            settings.opacity = 1
            settings.flow = 1
            settings.airbrush = false
            settings.blendMode = .normal
            settings.roundness = 1
            settings.angle = 0
            settings.spacing = 0
            settings.scatter = 0
            let stroke = try makeRasterEdit(for: current, settings: settings)
            stroke.clone = (result, CGRect(x: 0, y: 0, width: result.width, height: result.height), false)
            // A 16-bit working copy goes into the layer's 16-bit pixels.
            if result.bitsPerComponent == 16 { stroke.deepClone = stroke.clone }
            stroke.replacesWithClone = true
            stroke.editName = warp.mode == .liquify && warp.liquifyMode != .forwardWarp ? warp.liquifyMode.rawValue : warp.mode.rawValue
            // The tip is solid and a little wider than the brush, so a point every twentieth of its width covers what
            // every dab did: a big brush on a big canvas lays thousands of dabs, and replaying each one stalled the release.
            let spacing = max(1, warp.diameter * 0.05)
            var kept: CGPoint?
            for (index, point) in warp.points.enumerated() {
                if let kept, index < warp.points.count - 1, hypot(point.x - kept.x, point.y - kept.y) < spacing { continue }
                try stroke.append(point)
                kept = point
            }
            try stroke.flush()
            if !stroke.patches.isEmpty { try commitPaintSnapshot(stroke) }
        } catch { brushError = error.localizedDescription }
    }
}
