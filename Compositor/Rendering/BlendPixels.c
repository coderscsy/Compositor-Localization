#include "BlendPixels.h"
#include <math.h>

static inline uint8_t clamp_u8(float v) {
    if (v <= 0.0f) return 0;
    if (v >= 255.0f) return 255;
    return (uint8_t)(v + 0.5f);
}

static inline float channel_value_255(float r, float g, float b, int32_t channel) {
    switch (channel) {
        case 1: return r;
        case 2: return g;
        case 3: return b;
        default: return 0.299f * r + 0.587f * g + 0.114f * b;
    }
}

static inline float range_factor(float v, int32_t bLow, int32_t bHigh, int32_t wLow, int32_t wHigh) {
    float lowFactor;
    if (bHigh > bLow) {
        lowFactor = (v - (float)bLow) / (float)(bHigh - bLow);
        if (lowFactor < 0.0f) lowFactor = 0.0f;
        else if (lowFactor > 1.0f) lowFactor = 1.0f;
    } else {
        lowFactor = (v >= (float)bLow) ? 1.0f : 0.0f;
    }

    float highFactor;
    if (wHigh > wLow) {
        highFactor = ((float)wHigh - v) / (float)(wHigh - wLow);
        if (highFactor < 0.0f) highFactor = 0.0f;
        else if (highFactor > 1.0f) highFactor = 1.0f;
    } else {
        highFactor = (v <= (float)wHigh) ? 1.0f : 0.0f;
    }
    return lowFactor * highFactor;
}

void blend_apply_blend_if(uint8_t *src, int32_t srcStride,
                          const uint8_t *dst, int32_t dstStride,
                          int32_t width, int32_t height,
                          BlendIfParams params) {
    if (!src || !dst || width <= 0 || height <= 0) return;
    int underIdentity = (params.underBlackLow <= 0 && params.underBlackHigh <= 0 &&
                         params.underWhiteLow >= 255 && params.underWhiteHigh >= 255);
    int thisIdentity = (params.thisBlackLow <= 0 && params.thisBlackHigh <= 0 &&
                        params.thisWhiteLow >= 255 && params.thisWhiteHigh >= 255);
    if (underIdentity && thisIdentity) return;

    for (int32_t y = 0; y < height; y++) {
        uint8_t *sRow = src + (size_t)y * (size_t)srcStride;
        const uint8_t *dRow = dst + (size_t)y * (size_t)dstStride;
        for (int32_t x = 0; x < width; x++) {
            uint8_t *sp = sRow + x * 4;
            uint8_t sa = sp[3];
            if (sa == 0) continue;

            float factor = 1.0f;
            if (!thisIdentity) {
                float invA = 255.0f / (float)sa;
                float sr = fminf(255.0f, (float)sp[0] * invA);
                float sg = fminf(255.0f, (float)sp[1] * invA);
                float sb = fminf(255.0f, (float)sp[2] * invA);
                float sv = channel_value_255(sr, sg, sb, params.channel);
                factor *= range_factor(sv, params.thisBlackLow, params.thisBlackHigh,
                                       params.thisWhiteLow, params.thisWhiteHigh);
            }
            if (!underIdentity && factor > 0.0f) {
                const uint8_t *dp = dRow + x * 4;
                uint8_t da = dp[3];
                if (da > 0) {
                    float invD = 255.0f / (float)da;
                    float dr = fminf(255.0f, (float)dp[0] * invD);
                    float dg = fminf(255.0f, (float)dp[1] * invD);
                    float db = fminf(255.0f, (float)dp[2] * invD);
                    float dv = channel_value_255(dr, dg, db, params.channel);
                    float mUnder = range_factor(dv, params.underBlackLow, params.underBlackHigh,
                                                params.underWhiteLow, params.underWhiteHigh);
                    float dAlpha = (float)da / 255.0f;
                    factor *= 1.0f + (mUnder - 1.0f) * dAlpha;
                }
            }
            if (factor <= 0.0f) {
                sp[0] = 0; sp[1] = 0; sp[2] = 0; sp[3] = 0;
            } else if (factor < 0.9999f) {
                sp[0] = clamp_u8((float)sp[0] * factor);
                sp[1] = clamp_u8((float)sp[1] * factor);
                sp[2] = clamp_u8((float)sp[2] * factor);
                sp[3] = clamp_u8((float)sa * factor);
            }
        }
    }
}

