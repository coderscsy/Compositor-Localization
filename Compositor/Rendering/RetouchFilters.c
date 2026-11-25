#include "RetouchFilters.h"
#include <math.h>
#include <string.h>

static inline float clamp01(float v) { return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v); }

void adjust_brightness_contrast(uint8_t *rgba, size_t width, size_t height, size_t stride,
                                float brightness, float contrast, int32_t legacy) {
    float b = brightness / 150.0f;
    float c = contrast / 100.0f;
    // Precompute a 256-entry LUT for fast, branch-free per-pixel mapping.
    uint8_t lut[256];
    for (int i = 0; i < 256; i++) {
        float x = (float)i / 255.0f;
        float y = x;
        if (legacy) {
            y = x + b * 0.5f;
            float slope = (c >= 0.0f) ? (1.0f / fmaxf(0.05f, 1.0f - c * 0.9f)) : (1.0f + c * 0.9f);
            y = (y - 0.5f) * slope + 0.5f;
        } else {
            // Modern Photoshop Brightness/Contrast: smooth midpoint curve for brightness and S-curve for contrast.
            if (b != 0.0f) {
                float lift = b * 0.45f;
                y = x + lift * (4.0f * x * (1.0f - x) * 0.7f + 0.3f * (b > 0.0f ? (1.0f - x) : x));
            }
            if (c != 0.0f) {
                float t = clamp01(y);
                float smooth = t * t * (3.0f - 2.0f * t);
                if (c > 0.0f) {
                    y = t + (smooth - t) * c * 1.35f;
                } else {
                    y = 0.5f + (t - 0.5f) * (1.0f + c * 0.85f);
                }
            }
        }
        lut[i] = (uint8_t)lroundf(clamp01(y) * 255.0f);
    }

    for (size_t y = 0; y < height; y++) {
        uint8_t *p = rgba + y * stride;
        for (size_t x = 0; x < width; x++, p += 4) {
            unsigned a = p[3];
            if (a == 0) continue;
            if (a == 255) {
                p[0] = lut[p[0]];
                p[1] = lut[p[1]];
                p[2] = lut[p[2]];
            } else {
                float inv = 255.0f / (float)a;
                int r = (int)lroundf(clamp01((float)p[0] * inv / 255.0f) * 255.0f);
                int g = (int)lroundf(clamp01((float)p[1] * inv / 255.0f) * 255.0f);
                int bl = (int)lroundf(clamp01((float)p[2] * inv / 255.0f) * 255.0f);
                float alpha = (float)a / 255.0f;
                p[0] = (uint8_t)lroundf((float)lut[r] * alpha);
                p[1] = (uint8_t)lroundf((float)lut[g] * alpha);
                p[2] = (uint8_t)lroundf((float)lut[bl] * alpha);
            }
        }
    }
}

void adjust_vibrance(uint8_t *rgba, size_t width, size_t height, size_t stride,
                     float vibrance, float saturation) {
    float vib = vibrance / 100.0f;
    float sat = saturation / 100.0f;
    for (size_t y = 0; y < height; y++) {
        uint8_t *p = rgba + y * stride;
        for (size_t x = 0; x < width; x++, p += 4) {
            unsigned a = p[3];
            if (a == 0) continue;
            float invA = (a == 255) ? (1.0f / 255.0f) : (1.0f / (float)a);
            float r = clamp01((float)p[0] * invA);
            float g = clamp01((float)p[1] * invA);
            float b = clamp01((float)p[2] * invA);

            float maxC = fmaxf(r, fmaxf(g, b));
            float minC = fminf(r, fminf(g, b));
            float chroma = maxC - minC;
            float lum = 0.2126f * r + 0.7152f * g + 0.0722f * b;

            // Vibrance boosts low-saturation colors more strongly and softens boost on warm skin hues.
            float skinProtect = 1.0f;
            if (vib > 0.0f && r > g && g > b) {
                float warmth = clamp01((r - b) * 2.0f);
                skinProtect = 1.0f - 0.35f * warmth;
            }
            float vibBoost = vib * (1.0f - chroma) * skinProtect;
            float factor = fmaxf(0.0f, 1.0f + sat + vibBoost);

            float outR = clamp01(lum + (r - lum) * factor);
            float outG = clamp01(lum + (g - lum) * factor);
            float outB = clamp01(lum + (b - lum) * factor);

            float alphaF = (float)a;
            p[0] = (uint8_t)lroundf(outR * alphaF);
            p[1] = (uint8_t)lroundf(outG * alphaF);
            p[2] = (uint8_t)lroundf(outB * alphaF);
        }
    }
}

