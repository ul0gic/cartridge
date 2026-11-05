/* Changed by ul0gic for Cartridge on 2026-11-01. */
#ifndef CARTRIDGE_HOST_H
#define CARTRIDGE_HOST_H

#include <stdbool.h>
#include <stdint.h>

#include "cartridge_xemu.h"

#ifdef __cplusplus
extern "C" {
#endif

void cartridge_host_log(CartridgeXemuLogLevel level, const char *format, ...)
    __attribute__((format(printf, 2, 3)));
void cartridge_host_frame_ready(uint32_t surface_index, uint32_t width,
                                uint32_t height);
void cartridge_host_read_pad(CartridgeXemuPad *pad);
void cartridge_host_audio(const int16_t *frames, uint32_t frame_count);
void cartridge_host_audio_underrun(void);
void cartridge_host_guest_stopped(void);

IOSurfaceRef cartridge_host_surface(uint32_t index);

typedef void (*CartridgeDisplayTask)(void *opaque);

CartridgeXemuStatus cartridge_display_start(int argc, char **argv);
bool cartridge_display_run(CartridgeDisplayTask task, void *opaque);
void cartridge_display_stop(void);

void cartridge_input_init(void);

#ifdef __cplusplus
}
#endif

#endif
