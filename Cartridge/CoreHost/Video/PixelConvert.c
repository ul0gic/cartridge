#include "../CoreHostC.h"

#include <string.h>

void cartridge_convert_xrgb8888(uint8_t *destination, size_t destinationPitch, const uint8_t *source, size_t sourcePitch, uint32_t width, uint32_t height)
{
    for (uint32_t y = 0; y < height; y++) {
        memcpy(destination + y * destinationPitch, source + y * sourcePitch, (size_t)width * 4);
    }
}

void cartridge_convert_rgb565(uint8_t *destination, size_t destinationPitch, const uint8_t *source, size_t sourcePitch, uint32_t width, uint32_t height)
{
    for (uint32_t y = 0; y < height; y++) {
        const uint16_t *in = (const uint16_t *)(source + y * sourcePitch);
        uint32_t *out = (uint32_t *)(destination + y * destinationPitch);
        for (uint32_t x = 0; x < width; x++) {
            uint32_t pixel = in[x];
            uint32_t red = (pixel >> 11) & 0x1F;
            uint32_t green = (pixel >> 5) & 0x3F;
            uint32_t blue = pixel & 0x1F;
            red = (red << 3) | (red >> 2);
            green = (green << 2) | (green >> 4);
            blue = (blue << 3) | (blue >> 2);
            out[x] = (red << 16) | (green << 8) | blue;
        }
    }
}

void cartridge_convert_0rgb1555(uint8_t *destination, size_t destinationPitch, const uint8_t *source, size_t sourcePitch, uint32_t width, uint32_t height)
{
    for (uint32_t y = 0; y < height; y++) {
        const uint16_t *in = (const uint16_t *)(source + y * sourcePitch);
        uint32_t *out = (uint32_t *)(destination + y * destinationPitch);
        for (uint32_t x = 0; x < width; x++) {
            uint32_t pixel = in[x];
            uint32_t red = (pixel >> 10) & 0x1F;
            uint32_t green = (pixel >> 5) & 0x1F;
            uint32_t blue = pixel & 0x1F;
            red = (red << 3) | (red >> 2);
            green = (green << 3) | (green >> 2);
            blue = (blue << 3) | (blue >> 2);
            out[x] = (red << 16) | (green << 8) | blue;
        }
    }
}