void adjust_threshold(uint8_t *rgba, size_t width, size_t height, size_t stride, int32_t level) {
    if (level < 1) level = 1;
    if (level > 255) level = 255;
    for (size_t y = 0; y < height; y++) {
        uint8_t *p = rgba + y * stride;
        for (size_t x = 0; x < width; x++, p += 4) {
            unsigned a = p[3];
            if (a == 0) continue;
            unsigned r = p[0], g = p[1], b = p[2];
            if (a < 255) {
                r = (r * 255u + a / 2) / a; if (r > 255) r = 255;
                g = (g * 255u + a / 2) / a; if (g > 255) g = 255;
                b = (b * 255u + a / 2) / a; if (b > 255) b = 255;
            }
            int lum = (int)((2126u * r + 7152u * g + 722u * b + 5000u) / 10000u);
            uint8_t v = (lum >= level) ? (uint8_t)a : 0;
            p[0] = v;
            p[1] = v;
            p[2] = v;
        }
    }
}

void adjust_posterize(uint8_t *rgba, size_t width, size_t height, size_t stride, int32_t levels) {
    if (levels < 2) levels = 2;
    if (levels > 255) levels = 255;
    uint8_t lut[256];
    float steps = (float)(levels - 1);
    for (int i = 0; i < 256; i++) {
        float t = (float)i / 255.0f;
        float q = floorf(t * (float)levels);
        if (q > steps) q = steps;
        lut[i] = (uint8_t)lroundf((q / steps) * 255.0f);
    }
    for (size_t y = 0; y < height; y++) {
        uint8_t *p = rgba + y * stride;
        for (size_t x = 0; x < width; x++, p += 4) {
            unsigned a = p[3];
            if (a == 0) continue;
            if (a == 255) {
                p[0] = lut[p[0]];
                p[1] = lut[p[1]];
                p[2] = lut[p[2]];
            } else {
                unsigned r = (p[0] * 255u + a / 2) / a; if (r > 255) r = 255;
                unsigned g = (p[1] * 255u + a / 2) / a; if (g > 255) g = 255;
                unsigned b = (p[2] * 255u + a / 2) / a; if (b > 255) b = 255;
                p[0] = (uint8_t)((lut[r] * a + 127u) / 255u);
                p[1] = (uint8_t)((lut[g] * a + 127u) / 255u);
                p[2] = (uint8_t)((lut[b] * a + 127u) / 255u);
            }
        }
    }
}

static inline float selective_delta(float comp, float adj, float black, int32_t relative) {
    float k = relative ? (1.0f - comp) : 1.0f;
    // Apply per-channel CMY shift plus black (ink) shift, clamped as in Photoshop's Selective Color.
    float delta = (adj + black) * k;
    return clamp01(comp + delta) - comp;
}

