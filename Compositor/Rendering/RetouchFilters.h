#ifndef RetouchFilters_h
#define RetouchFilters_h

#include <stddef.h>
#include <stdint.h>

void adjust_brightness_contrast(uint8_t *rgba, size_t width, size_t height, size_t stride,
                                float brightness, float contrast, int32_t legacy);

void adjust_vibrance(uint8_t *rgba, size_t width, size_t height, size_t stride,
                     float vibrance, float saturation);

void adjust_threshold(uint8_t *rgba, size_t width, size_t height, size_t stride,
                      int32_t level);

void adjust_posterize(uint8_t *rgba, size_t width, size_t height, size_t stride,
                      int32_t levels);

// adjustments is 9 * 4 floats: for each of the 9 families (R, Y, G, C, B, M, W, N, K),
// four CMYK deltas in -1...1 (cyan, magenta, yellow, black).
void adjust_selective_color(uint8_t *rgba, size_t width, size_t height, size_t stride,
                            const float *adjustments, int32_t relative);

// cube holds dim * dim * dim * 3 floats in R-fastest, G-middle, B-slowest order (0...1).
void adjust_color_lut(uint8_t *rgba, size_t width, size_t height, size_t stride,
                      const float *cube, int32_t dim, float intensity);

void filter_high_pass(uint8_t *rgba, const uint8_t *blurred, size_t width, size_t height,
                      size_t stride, size_t blurred_stride);

// edge_mode: 0 = wrap around, 1 = repeat edge pixels, 2 = transparent
void filter_offset(const uint8_t *src, uint8_t *dst, size_t width, size_t height,
                   size_t src_stride, size_t dst_stride, int32_t dx, int32_t dy, int32_t edge_mode);

#endif
