#ifndef TonePixels_h
#define TonePixels_h

#include <stddef.h>
#include <stdint.h>

// Mode constants for tone_adjust_rgba:
// 0 = Dodge (lighten), 1 = Burn (darken), 2 = Sponge Saturate, 3 = Sponge Desaturate.
// Range constants (used by Dodge/Burn): 0 = Shadows, 1 = Midtones, 2 = Highlights.
void tone_adjust_rgba(uint8_t *rgba, size_t width, size_t height, size_t stride,
                      int32_t mode, int32_t range, float strength, int32_t protect_tones);

#endif