void adjust_selective_color(uint8_t *rgba, size_t width, size_t height, size_t stride,
                            const float *adjustments, int32_t relative) {
    for (size_t y = 0; y < height; y++) {
        uint8_t *p = rgba + y * stride;
        for (size_t x = 0; x < width; x++, p += 4) {
            unsigned a = p[3];
            if (a == 0) continue;
            float invA = (a == 255) ? (1.0f / 255.0f) : (1.0f / (float)a);
            float r = clamp01((float)p[0] * invA);
            float g = clamp01((float)p[1] * invA);
            float b = clamp01((float)p[2] * invA);

            float maxC = fmaxf(r, fmaxf(g, b));
            float minC = fminf(r, fminf(g, b));
            float midC = r + g + b - maxC - minC;

            // Photoshop's 9 color-family weights:
            // 0:Reds, 1:Yellows, 2:Greens, 3:Cyans, 4:Blues, 5:Magentas, 6:Whites, 7:Neutrals, 8:Blacks.
            float w[9] = {0};
            if (maxC == r) w[0] = maxC - midC;
            if (minC == b) w[1] = midC - minC;
            if (maxC == g) w[2] = maxC - midC;
            if (minC == r) w[3] = midC - minC;
            if (maxC == b) w[4] = maxC - midC;
            if (minC == g) w[5] = midC - minC;
            if (minC > 0.5f) w[6] = (minC - 0.5f) * 2.0f;
            if (maxC > 0.0f && minC < 1.0f) w[7] = 1.0f - (fabsf(maxC - 0.5f) + fabsf(minC - 0.5f));
            if (maxC < 0.5f) w[8] = (0.5f - maxC) * 2.0f;

            // Work in CMY complement space (C = 1-R, M = 1-G, Y = 1-B).
            float c = 1.0f - r, m = 1.0f - g, yv = 1.0f - b;
            float dc = 0.0f, dm = 0.0f, dy = 0.0f;
            for (int f = 0; f < 9; f++) {
                float wf = w[f];
                if (wf <= 0.0f) continue;
                const float *adj = adjustments + f * 4;
                if (adj[0] == 0.0f && adj[1] == 0.0f && adj[2] == 0.0f && adj[3] == 0.0f) continue;
                dc += wf * selective_delta(c, adj[0], adj[3], relative);
                dm += wf * selective_delta(m, adj[1], adj[3], relative);
                dy += wf * selective_delta(yv, adj[2], adj[3], relative);
            }

            float outR = clamp01(1.0f - clamp01(c + dc));
            float outG = clamp01(1.0f - clamp01(m + dm));
            float outB = clamp01(1.0f - clamp01(yv + dy));

            float alphaF = (float)a;
            p[0] = (uint8_t)lroundf(outR * alphaF);
            p[1] = (uint8_t)lroundf(outG * alphaF);
            p[2] = (uint8_t)lroundf(outB * alphaF);
        }
    }
}

void adjust_color_lut(uint8_t *rgba, size_t width, size_t height, size_t stride,
                      const float *cube, int32_t dim, float intensity) {
    if (!cube || dim < 2 || intensity <= 0.0f) return;
    if (intensity > 1.0f) intensity = 1.0f;
    float scale = (float)(dim - 1);
    int maxIdx = dim - 1;

    for (size_t y = 0; y < height; y++) {
        uint8_t *p = rgba + y * stride;
        for (size_t x = 0; x < width; x++, p += 4) {
            unsigned a = p[3];
            if (a == 0) continue;
            float invA = (a == 255) ? (1.0f / 255.0f) : (1.0f / (float)a);
            float r = clamp01((float)p[0] * invA);
            float g = clamp01((float)p[1] * invA);
            float b = clamp01((float)p[2] * invA);

            float rf = r * scale, gf = g * scale, bf = b * scale;
            int r0 = (int)floorf(rf), g0 = (int)floorf(gf), b0 = (int)floorf(bf);
            int r1 = r0 < maxIdx ? r0 + 1 : maxIdx;
            int g1 = g0 < maxIdx ? g0 + 1 : maxIdx;
            int b1 = b0 < maxIdx ? b0 + 1 : maxIdx;
            float fr = rf - (float)r0, fg = gf - (float)g0, fb = bf - (float)b0;

            #define LUT_AT(ri, gi, bi, ch) cube[(((bi) * dim + (gi)) * dim + (ri)) * 3 + (ch)]
            float out[3];
            for (int ch = 0; ch < 3; ch++) {
                float c000 = LUT_AT(r0, g0, b0, ch);
                float c100 = LUT_AT(r1, g0, b0, ch);
                float c010 = LUT_AT(r0, g1, b0, ch);
                float c110 = LUT_AT(r1, g1, b0, ch);
                float c001 = LUT_AT(r0, g0, b1, ch);
                float c101 = LUT_AT(r1, g0, b1, ch);
                float c011 = LUT_AT(r0, g1, b1, ch);
                float c111 = LUT_AT(r1, g1, b1, ch);
                float c00 = c000 + (c100 - c000) * fr;
                float c10 = c010 + (c110 - c010) * fr;
                float c01 = c001 + (c101 - c001) * fr;
                float c11 = c011 + (c111 - c011) * fr;
                float c0 = c00 + (c10 - c00) * fg;
                float c1 = c01 + (c11 - c01) * fg;
                out[ch] = clamp01(c0 + (c1 - c0) * fb);
            }
            #undef LUT_AT

            float outR = r + (out[0] - r) * intensity;
            float outG = g + (out[1] - g) * intensity;
            float outB = b + (out[2] - b) * intensity;
            float alphaF = (float)a;
            p[0] = (uint8_t)lroundf(outR * alphaF);
            p[1] = (uint8_t)lroundf(outG * alphaF);
            p[2] = (uint8_t)lroundf(outB * alphaF);
        }
    }
}