static inline uint32_t mix32(uint32_t x) {
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

void blend_dissolve(const uint8_t *src, int32_t srcStride,
                    uint8_t *dst, int32_t dstStride,
                    int32_t width, int32_t height,
                    int32_t originX, int32_t originY) {
    if (!src || !dst || width <= 0 || height <= 0) return;
    for (int32_t y = 0; y < height; y++) {
        const uint8_t *sRow = src + (size_t)y * (size_t)srcStride;
        uint8_t *dRow = dst + (size_t)y * (size_t)dstStride;
        uint32_t gy = (uint32_t)(y + originY) * 0x85ebca77u;
        for (int32_t x = 0; x < width; x++) {
            const uint8_t *sp = sRow + x * 4;
            uint8_t sa = sp[3];
            if (sa == 0) continue;
            uint8_t *dp = dRow + x * 4;
            if (sa == 255) {
                dp[0] = sp[0]; dp[1] = sp[1]; dp[2] = sp[2]; dp[3] = 255;
                continue;
            }
            uint32_t h = mix32(((uint32_t)(x + originX) * 0x9e3779b1u) ^ gy);
            float threshold = (float)(h >> 8) / 16777216.0f;
            if (threshold < (float)sa / 255.0f) {
                float invA = 255.0f / (float)sa;
                dp[0] = clamp_u8((float)sp[0] * invA);
                dp[1] = clamp_u8((float)sp[1] * invA);
                dp[2] = clamp_u8((float)sp[2] * invA);
                dp[3] = 255;
            }
        }
    }
}

static void blend_luma_color(const uint8_t *src, int32_t srcStride,
                             uint8_t *dst, int32_t dstStride,
                             int32_t width, int32_t height,
                             int pickLighter) {
    if (!src || !dst || width <= 0 || height <= 0) return;
    for (int32_t y = 0; y < height; y++) {
        const uint8_t *sRow = src + (size_t)y * (size_t)srcStride;
        uint8_t *dRow = dst + (size_t)y * (size_t)dstStride;
        for (int32_t x = 0; x < width; x++) {
            const uint8_t *sp = sRow + x * 4;
            uint8_t sa8 = sp[3];
            if (sa8 == 0) continue;
            uint8_t *dp = dRow + x * 4;
            uint8_t da8 = dp[3];
            if (da8 == 0) {
                dp[0] = sp[0]; dp[1] = sp[1]; dp[2] = sp[2]; dp[3] = sa8;
                continue;
            }
            float sa = (float)sa8 / 255.0f;
            float da = (float)da8 / 255.0f;
            float invSa = 1.0f / sa;
            float invDa = 1.0f / da;
            float spR = (float)sp[0] / 255.0f, spG = (float)sp[1] / 255.0f, spB = (float)sp[2] / 255.0f;
            float dpR = (float)dp[0] / 255.0f, dpG = (float)dp[1] / 255.0f, dpB = (float)dp[2] / 255.0f;
            float csR = fminf(1.0f, spR * invSa), csG = fminf(1.0f, spG * invSa), csB = fminf(1.0f, spB * invSa);
            float cbR = fminf(1.0f, dpR * invDa), cbG = fminf(1.0f, dpG * invDa), cbB = fminf(1.0f, dpB * invDa);
            float ls = 0.299f * csR + 0.587f * csG + 0.114f * csB;
            float lb = 0.299f * cbR + 0.587f * cbG + 0.114f * cbB;
            int useSrc = pickLighter ? (ls > lb) : (ls < lb);
            float bR = useSrc ? csR : cbR;
            float bG = useSrc ? csG : cbG;
            float bB = useSrc ? csB : cbB;
            float sda = sa * da;
            float oneMinusDa = 1.0f - da;
            float oneMinusSa = 1.0f - sa;
            float outR = spR * oneMinusDa + dpR * oneMinusSa + sda * bR;
            float outG = spG * oneMinusDa + dpG * oneMinusSa + sda * bG;
            float outB = spB * oneMinusDa + dpB * oneMinusSa + sda * bB;
            float outA = sa + da * oneMinusSa;
            dp[0] = clamp_u8(outR * 255.0f);
            dp[1] = clamp_u8(outG * 255.0f);
            dp[2] = clamp_u8(outB * 255.0f);
            dp[3] = clamp_u8(outA * 255.0f);
        }
    }
}

void blend_darker_color(const uint8_t *src, int32_t srcStride,
                        uint8_t *dst, int32_t dstStride,
                        int32_t width, int32_t height) {
    blend_luma_color(src, srcStride, dst, dstStride, width, height, 0);
}

void blend_lighter_color(const uint8_t *src, int32_t srcStride,
                         uint8_t *dst, int32_t dstStride,
                         int32_t width, int32_t height) {
    blend_luma_color(src, srcStride, dst, dstStride, width, height, 1);
}
