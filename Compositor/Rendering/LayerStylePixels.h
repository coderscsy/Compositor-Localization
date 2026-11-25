#ifndef LAYER_STYLE_PIXELS_H
#define LAYER_STYLE_PIXELS_H

#include <stdint.h>

typedef struct {
    float position;
    float r, g, b, a;
} StyleGradientStop;

/// Applies Photoshop-style spread/choke (0..100) to an 8-bit grayscale coverage buffer in-place.
void style_apply_spread(uint8_t *alpha, int32_t stride, int32_t width, int32_t height, float spreadPercent);

/// Blends a solid color (r,g,b in 0..1) with `opacity` (0..1) and `coverage` (8-bit grayscale) onto
/// premultiplied RGBA8 `dst` using `blendMode` (0=Normal, 1=Multiply, 2=Screen, 3=Overlay, 4=SoftLight,
/// 5=HardLight, 6=Darken, 7=Lighten, 8=ColorDodge, 9=ColorBurn, 10=LinearDodge).
/// If `clipMask` is non-NULL, output alpha is constrained by `clipMask` (used for interior layer styles).
void style_blend_solid(uint8_t *dst, int32_t dstStride,
                       const uint8_t *coverage, int32_t covStride,
                       const uint8_t *clipMask, int32_t clipStride,
                       int32_t width, int32_t height,
                       float r, float g, float b, float opacity,
                       int32_t blendMode);

/// Renders a Gradient Overlay onto premultiplied RGBA8 `dst`, clipped to `layerAlpha` (8-bit grayscale).
/// `shape`: 0=Linear, 1=Radial, 2=Angle, 3=Reflected, 4=Diamond.
/// `boxX, boxY, boxW, boxH`: the layer's content bounding box inside the padded effect canvas.
void style_render_gradient_overlay(uint8_t *dst, int32_t dstStride,
                                   const uint8_t *layerAlpha, int32_t alphaStride,
                                   int32_t width, int32_t height,
                                   float boxX, float boxY, float boxW, float boxH,
                                   int32_t shape, float angleDeg, float scalePercent, int32_t reverse,
                                   float opacity, int32_t blendMode,
                                   const StyleGradientStop *stops, int32_t stopCount);

/// Renders a procedural Pattern Overlay onto premultiplied RGBA8 `dst`, clipped to `layerAlpha`.
/// `pattern`: 0=Checkerboard, 1=Stripes, 2=DiagonalStripes, 3=Dots, 4=Grid, 5=Crosshatch, 6=Noise.
void style_render_pattern_overlay(uint8_t *dst, int32_t dstStride,
                                  const uint8_t *layerAlpha, int32_t alphaStride,
                                  int32_t width, int32_t height,
                                  int32_t pattern, float scalePercent,
                                  float r, float g, float b, float opacity, int32_t blendMode);

/// Renders Bevel & Emboss shading onto premultiplied RGBA8 `dst` from `heightField` (0..255 smoothed alpha)
/// and `layerAlpha` (0..255 original alpha).
/// `style`: 0=InnerBevel, 1=OuterBevel, 2=Emboss, 3=PillowEmboss.
/// `directionDown`: 0=Up, 1=Down.
void style_render_bevel_emboss(uint8_t *dst, int32_t dstStride,
                               const uint8_t *layerAlpha, int32_t alphaStride,
                               const uint8_t *heightField, int32_t heightStride,
                               int32_t width, int32_t height,
                               int32_t style, int32_t directionDown,
                               float depthPercent, float angleDeg, float altitudeDeg,
                               float hiR, float hiG, float hiB, float hiOpacity, int32_t hiBlendMode,
                               float shR, float shG, float shB, float shOpacity, int32_t shBlendMode);

#endif /* LAYER_STYLE_PIXELS_H */
