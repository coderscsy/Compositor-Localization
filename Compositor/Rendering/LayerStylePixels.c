#include "LayerStylePixels.h"
#include <math.h>
#include <stdlib.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static inline float clampf01(float v) {
    return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v);
}

static inline uint8_t to_u8(float v) {
    float c = clampf01(v) * 255.0f;
    return (uint8_t)(c + 0.5f);
}

static inline float blend_channel(float s, float d, int32_t mode) {
    switch (mode) {
        case 1: // Multiply
            return s * d;
        case 2: // Screen
            return 1.0f - (1.0f - s) * (1.0f - d);
        case 3: // Overlay
            return d < 0.5f ? (2.0f * s * d) : (1.0f - 2.0f * (1.0f - s) * (1.0f - d));
        case 4: { // Soft Light (W3C / Photoshop approximation)
            if (s <= 0.5f) {
                return d - (1.0f - 2.0f * s) * d * (1.0f - d);
            } else {
                float g = (d <= 0.25f) ? (((16.0f * d - 12.0f) * d + 4.0f) * d) : sqrtf(d);
                return d + (2.0f * s - 1.0f) * (g - d);
            }
        }
        case 5: // Hard Light
            return s < 0.5f ? (2.0f * s * d) : (1.0f - 2.0f * (1.0f - s) * (1.0f - d));
        case 6: // Darken
            return s < d ? s : d;
        case 7: // Lighten
            return s > d ? s : d;
        case 8: // Color Dodge
            if (d <= 0.0f) return 0.0f;
            if (s >= 1.0f) return 1.0f;
            return clampf01(d / (1.0f - s));
        case 9: // Color Burn
            if (d >= 1.0f) return 1.0f;
            if (s <= 0.0f) return 0.0f;
            return 1.0f - clampf01((1.0f - d) / s);
        case 10: // Linear Dodge (Add)
            return clampf01(s + d);
        default: // 0: Normal
            return s;
    }
}

static inline void composite_pixel(uint8_t *dp, float sr, float sg, float sb, float sa, int32_t mode) {
    if (sa <= 0.0001f) return;
    float da = (float)dp[3] / 255.0f;
    if (da <= 0.0001f) {
        dp[0] = to_u8(sr * sa);
        dp[1] = to_u8(sg * sa);
        dp[2] = to_u8(sb * sa);
        dp[3] = to_u8(sa);
        return;
    }
    float dr = clampf01(((float)dp[0] / 255.0f) / da);
    float dg = clampf01(((float)dp[1] / 255.0f) / da);
    float db = clampf01(((float)dp[2] / 255.0f) / da);

    float br = blend_channel(sr, dr, mode);
    float bg = blend_channel(sg, dg, mode);
    float bb = blend_channel(sb, db, mode);

    float outA = sa + da * (1.0f - sa);
    float outR = sr * sa * (1.0f - da) + dr * da * (1.0f - sa) + sa * da * br;
    float outG = sg * sa * (1.0f - da) + dg * da * (1.0f - sa) + sa * da * bg;
    float outB = sb * sa * (1.0f - da) + db * da * (1.0f - sa) + sa * da * bb;

    dp[0] = to_u8(outR);
    dp[1] = to_u8(outG);
    dp[2] = to_u8(outB);
    dp[3] = to_u8(outA);
}

void style_apply_spread(uint8_t *alpha, int32_t stride, int32_t width, int32_t height, float spreadPercent) {
    if (!alpha || width <= 0 || height <= 0 || spreadPercent <= 0.01f) return;
    float s = clampf01(spreadPercent / 100.0f);
    // Photoshop spread expands the upper portion of a blurred matte toward full opacity:
    // at 0% unchanged, at 100% hard threshold near 0.5.
    float denom = 1.0f - s * 0.96f;
    for (int32_t y = 0; y < height; y++) {
        uint8_t *row = alpha + (size_t)y * (size_t)stride;
        for (int32_t x = 0; x < width; x++) {
            if (row[x] == 0 || row[x] == 255) continue;
            float v = (float)row[x] / 255.0f;
            float boosted = clampf01(v / denom);
            row[x] = to_u8(boosted);
        }
    }
}

