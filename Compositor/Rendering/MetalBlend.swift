import CoreImage
import Metal

/// GPU implementations of Dissolve, Darker Color, Lighter Color, and Blend If matching `BlendPixels.c`.
nonisolated enum MetalBlend {
    static func blend(_ top: CIImage, over bottom: CIImage, mode: LayerBlendMode) -> CIImage {
        let kernelName: String
        switch mode {
        case .dissolve: kernelName = "blend_dissolve"
        case .darkerColor: kernelName = "blend_darker_color"
        case .lighterColor: kernelName = "blend_lighter_color"
        default: return top.composited(over: bottom)
        }
        let extent = top.extent.union(bottom.extent).integral
        guard !extent.isEmpty, !extent.isInfinite, pipelines != nil else { return top.composited(over: bottom) }
        var dummy: UInt32 = 0
        let params = Data(bytes: &dummy, count: MemoryLayout<UInt32>.stride)
        return (try? BlendKernel.apply(withExtent: extent, inputs: [top, bottom],
                                       arguments: ["kernel": kernelName, "parameters": params]))
            ?? top.composited(over: bottom)
    }

    static func applyBlendIf(_ top: CIImage, over bottom: CIImage, settings: BlendIfSettings) -> CIImage {
        guard let clean = settings.nonIdentity else { return top }
        let extent = top.extent.integral
        guard !extent.isEmpty, !extent.isInfinite, pipelines != nil else { return top }
        var params = BlendIfUniforms(
            channel: UInt32(clean.channel.index),
            thisBlackLow: Float(clean.thisLayer.blackLow) / 255.0,
            thisBlackHigh: Float(clean.thisLayer.blackHigh) / 255.0,
            thisWhiteLow: Float(clean.thisLayer.whiteLow) / 255.0,
            thisWhiteHigh: Float(clean.thisLayer.whiteHigh) / 255.0,
            underBlackLow: Float(clean.underlyingLayer.blackLow) / 255.0,
            underBlackHigh: Float(clean.underlyingLayer.blackHigh) / 255.0,
            underWhiteLow: Float(clean.underlyingLayer.whiteLow) / 255.0,
            underWhiteHigh: Float(clean.underlyingLayer.whiteHigh) / 255.0
        )
        let data = Data(bytes: &params, count: MemoryLayout<BlendIfUniforms>.stride)
        return (try? BlendKernel.apply(withExtent: extent, inputs: [top, bottom],
                                       arguments: ["kernel": "blend_if_mask", "parameters": data]))
            ?? top
    }

    private struct BlendIfUniforms {
        var channel: UInt32
        var thisBlackLow: Float
        var thisBlackHigh: Float
        var thisWhiteLow: Float
        var thisWhiteHigh: Float
        var underBlackLow: Float
        var underBlackHigh: Float
        var underWhiteLow: Float
        var underWhiteHigh: Float
    }

    private struct Placement {
        var outOrigin: SIMD2<Int32>   // (output.minX, output.maxY - 1)
        var topOffset: SIMD2<Int32>   // (output.minX - top.minX, top.maxY - output.maxY)
        var botOffset: SIMD2<Int32>   // (output.minX - bot.minX, bot.maxY - output.maxY)
        var topSize: SIMD2<Int32>
        var botSize: SIMD2<Int32>
    }

    static let pipelines: [String: MTLComputePipelineState]? = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeLibrary(source: source, options: nil) else { return nil }
        var result: [String: MTLComputePipelineState] = [:]
        for name in ["blend_dissolve", "blend_darker_color", "blend_lighter_color", "blend_if_mask"] {
            guard let function = library.makeFunction(name: name),
                  let pipeline = try? device.makeComputePipelineState(function: function) else { return nil }
            result[name] = pipeline
        }
        return result
    }()

    private final class BlendKernel: CIImageProcessorKernel {
        override class var outputFormat: CIFormat { .RGBAh }
        override class func formatForInput(at input: Int32) -> CIFormat { .RGBAh }
        override class func roi(forInput input: Int32, arguments: [String: Any]?, outputRect: CGRect) -> CGRect {
            outputRect
        }

        override class func process(with inputs: [CIImageProcessorInput]?, arguments: [String: Any]?,
                                    output: CIImageProcessorOutput) throws {
            guard let inputs, inputs.count == 2,
                  let topTex = inputs[0].metalTexture,
                  let botTex = inputs[1].metalTexture,
                  let target = output.metalTexture,
                  let buffer = output.metalCommandBuffer,
                  let name = arguments?["kernel"] as? String,
                  var parameters = arguments?["parameters"] as? Data,
                  let pipeline = MetalBlend.pipelines?[name],
                  let encoder = buffer.makeComputeCommandEncoder() else { throw ExportError.render }
            var place = Placement(
                outOrigin: SIMD2(Int32(output.region.minX), Int32(output.region.maxY - 1)),
                topOffset: SIMD2(Int32(output.region.minX - inputs[0].region.minX),
                                 Int32(inputs[0].region.maxY - output.region.maxY)),
                botOffset: SIMD2(Int32(output.region.minX - inputs[1].region.minX),
                                 Int32(inputs[1].region.maxY - output.region.maxY)),
                topSize: SIMD2(Int32(topTex.width), Int32(topTex.height)),
                botSize: SIMD2(Int32(botTex.width), Int32(botTex.height))
            )
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(topTex, index: 0)
            encoder.setTexture(botTex, index: 1)
            encoder.setTexture(target, index: 2)
            parameters.withUnsafeMutableBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 0) }
            encoder.setBytes(&place, length: MemoryLayout<Placement>.stride, index: 1)
            let group = MTLSize(width: 16, height: 16, depth: 1)
            let grid = MTLSize(width: (target.width + 15) / 16, height: (target.height + 15) / 16, depth: 1)
            encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: group)
            encoder.endEncoding()
        }
    }

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct BlendIfUniforms {
        uint channel;
        float thisBlackLow;
        float thisBlackHigh;
        float thisWhiteLow;
        float thisWhiteHigh;
        float underBlackLow;
        float underBlackHigh;
        float underWhiteLow;
        float underWhiteHigh;
    };

    struct Placement {
        int2 outOrigin;
        int2 topOffset;
        int2 botOffset;
        int2 topSize;
        int2 botSize;
    };

    static inline float4 sampleTex(texture2d<float, access::read> tex, int2 coord, int2 sz) {
        if (coord.x < 0 || coord.y < 0 || coord.x >= sz.x || coord.y >= sz.y) {
            return float4(0.0);
        }
        return tex.read(uint2(coord));
    }

    static inline uint mix32(uint x) {
        x ^= x >> 16;
        x *= 0x7feb352du;
        x ^= x >> 15;
        x *= 0x846ca68bu;
        x ^= x >> 16;
        return x;
    }

    static inline float channelVal(float3 c, uint ch) {
        if (ch == 1u) return c.r;
        if (ch == 2u) return c.g;
        if (ch == 3u) return c.b;
        return 0.299f * c.r + 0.587f * c.g + 0.114f * c.b;
    }

    static inline float rangeFactor(float v, float bLow, float bHigh, float wLow, float wHigh) {
        float lowF = (bHigh > bLow) ? clamp((v - bLow) / (bHigh - bLow), 0.0f, 1.0f) : ((v >= bLow) ? 1.0f : 0.0f);
        float highF = (wHigh > wLow) ? clamp((wHigh - v) / (wHigh - wLow), 0.0f, 1.0f) : ((v <= wHigh) ? 1.0f : 0.0f);
        return lowF * highF;
    }

    kernel void blend_if_mask(texture2d<float, access::read> topTex [[texture(0)]],
                              texture2d<float, access::read> botTex [[texture(1)]],
                              texture2d<float, access::write> outTex [[texture(2)]],
                              constant BlendIfUniforms &p [[buffer(0)]],
                              constant Placement &place [[buffer(1)]],
                              uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
        int2 pos = int2(gid);
        float4 src = sampleTex(topTex, pos + place.topOffset, place.topSize);
        if (src.a <= 0.00001f) {
            outTex.write(float4(0.0), gid);
            return;
        }
        float3 cs = clamp(src.rgb / src.a, 0.0f, 1.0f);
        float sv = channelVal(cs, p.channel);
        float mThis = rangeFactor(sv, p.thisBlackLow, p.thisBlackHigh, p.thisWhiteLow, p.thisWhiteHigh);

        float factor = mThis;
        if (factor > 0.0f) {
            float4 dst = sampleTex(botTex, pos + place.botOffset, place.botSize);
            if (dst.a > 0.00001f) {
                float3 cb = clamp(dst.rgb / dst.a, 0.0f, 1.0f);
                float dv = channelVal(cb, p.channel);
                float mUnder = rangeFactor(dv, p.underBlackLow, p.underBlackHigh, p.underWhiteLow, p.underWhiteHigh);
                factor *= mix(1.0f, mUnder, clamp(dst.a, 0.0f, 1.0f));
            }
        }
        outTex.write(src * factor, gid);
    }

    kernel void blend_dissolve(texture2d<float, access::read> topTex [[texture(0)]],
                               texture2d<float, access::read> botTex [[texture(1)]],
                               texture2d<float, access::write> outTex [[texture(2)]],
                               constant uint &unused [[buffer(0)]],
                               constant Placement &place [[buffer(1)]],
                               uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
        int2 pos = int2(gid);
        float4 src = sampleTex(topTex, pos + place.topOffset, place.topSize);
        float4 dst = sampleTex(botTex, pos + place.botOffset, place.botSize);
        if (src.a <= 0.00001f) {
            outTex.write(dst, gid);
            return;
        }
        if (src.a >= 0.9999f) {
            outTex.write(float4(src.rgb / src.a, 1.0f), gid);
            return;
        }
        int cx = place.outOrigin.x + pos.x;
        int cy = place.outOrigin.y - pos.y;
        uint h = mix32((uint(cx) * 0x9e3779b1u) ^ (uint(cy) * 0x85ebca77u));
        float threshold = float(h >> 8) / 16777216.0f;
        if (threshold < src.a) {
            outTex.write(float4(src.rgb / src.a, 1.0f), gid);
        } else {
            outTex.write(dst, gid);
        }
    }

    static inline void blendLuma(texture2d<float, access::read> topTex,
                                 texture2d<float, access::read> botTex,
                                 texture2d<float, access::write> outTex,
                                 constant Placement &place,
                                 uint2 gid,
                                 bool pickLighter) {
        if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
        int2 pos = int2(gid);
        float4 src = sampleTex(topTex, pos + place.topOffset, place.topSize);
        float4 dst = sampleTex(botTex, pos + place.botOffset, place.botSize);
        float sa = clamp(src.a, 0.0f, 1.0f);
        if (sa <= 0.00001f) {
            outTex.write(dst, gid);
            return;
        }
        float da = clamp(dst.a, 0.0f, 1.0f);
        if (da <= 0.00001f) {
            outTex.write(src, gid);
            return;
        }
        float3 cs = src.rgb / sa;
        float3 cb = dst.rgb / da;
        float ls = 0.299f * cs.r + 0.587f * cs.g + 0.114f * cs.b;
        float lb = 0.299f * cb.r + 0.587f * cb.g + 0.114f * cb.b;
        float3 blended = (pickLighter ? (ls > lb) : (ls < lb)) ? cs : cb;
        float3 outRgb = src.rgb * (1.0f - da) + dst.rgb * (1.0f - sa) + (sa * da) * blended;
        float outA = sa + da * (1.0f - sa);
        outTex.write(float4(outRgb, outA), gid);
    }

    kernel void blend_darker_color(texture2d<float, access::read> topTex [[texture(0)]],
                                   texture2d<float, access::read> botTex [[texture(1)]],
                                   texture2d<float, access::write> outTex [[texture(2)]],
                                   constant uint &unused [[buffer(0)]],
                                   constant Placement &place [[buffer(1)]],
                                   uint2 gid [[thread_position_in_grid]]) {
        blendLuma(topTex, botTex, outTex, place, gid, false);
    }

    kernel void blend_lighter_color(texture2d<float, access::read> topTex [[texture(0)]],
                                    texture2d<float, access::read> botTex [[texture(1)]],
                                    texture2d<float, access::write> outTex [[texture(2)]],
                                    constant uint &unused [[buffer(0)]],
                                    constant Placement &place [[buffer(1)]],
                                    uint2 gid [[thread_position_in_grid]]) {
        blendLuma(topTex, botTex, outTex, place, gid, true);
    }
    """
}