void filter_high_pass(uint8_t *rgba, const uint8_t *blurred, size_t width, size_t height,
                      size_t stride, size_t blurred_stride) {
    for (size_t y = 0; y < height; y++) {
        uint8_t *p = rgba + y * stride;
        const uint8_t *b = blurred + y * blurred_stride;
        for (size_t x = 0; x < width; x++, p += 4, b += 4) {
            unsigned a = p[3];
            if (a == 0) continue;
            float invA = (a == 255) ? (1.0f / 255.0f) : (1.0f / (float)a);
            float invB = (b[3] == 0) ? 0.0f : (b[3] == 255 ? (1.0f / 255.0f) : (1.0f / (float)b[3]));
            float r = clamp01((float)p[0] * invA);
            float g = clamp01((float)p[1] * invA);
            float bl = clamp01((float)p[2] * invA);
            float br = clamp01((float)b[0] * invB);
            float bg = clamp01((float)b[1] * invB);
            float bb = clamp01((float)b[2] * invB);

            // Photoshop High Pass: 0.5 + (original - blurred), clamped to 0...1, preserving alpha.
            float outR = clamp01(0.5f + (r - br));
            float outG = clamp01(0.5f + (g - bg));
            float outB = clamp01(0.5f + (bl - bb));
            float alphaF = (float)a;
            p[0] = (uint8_t)lroundf(outR * alphaF);
            p[1] = (uint8_t)lroundf(outG * alphaF);
            p[2] = (uint8_t)lroundf(outB * alphaF);
        }
    }
}

void filter_offset(const uint8_t *src, uint8_t *dst, size_t width, size_t height,
                   size_t src_stride, size_t dst_stride, int32_t dx, int32_t dy, int32_t edge_mode) {
    if (width == 0 || height == 0) return;
    int64_t w = (int64_t)width, h = (int64_t)height;
    for (int64_t y = 0; y < h; y++) {
        uint8_t *row = dst + (size_t)y * dst_stride;
        int64_t sy = y - dy;
        int y_out = 0;
        if (edge_mode == 0) {
            sy = ((sy % h) + h) % h;
        } else if (edge_mode == 1) {
            if (sy < 0) sy = 0;
            if (sy >= h) sy = h - 1;
        } else {
            if (sy < 0 || sy >= h) y_out = 1;
        }
        if (y_out) {
            memset(row, 0, width * 4);
            continue;
        }
        const uint8_t *srow = src + (size_t)sy * src_stride;
        for (int64_t x = 0; x < w; x++) {
            int64_t sx = x - dx;
            uint8_t *dp = row + (size_t)x * 4;
            if (edge_mode == 0) {
                sx = ((sx % w) + w) % w;
            } else if (edge_mode == 1) {
                if (sx < 0) sx = 0;
                if (sx >= w) sx = w - 1;
            } else if (sx < 0 || sx >= w) {
                dp[0] = dp[1] = dp[2] = dp[3] = 0;
                continue;
            }
            const uint8_t *sp = srow + (size_t)sx * 4;
            dp[0] = sp[0]; dp[1] = sp[1]; dp[2] = sp[2]; dp[3] = sp[3];
        }
    }
}