void style_blend_solid(uint8_t *dst, int32_t dstStride,
                       const uint8_t *coverage, int32_t covStride,
                       const uint8_t *clipMask, int32_t clipStride,
                       int32_t width, int32_t height,
                       float r, float g, float b, float opacity,
                       int32_t blendMode) {
    if (!dst || !coverage || width <= 0 || height <= 0 || opacity <= 0.0001f) return;
    for (int32_t y = 0; y < height; y++) {
        uint8_t *dRow = dst + (size_t)y * (size_t)dstStride;
        const uint8_t *cRow = coverage + (size_t)y * (size_t)covStride;
        const uint8_t *mRow = clipMask ? (clipMask + (size_t)y * (size_t)clipStride) : NULL;
        for (int32_t x = 0; x < width; x++) {
            float cov = (float)cRow[x] / 255.0f;
            if (cov <= 0.0001f) continue;
            if (mRow) {
                cov *= (float)mRow[x] / 255.0f;
                if (cov <= 0.0001f) continue;
            }
            composite_pixel(dRow + x * 4, r, g, b, clampf01(cov * opacity), blendMode);
        }
    }
}

static inline void sample_gradient(const StyleGradientStop *stops, int32_t count, float t,
                                   float *r, float *g, float *b, float *a) {
    if (count <= 0) { *r = 0; *g = 0; *b = 0; *a = 1; return; }
    if (count == 1 || t <= stops[0].position) {
        *r = stops[0].r; *g = stops[0].g; *b = stops[0].b; *a = stops[0].a;
        return;
    }
    if (t >= stops[count - 1].position) {
        *r = stops[count - 1].r; *g = stops[count - 1].g; *b = stops[count - 1].b; *a = stops[count - 1].a;
        return;
    }
    for (int32_t i = 0; i < count - 1; i++) {
        if (t <= stops[i + 1].position) {
            float span = stops[i + 1].position - stops[i].position;
            float f = span > 0.00001f ? clampf01((t - stops[i].position) / span) : 0.0f;
            *r = stops[i].r + (stops[i + 1].r - stops[i].r) * f;
            *g = stops[i].g + (stops[i + 1].g - stops[i].g) * f;
            *b = stops[i].b + (stops[i + 1].b - stops[i].b) * f;
            *a = stops[i].a + (stops[i + 1].a - stops[i].a) * f;
            return;
        }
    }
    *r = stops[count - 1].r; *g = stops[count - 1].g; *b = stops[count - 1].b; *a = stops[count - 1].a;
}

void style_render_gradient_overlay(uint8_t *dst, int32_t dstStride,
                                   const uint8_t *layerAlpha, int32_t alphaStride,
                                   int32_t width, int32_t height,
                                   float boxX, float boxY, float boxW, float boxH,
                                   int32_t shape, float angleDeg, float scalePercent, int32_t reverse,
                                   float opacity, int32_t blendMode,
                                   const StyleGradientStop *stops, int32_t stopCount) {
    if (!dst || !layerAlpha || !stops || stopCount <= 0 || width <= 0 || height <= 0 || opacity <= 0.0001f) return;
    float cx = boxX + boxW * 0.5f;
    float cy = boxY + boxH * 0.5f;
    float rad = angleDeg * (float)(M_PI / 180.0);
    // Photoshop 90 deg goes bottom-to-top (in screen y-down coords, -sin).
    float dx = cosf(rad);
    float dy = -sinf(rad);
    float scale = fmaxf(0.1f, scalePercent / 100.0f);
    float halfExtent = fmaxf(1.0f, 0.5f * (fabsf(dx) * boxW + fabsf(dy) * boxH) * scale);
    float radius = fmaxf(1.0f, 0.5f * hypotf(boxW, boxH) * scale);

    for (int32_t y = 0; y < height; y++) {
        uint8_t *dRow = dst + (size_t)y * (size_t)dstStride;
        const uint8_t *aRow = layerAlpha + (size_t)y * (size_t)alphaStride;
        for (int32_t x = 0; x < width; x++) {
            uint8_t la = aRow[x];
            if (la == 0) continue;
            float px = ((float)x + 0.5f) - cx;
            float py = ((float)y + 0.5f) - cy;
            float t = 0.0f;
            switch (shape) {
                case 1: // Radial
                    t = clampf01(hypotf(px, py) / radius);
                    break;
                case 2: { // Angle
                    float a = atan2f(-py, px) - rad;
                    float norm = fmodf(a / (float)(2.0 * M_PI), 1.0f);
                    if (norm < 0.0f) norm += 1.0f;
                    t = clampf01(norm);
                    break;
                }
                case 3: { // Reflected
                    float proj = (px * dx + py * dy) / halfExtent;
                    t = clampf01(fabsf(proj));
                    break;
                }
                case 4: { // Diamond
                    float rx = px * dx + py * dy;
                    float ry = -px * dy + py * dx;
                    t = clampf01((fabsf(rx) + fabsf(ry)) / radius);
                    break;
                }
                default: { // 0: Linear
                    float proj = (px * dx + py * dy) / (2.0f * halfExtent) + 0.5f;
                    t = clampf01(proj);
                    break;
                }
            }
            if (reverse) t = 1.0f - t;
            float gr, gg, gb, ga;
            sample_gradient(stops, stopCount, t, &gr, &gg, &gb, &ga);
            float cov = ((float)la / 255.0f) * ga * opacity;
            composite_pixel(dRow + x * 4, gr, gg, gb, clampf01(cov), blendMode);
        }
    }
}

