#ifndef BLEND_PIXELS_H
#define BLEND_PIXELS_H

#include <stdint.h>

typedef struct {
    int32_t channel;       // 0 = Gray, 1 = Red, 2 = Green, 3 = Blue
    int32_t thisBlackLow;
    int32_t thisBlackHigh;
    int32_t thisWhiteLow;
    int32_t thisWhiteHigh;
    int32_t underBlackLow;
    int32_t underBlackHigh;
    int32_t underWhiteLow;
    int32_t underWhiteHigh;
} BlendIfParams;

/// Modulates premultiplied RGBA8 `src` in-place using Photoshop-style Blend If ranges evaluated against
/// `src` (This Layer) and `dst` (Underlying Layer). Both buffers have dimensions `width` x `height`.
void blend_apply_blend_if(uint8_t *src, int32_t srcStride,
                          const uint8_t *dst, int32_t dstStride,
                          int32_t width, int32_t height,
                          BlendIfParams params);

/// Composites premultiplied RGBA8 `src` over `dst` in-place using Photoshop's Dissolve mode.
/// `originX`/`originY` anchor the deterministic noise pattern in document space.
void blend_dissolve(const uint8_t *src, int32_t srcStride,
                    uint8_t *dst, int32_t dstStride,
                    int32_t width, int32_t height,
                    int32_t originX, int32_t originY);

/// Composites premultiplied RGBA8 `src` over `dst` in-place using Photoshop's Darker Color mode.
void blend_darker_color(const uint8_t *src, int32_t srcStride,
                        uint8_t *dst, int32_t dstStride,
                        int32_t width, int32_t height);

/// Composites premultiplied RGBA8 `src` over `dst` in-place using Photoshop's Lighter Color mode.
void blend_lighter_color(const uint8_t *src, int32_t srcStride,
                         uint8_t *dst, int32_t dstStride,
                         int32_t width, int32_t height);

#endif /* BLEND_PIXELS_H */
