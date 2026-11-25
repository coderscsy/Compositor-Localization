import AppKit
import CoreGraphics
import CoreText

/// Photoshop-style Warp Text deformation presets (`.comp` format version 33).
nonisolated enum TextWarpStyle: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case arc = "Arc"
    case arch = "Arch"
    case bulge = "Bulge"
    case flag = "Flag"
    case wave = "Wave"
    case fish = "Fish"
    case rise = "Rise"
}

/// Non-destructive Warp Text parameters stored on `LayerTextStyle` (`.comp` format version 33).
nonisolated struct TextWarpSettings: Codable, Equatable, Sendable {
    var style: TextWarpStyle = .none
    /// Primary warp bend (-1…1, displayed as -100%…100%).
    var bend: CGFloat = 0.5
    /// Horizontal taper distortion (-1…1).
    var horizontalDistortion: CGFloat = 0
    /// Vertical taper distortion (-1…1).
    var verticalDistortion: CGFloat = 0

    var isActive: Bool { style != .none }
    var isValid: Bool {
        bend.isFinite && (-1...1).contains(bend)
            && horizontalDistortion.isFinite && (-1...1).contains(horizontalDistortion)
            && verticalDistortion.isFinite && (-1...1).contains(verticalDistortion)
    }
}

/// Extended typography renderers: Vertical Text, Text on Path, and Warp Text mesh resampling.
nonisolated enum TypographyRenderer {

    /// Renders vertical column typography (columns laid right-to-left, characters stacked top-to-bottom).
    static func renderVertical(_ style: LayerTextStyle) throws -> CGImage {
        let content = style.allCaps == true ? style.content.localizedUppercase : style.content
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let columns = max(1, lines.count)
        let maxChars = max(1, lines.map(\.count).max() ?? 1)
        let padding = LayerTextStyle.padding
        let colPitch = max(style.fontSize * 1.15, style.lineHeight)
        let charStep = max(style.fontSize * 0.6, style.fontSize * 1.08 + style.tracking * 0.08)

        let autoWidth = ceil(CGFloat(columns) * colPitch + padding * 2)
        let autoHeight = ceil(CGFloat(maxChars) * charStep + padding * 2 + style.fontSize * 0.4)
        let size = style.boxSize ?? CGSize(width: max(16, autoWidth), height: max(16, autoHeight))
        let width = Int(ceil(size.width)), height = Int(ceil(size.height))
        guard width >= 1, height >= 1, width <= DocumentLimits.maxSide, height <= DocumentLimits.maxSide,
              width * height <= DocumentLimits.maxSurfacePixels else { throw ProjectError.tooLarge }

        let context = try BrushRaster.context(width: width, height: height, mask: false)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

        let baseColor = NSColor(srgbRed: style.red, green: style.green, blue: style.blue, alpha: 1)
        let baseFont = NSFont(name: style.fontName, size: style.fontSize) ?? NSFont.systemFont(ofSize: style.fontSize)
        let baselineShift = style.baselineShift ?? 0

        var utf16Offset = 0
        for (colIdx, line) in lines.enumerated() {
            // Right-to-left columns, matching East Asian / Photoshop Vertical Type.
            let colCenterX = CGFloat(width) - padding - (CGFloat(colIdx) + 0.5) * colPitch + baselineShift
            var y = padding
            for ch in line {
                let chStr = String(ch)
                let color = style.color(at: utf16Offset)
                let fontName = style.fontName(at: utf16Offset)
                let font = NSFont(name: fontName, size: style.fontSize) ?? baseFont
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1),
                ]
                if style.underline == true { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if style.strikethrough == true { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                let attr = NSAttributedString(string: chStr, attributes: attrs)
                let chSize = attr.size()
                let drawPt = CGPoint(x: colCenterX - chSize.width / 2, y: y)
                attr.draw(at: drawPt)
                y += charStep
                utf16Offset += chStr.utf16.count
            }
            utf16Offset += 1 // newline
        }
        _ = baseColor
        guard let image = context.makeImage() else { throw ExportError.render }
        return image
    }

    /// Renders text flowing smoothly along the first non-empty subpath of `path`.
    static func renderOnPath(_ style: LayerTextStyle, path: VectorPath) throws -> CGImage {
        guard let sub = path.subpaths.first(where: { $0.anchors.count >= 2 }) else {
            return try renderEmptyFallback(style)
        }
        let samples = sub.arcLengthSamples(stepsPerSegment: 32)
        guard let totalLength = samples.last?.distance, totalLength > 1 else {
            return try renderEmptyFallback(style)
        }

        let cg = path.cgPath()
        let pathBounds = cg.boundingBoxOfPath
        let margin = max(LayerTextStyle.padding * 2, style.fontSize * 1.6 + abs(style.baselineShift ?? 0))
        let renderBounds = pathBounds.insetBy(dx: -margin, dy: -margin).integral
        let width = max(16, Int(ceil(renderBounds.width)))
        let height = max(16, Int(ceil(renderBounds.height)))
        guard width <= DocumentLimits.maxSide, height <= DocumentLimits.maxSide,
              width * height <= DocumentLimits.maxSurfacePixels else { throw ProjectError.tooLarge }

        let context = try BrushRaster.context(width: width, height: height, mask: false)
        // Map document coordinates into this layer's local top-left bitmap.
        context.translateBy(x: -renderBounds.minX, y: -renderBounds.minY)

        let attrString = EditorSession.attributedText(style)
        let ctLine = CTLineCreateWithAttributedString(attrString)
        let totalTextWidth = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        let startOffset: CGFloat
        switch style.alignment {
        case .left, .justified:
            startOffset = max(0, style.pathOffset ?? 0)
        case .center:
            startOffset = max(0, (totalLength - totalTextWidth) / 2 + (style.pathOffset ?? 0))
        case .right:
            startOffset = max(0, totalLength - totalTextWidth + (style.pathOffset ?? 0))
        }

        func sampleAt(_ dist: CGFloat) -> VectorSubpath.ArcSample? {
            guard dist >= 0, dist <= totalLength else { return nil }
            var lo = 0, hi = samples.count - 1
            while lo < hi {
                let mid = (lo + hi) / 2
                if samples[mid].distance < dist { lo = mid + 1 } else { hi = mid }
            }
            if lo == 0 { return samples[0] }
            let a = samples[lo - 1], b = samples[lo]
            let span = b.distance - a.distance
            let t: CGFloat = span > 1e-5 ? (dist - a.distance) / span : 0
            let pt = CGPoint(x: a.point.x + (b.point.x - a.point.x) * t,
                             y: a.point.y + (b.point.y - a.point.y) * t)
            let dx = a.tangent.dx + (b.tangent.dx - a.tangent.dx) * t
            let dy = a.tangent.dy + (b.tangent.dy - a.tangent.dy) * t
            let len = hypot(dx, dy)
            let tan = len > 1e-6 ? CGVector(dx: dx / len, dy: dy / len) : a.tangent
            return VectorSubpath.ArcSample(point: pt, tangent: tan, distance: dist)
        }

        let runs = CTLineGetGlyphRuns(ctLine) as? [CTRun] ?? []
        let baselineShift = style.baselineShift ?? 0
        var cursor = startOffset

        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let font = (attrs[kCTFontAttributeName] as! CTFont?) ?? CTFontCreateWithName(style.fontName as CFString, style.fontSize, nil)
            let fgNSColor = (attrs[NSAttributedString.Key.foregroundColor] as? NSColor)
                ?? NSColor(srgbRed: style.red, green: style.green, blue: style.blue, alpha: 1)

            var glyphs = [CGGlyph](repeating: 0, count: count)
            var advances = [CGSize](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetAdvances(run, CFRange(location: 0, length: count), &advances)

            for i in 0..<count {
                let adv = advances[i].width
                let midDist = cursor + adv / 2
                cursor += adv
                guard let sample = sampleAt(midDist) else { continue }
                let angle = atan2(sample.tangent.dy, sample.tangent.dx)

                context.saveGState()
                context.translateBy(x: sample.point.x, y: sample.point.y)
                context.rotate(by: angle)
                // BrushRaster context is y-down (flipped); flip locally so CoreText draws glyphs upright above the path!
                context.scaleBy(x: 1, y: -1)
                context.setFillColor(fgNSColor.cgColor)
                var g = glyphs[i]
                var pos = CGPoint(x: -adv / 2, y: baselineShift)
                CTFontDrawGlyphs(font, &g, &pos, 1, context)
                context.restoreGState()
            }
        }

        guard let image = context.makeImage() else { throw ExportError.render }
        return image
    }

    private static func renderEmptyFallback(_ style: LayerTextStyle) throws -> CGImage {
        let ctx = try BrushRaster.context(width: 16, height: 16, mask: false)
        guard let image = ctx.makeImage() else { throw ExportError.render }
        return image
    }

    /// Applies Photoshop-style Warp Text deformation to a rendered text bitmap using bilinear inverse mapping.
    static func applyWarp(_ source: CGImage, warp: TextWarpSettings) throws -> CGImage {
        guard warp.isActive else { return source }
        let sw = source.width, sh = source.height
        guard sw >= 1, sh >= 1 else { return source }

        let bend = Float(max(-1, min(1, warp.bend)))
        let hDist = Float(max(-1, min(1, warp.horizontalDistortion)))
        let vDist = Float(max(-1, min(1, warp.verticalDistortion)))

        // Expand output canvas vertically and horizontally so bent/bulged text never clips.
        let padY = Int(ceil(Float(sh) * (0.65 * abs(bend) + 0.25 * abs(vDist) + 0.1)))
        let padX = Int(ceil(Float(sw) * (0.25 * abs(bend) + 0.25 * abs(hDist) + 0.05)))
        let dw = min(DocumentLimits.maxSide, sw + padX * 2)
        let dh = min(DocumentLimits.maxSide, sh + padY * 2)
        guard dw * dh <= DocumentLimits.maxSurfacePixels else { return source }

        // Read source pixels into top-left RGBA8 buffer (preserving upright orientation).
        let srcCtx = try BrushRaster.context(width: sw, height: sh, mask: false)
        BrushRaster.draw(source, in: CGRect(x: 0, y: 0, width: sw, height: sh), mask: false, context: srcCtx)
        guard let srcData = srcCtx.data else { throw ExportError.render }
        let src = srcData.assumingMemoryBound(to: UInt8.self)

        let dstCtx = try BrushRaster.context(width: dw, height: dh, mask: false)
        guard let dstData = dstCtx.data else { throw ExportError.render }
        let dst = dstData.assumingMemoryBound(to: UInt8.self)

        let invHalfSW = 2.0 / Float(max(1, sw))
        let invHalfSH = 2.0 / Float(max(1, sh))
        let halfSW = Float(sw) * 0.5
        let halfSH = Float(sh) * 0.5
        let fPadX = Float(padX), fPadY = Float(padY)

        for y in 0..<dh {
            // Normalized coordinates relative to the original unpadded text box [-1, 1].
            let ny = (Float(y) - fPadY - halfSH) * invHalfSH
            for x in 0..<dw {
                let nx = (Float(x) - fPadX - halfSW) * invHalfSW

                // Invert horizontal/vertical perspective distortion.
                var u = nx
                var v = ny
                if abs(hDist) > 1e-4 {
                    let denom = max(0.2, 1.0 + hDist * 0.45 * nx)
                    v /= denom
                }
                if abs(vDist) > 1e-4 {
                    let denom = max(0.2, 1.0 + vDist * 0.45 * ny)
                    u /= denom
                }

                // Invert primary warp preset to find source normalized coordinates (su, sv).
                var su = u
                var sv = v
                switch warp.style {
                case .none:
                    break
                case .arch:
                    // Positive bend arches center upward (negative y in top-left coords).
                    sv = v + bend * 0.9 * (1.0 - u * u)
                case .arc:
                    // Parabolic arc with mild fan outward along curve normal.
                    let arch = bend * 0.85 * (1.0 - u * u)
                    sv = v + arch
                    su = u / max(0.35, 1.0 - bend * 0.22 * sv)
                case .bulge:
                    let scale = max(0.25, 1.0 + bend * 0.65 * (1.0 - u * u))
                    sv = v / scale
                case .flag:
                    sv = v + bend * 0.55 * sinf(u * .pi)
                case .wave:
                    sv = v + bend * 0.45 * sinf(u * 2.0 * .pi)
                case .fish:
                    let env = max(0.2, 1.0 + bend * 0.55 * cosf(u * .pi * 0.5) * (1.0 - 0.35 * u))
                    sv = v / env
                case .rise:
                    sv = v + bend * 0.65 * u
                }

                let sx = (su * halfSW) + halfSW
                let sy = (sv * halfSH) + halfSH
                guard sx >= 0, sx <= Float(sw - 1), sy >= 0, sy <= Float(sh - 1) else { continue }

                let x0 = Int(sx), y0 = Int(sy)
                let x1 = min(sw - 1, x0 + 1), y1 = min(sh - 1, y0 + 1)
                let fx = sx - Float(x0), fy = sy - Float(y0)
                let p00 = (y0 * sw + x0) * 4, p10 = (y0 * sw + x1) * 4
                let p01 = (y1 * sw + x0) * 4, p11 = (y1 * sw + x1) * 4
                let dp = (y * dw + x) * 4
                for k in 0..<4 {
                    let top = Float(src[p00 + k]) + (Float(src[p10 + k]) - Float(src[p00 + k])) * fx
                    let bot = Float(src[p01 + k]) + (Float(src[p11 + k]) - Float(src[p01 + k])) * fx
                    dst[dp + k] = UInt8(max(0, min(255, (top + (bot - top) * fy).rounded())))
                }
            }
        }
        guard let image = dstCtx.makeImage() else { throw ExportError.render }
        return image
    }
}