static inline uint32_t pattern_hash(uint32_t x) {
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

void style_render_pattern_overlay(uint8_t *dst, int32_t dstStride,
                                  const uint8_t *layerAlpha, int32_t alphaStride,
                                  int32_t width, int32_t height,
                                  int32_t pattern, float scalePercent,
                                  float r, float g, float b, float opacity, int32_t blendMode) {
    if (!dst || !layerAlpha || width <= 0 || height <= 0 || opacity <= 0.0001f) return;
    float period = fmaxf(4.0f, 16.0f * (scalePercent / 100.0f));
    for (int32_t y = 0; y < height; y++) {
        uint8_t *dRow = dst + (size_t)y * (size_t)dstStride;
        const uint8_t *aRow = layerAlpha + (size_t)y * (size_t)alphaStride;
        for (int32_t x = 0; x < width; x++) {
            uint8_t la = aRow[x];
            if (la == 0) continue;
            float u = fmodf((float)x / period, 1.0f);
            float v = fmodf((float)y / period, 1.0f);
            if (u < 0.0f) u += 1.0f;
            if (v < 0.0f) v += 1.0f;
            float pat = 0.0f;
            switch (pattern) {
                case 0: // Checkerboard
                    pat = ((u < 0.5f) != (v < 0.5f)) ? 1.0f : 0.0f;
                    break;
                case 1: // Stripes (vertical)
                    pat = (u < 0.5f) ? 1.0f : 0.0f;
                    break;
                case 2: { // Diagonal Stripes
                    float d = fmodf(u + v, 1.0f);
                    pat = (d < 0.5f) ? 1.0f : 0.0f;
                    break;
                }
                case 3: { // Polka Dots
                    float dist = hypotf(u - 0.5f, v - 0.5f);
                    float edge = 1.0f / period;
                    pat = clampf01((0.30f - dist) / fmaxf(0.02f, edge) + 0.5f);
                    break;
                }
                case 4: { // Grid
                    float lineW = fmaxf(0.08f, 1.5f / period);
                    pat = (u < lineW || v < lineW) ? 1.0f : 0.0f;
                    break;
                }
                case 5: { // Crosshatch
                    float lineW = fmaxf(0.07f, 1.4f / period);
                    float d1 = fmodf(u + v, 1.0f);
                    float d2 = fmodf(u - v + 1.0f, 1.0f);
                    pat = (d1 < lineW || d2 < lineW) ? 1.0f : 0.0f;
                    break;
                }
                default: { // 6: Fine Noise
                    uint32_t gx = (uint32_t)floorf((float)x / fmaxf(1.0f, scalePercent / 100.0f));
                    uint32_t gy = (uint32_t)floorf((float)y / fmaxf(1.0f, scalePercent / 100.0f));
                    uint32_t h = pattern_hash((gx * 0x9e3779b1u) ^ (gy * 0x85ebca77u));
                    pat = (float)(h >> 8) / 16777216.0f;
                    break;
                }
            }
            if (pat <= 0.0001f) continue;
            float cov = ((float)la / 255.0f) * pat * opacity;
            composite_pixel(dRow + x * 4, r, g, b, clampf01(cov), blendMode);
        }
    }
}

void style_render_bevel_emboss(uint8_t *dst, int32_t dstStride,
                               const uint8_t *layerAlpha, int32_t alphaStride,
                               const uint8_t *heightField, int32_t heightStride,
                               int32_t width, int32_t height,
                               int32_t style, int32_t directionDown,
                               float depthPercent, float angleDeg, float altitudeDeg,
                               float hiR, float hiG, float hiB, float hiOpacity, int32_t hiBlendMode,
                               float shR, float shG, float shB, float shOpacity, int32_t shBlendMode) {
    if (!dst || !layerAlpha || !heightField || width <= 0 || height <= 0) return;
    float az = angleDeg * (float)(M_PI / 180.0);
    float alt = clampf01(altitudeDeg / 90.0f) * (float)(M_PI * 0.5);
    // Light vector in screen space (x right, y down, z out of screen).
    float lx = cosf(az) * cosf(alt);
    float ly = -sinf(az) * cosf(alt);
    float lz = sinf(alt);
    float depthScale = fmaxf(0.05f, depthPercent / 100.0f) * 6.0f;
    float dirSign = directionDown ? -1.0f : 1.0f;

    for (int32_t y = 0; y < height; y++) {
        int32_t y0 = y > 0 ? y - 1 : 0;
        int32_t y1 = y + 1 < height ? y + 1 : height - 1;
        uint8_t *dRow = dst + (size_t)y * (size_t)dstStride;
        const uint8_t *aRow = layerAlpha + (size_t)y * (size_t)alphaStride;
        const uint8_t *hPrev = heightField + (size_t)y0 * (size_t)heightStride;
        const uint8_t *hCurr = heightField + (size_t)y * (size_t)heightStride;
        const uint8_t *hNext = heightField + (size_t)y1 * (size_t)heightStride;

        for (int32_t x = 0; x < width; x++) {
            float la = (float)aRow[x] / 255.0f;
            float mask = 0.0f;
            float localSign = dirSign;
            switch (style) {
                case 0: // Inner Bevel
                    mask = la;
                    break;
                case 1: // Outer Bevel
                    mask = 1.0f - la;
                    localSign = -dirSign;
                    break;
                case 2: // Emboss (both inside & outside)
                    mask = 1.0f;
                    break;
                case 3: // Pillow Emboss (reverses slope across edge)
                    mask = 1.0f;
                    localSign = (la >= 0.5f) ? dirSign : -dirSign;
                    break;
                default:
                    mask = la;
                    break;
            }
            if (mask <= 0.001f) continue;

            int32_t x0 = x > 0 ? x - 1 : 0;
            int32_t x1 = x + 1 < width ? x + 1 : width - 1;
            float gx = ((float)hCurr[x1] - (float)hCurr[x0]) / 510.0f;
            float gy = ((float)hNext[x] - (float)hPrev[x]) / 510.0f;
            float gradMag = hypotf(gx, gy);
            if (gradMag <= 0.0005f) continue;

            float nx = -gx * depthScale * localSign;
            float ny = -gy * depthScale * localSign;
            float nz = 1.0f;
            float invLen = 1.0f / sqrtf(nx * nx + ny * ny + nz * nz);
            nx *= invLen; ny *= invLen; nz *= invLen;

            float ndotl = nx * lx + ny * ly + nz * lz;
            float delta = ndotl - lz;
            // Weight by how strongly sloped the pixel is so flat interiors stay untouched.
            float slopeWeight = clampf01(gradMag * 12.0f) * mask;
            if (delta > 0.0f && hiOpacity > 0.0001f) {
                float denom = fmaxf(0.05f, 1.0f - lz);
                float amt = clampf01(delta / denom) * slopeWeight * hiOpacity;
                composite_pixel(dRow + x * 4, hiR, hiG, hiB, amt, hiBlendMode);
            } else if (delta < 0.0f && shOpacity > 0.0001f) {
                float denom = fmaxf(0.05f, lz + 0.5f);
                float amt = clampf01((-delta) / denom) * slopeWeight * shOpacity;
                composite_pixel(dRow + x * 4, shR, shG, shB, amt, shBlendMode);
            }
        }
    }
}
