import CoreGraphics
import CoreImage

/// Blend modes and Blend If compositing that Core Graphics cannot draw directly.
///
/// Covers:
/// - Modes Core Image computes (Color Burn, Color Dodge, Soft Light, Linear Burn/Dodge, Vivid/Linear/Pin Light,
///   Hard Mix, Subtract, Divide),
/// - Custom pixel-kernel modes (Dissolve, Darker Color, Lighter Color),
/// - Blend If tonal visibility ranges (This Layer / Underlying Layer) combined with any of the 27 blend modes.
nonisolated enum SeparableBlend {
    /// Whether this mode / Blend If combination must be composited through an offscreen surface.
    static func needsSurface(_ mode: LayerBlendMode, blendIf: BlendIfSettings? = nil) -> Bool {
        mode.coreImageFilter != nil || mode.usesCustomBlend || blendIf?.nonIdentity != nil
    }

    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    // Core Image works in a linear space unless told otherwise, and several modes depend on gamma-encoded sRGB.
    private static let ciContext = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: space])

    private static func makeRGBA8Surface(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: space, bitmapInfo: bitmapInfo)
    }

    private static func copyToRGBA8(_ image: CGImage, width: Int, height: Int) -> CGContext? {
        guard let ctx = makeRGBA8Surface(width: width, height: height) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setBlendMode(.copy)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }

    /// Draws one layer into `context` in `mode` (and optional `blendIf`). `body` draws it as it would be drawn
    /// normally, into a context laid out exactly like `context`. Only a bitmap-backed context can be read back.
    static func draw(_ mode: LayerBlendMode, blendIf: BlendIfSettings? = nil,
                     in context: CGContext, body: (CGContext) -> Void) -> Bool {
        guard needsSurface(mode, blendIf: blendIf),
              context.data != nil, context.width > 0, context.height > 0,
              let surface = makeRGBA8Surface(width: context.width, height: context.height) else { return false }
        surface.concatenate(context.ctm)
        body(surface)
        guard let source = surface.makeImage() else { return false }
        return blend(source, over: context, mode: mode, blendIf: blendIf)
    }

    /// `top` blended over what `bottom` holds (the same size), written back into `bottom`.
    /// Returns false only when Core Graphics can draw it directly (no custom mode, no Core Image filter, no Blend If).
    static func blend(_ top: CGImage, over bottom: CGContext, mode: LayerBlendMode,
                      blendIf: BlendIfSettings? = nil) -> Bool {
        guard needsSurface(mode, blendIf: blendIf),
              bottom.data != nil, bottom.width > 0, bottom.height > 0,
              let under = bottom.makeImage() else { return false }
        let width = bottom.width, height = bottom.height
        let frame = CGRect(x: 0, y: 0, width: width, height: height)

        var sourceImage = top
        if let activeBlendIf = blendIf?.nonIdentity {
            guard let srcCtx = copyToRGBA8(top, width: width, height: height),
                  let dstCtx = copyToRGBA8(under, width: width, height: height),
                  let srcBytes = srcCtx.data?.assumingMemoryBound(to: UInt8.self),
                  let dstBytes = dstCtx.data?.assumingMemoryBound(to: UInt8.self) else { return false }
            blend_apply_blend_if(srcBytes, Int32(srcCtx.bytesPerRow),
                                 dstBytes, Int32(dstCtx.bytesPerRow),
                                 Int32(width), Int32(height),
                                 activeBlendIf.cParams)
            guard let masked = srcCtx.makeImage() else { return false }
            sourceImage = masked
        }

        if mode.usesCustomBlend {
            guard let srcCtx = copyToRGBA8(sourceImage, width: width, height: height),
                  let dstCtx = copyToRGBA8(under, width: width, height: height),
                  let srcBytes = srcCtx.data?.assumingMemoryBound(to: UInt8.self),
                  let dstBytes = dstCtx.data?.assumingMemoryBound(to: UInt8.self) else { return false }
            switch mode {
            case .dissolve:
                blend_dissolve(srcBytes, Int32(srcCtx.bytesPerRow),
                               dstBytes, Int32(dstCtx.bytesPerRow),
                               Int32(width), Int32(height), 0, 0)
            case .darkerColor:
                blend_darker_color(srcBytes, Int32(srcCtx.bytesPerRow),
                                   dstBytes, Int32(dstCtx.bytesPerRow),
                                   Int32(width), Int32(height))
            case .lighterColor:
                blend_lighter_color(srcBytes, Int32(srcCtx.bytesPerRow),
                                    dstBytes, Int32(dstCtx.bytesPerRow),
                                    Int32(width), Int32(height))
            default:
                break
            }
            guard let blended = dstCtx.makeImage() else { return false }
            writeBack(blended, into: bottom, frame: frame)
            return true
        }

        if let name = mode.coreImageFilter, let filter = CIFilter(name: name) {
            filter.setValue(CIImage(cgImage: sourceImage), forKey: kCIInputImageKey)
            filter.setValue(CIImage(cgImage: under), forKey: kCIInputBackgroundImageKey)
            guard let output = filter.outputImage,
                  let blended = ciContext.createCGImage(output, from: frame, format: .RGBA8, colorSpace: space) else { return false }
            writeBack(blended, into: bottom, frame: frame)
            return true
        }

        // Standard Core Graphics blend mode with Blend If active: composite the Blend-If-masked source onto `bottom`.
        bottom.saveGState()
        bottom.concatenate(bottom.ctm.inverted())
        bottom.setBlendMode(mode.cgMode)
        bottom.setAlpha(1)
        bottom.draw(sourceImage, in: frame)
        bottom.restoreGState()
        return true
    }

    private static func writeBack(_ image: CGImage, into context: CGContext, frame: CGRect) {
        context.saveGState()
        context.concatenate(context.ctm.inverted())
        context.setBlendMode(.copy)
        context.setAlpha(1)
        context.draw(image, in: frame)
        context.restoreGState()
    }
}
