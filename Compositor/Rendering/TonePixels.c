#include "TonePixels.h"
#include <math.h>

static inline float clamp01(float v) { return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v); }

static inline float tonal_weight(float lum, int32_t range) {
    if (range == 0) {
        // Shadows: peaks near 0, tapers smoothly to 0 at white.
        float inv = 1.0f - lum;
        return inv * inv;
    } else if (range == 2) {
        // Highlights: peaks near 1, tapers smoothly to 0 at black.
        return lum * lum;
    }
    // Midtones: bell curve peaking at 0.5, protecting pure black and white.
    return 4.0f * lum * (1.0f - lum);
}

static inline float dodge_channel(float c, float w, float strength, int32_t range) {
    float lifted = 1.0f - (1.0f - c) / (1.0f + strength * 1.8f * w);
    if (range == 0) {
        // Allow pure dark shadows to lift gently when dodging Shadows.
        lifted = clamp01(lifted + strength * 0.22f * w * (1.0f - c));
    }
    return clamp01(lifted);
}

static inline float burn_channel(float c, float w, float strength, int32_t range) {
    float darkened = c / (1.0f + strength * 1.8f * w);
    if (range == 2) {
        // Allow bright highlights to pull down cleanly when burning Highlights.
        darkened = clamp01(darkened - strength * 0.20f * w * c);
    }
    return clamp01(darkened);
}

void tone_adjust_rgba(uint8_t *rgba, size_t width, size_t height, size_t stride,
                      int32_t mode, int32_t range, float strength, int32_t protect_tones) {
    if (strength <= 0.0f) return;
    if (strength > 1.0f) strength = 1.0f;

    for (size_t y = 0; y < height; y++) {
        uint8_t *p = rgba + y * stride;
        for (size_t x = 0; x < width; x++, p += 4) {
            unsigned a = p[3];
            if (a == 0) continue;

            float invA = (a == 255) ? (1.0f / 255.0f) : (1.0f / (float)a);
            float r = clamp01((float)p[0] * invA);
            float g = clamp01((float)p[1] * invA);
            float b = clamp01((float)p[2] * invA);
            float lum = clamp01(0.2126f * r + 0.7152f * g + 0.0722f * b);

            float outR = r, outG = g, outB = b;

            if (mode == 0) {
                // Dodge (lighten)
                if (protect_tones) {
                    float w = tonal_weight(lum, range);
                    float targetLum = dodge_channel(lum, w, strength, range);
                    if (lum > 1e-4f) {
                        float scale = targetLum / lum;
                        outR = clamp01(r * scale);
                        outG = clamp01(g * scale);
                        outB = clamp01(b * scale);
                    } else {
                        outR = targetLum;
                        outG = targetLum;
                        outB = targetLum;
                    }
                } else {
                    outR = dodge_channel(r, tonal_weight(r, range), strength, range);
                    outG = dodge_channel(g, tonal_weight(g, range), strength, range);
                    outB = dodge_channel(b, tonal_weight(b, range), strength, range);
                }
            } else if (mode == 1) {
                // Burn (darken)
                if (protect_tones) {
                    float w = tonal_weight(lum, range);
                    float targetLum = burn_channel(lum, w, strength, range);
                    if (lum > 1e-4f) {
                        float scale = targetLum / lum;
                        outR = clamp01(r * scale);
                        outG = clamp01(g * scale);
                        outB = clamp01(b * scale);
                    } else {
                        outR = 0.0f;
                        outG = 0.0f;
                        outB = 0.0f;
                    }
                } else {
                    outR = burn_channel(r, tonal_weight(r, range), strength, range);
                    outG = burn_channel(g, tonal_weight(g, range), strength, range);
                    outB = burn_channel(b, tonal_weight(b, range), strength, range);
                }
            } else if (mode == 2) {
                // Sponge: Saturate
                float factor = 1.0f + strength * 1.25f;
                outR = clamp01(lum + (r - lum) * factor);
                outG = clamp01(lum + (g - lum) * factor);
                outB = clamp01(lum + (b - lum) * factor);
            } else if (mode == 3) {
                // Sponge: Desaturate
                float factor = 1.0f - strength;
                outR = clamp01(lum + (r - lum) * factor);
                outG = clamp01(lum + (g - lum) * factor);
                outB = clamp01(lum + (b - lum) * factor);
            }

            float alphaF = (float)a;
            p[0] = (uint8_t)lroundf(outR * alphaF);
            p[1] = (uint8_t)lroundf(outG * alphaF);
            p[2] = (uint8_t)lroundf(outB * alphaF);
        }
    }
}
