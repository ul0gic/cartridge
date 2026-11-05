#ifndef CoreHostC_h
#define CoreHostC_h

#import "Libretro/libretro.h"
#import "Audio/AudioRing.h"
#import "../Shared/CaptureAudioTap.h"
#import "Rewind/StateDelta.h"

#pragma clang assume_nonnull begin

typedef void (*cartridge_log_sink_t)(enum retro_log_level level, const char *message);

void cartridge_set_log_sink(cartridge_log_sink_t sink);
void cartridge_log_callback(enum retro_log_level level, const char *fmt, ...);
void cartridge_fill_log_callback(struct retro_log_callback *callback);

void cartridge_call_void(void (*fn)(void));
bool cartridge_call_load_game(bool (*fn)(const struct retro_game_info *), const struct retro_game_info *game);
void cartridge_call_get_system_info(void (*fn)(struct retro_system_info *), struct retro_system_info *info);
void cartridge_call_get_system_av_info(void (*fn)(struct retro_system_av_info *), struct retro_system_av_info *info);
void cartridge_call_set_controller_port_device(void (*fn)(unsigned, unsigned), unsigned port, unsigned device);
size_t cartridge_call_serialize_size(size_t (*fn)(void));
bool cartridge_call_serialize(bool (*fn)(void *, size_t), void *data, size_t size);
bool cartridge_call_unserialize(bool (*fn)(const void *, size_t), const void *data, size_t size);
void *_Nullable cartridge_call_get_memory_data(void *_Nullable (*_Nonnull fn)(unsigned), unsigned id);
size_t cartridge_call_get_memory_size(size_t (*fn)(unsigned), unsigned id);
bool cartridge_call_set_eject_state(retro_set_eject_state_t fn, bool ejected);
bool cartridge_call_set_image_index(retro_set_image_index_t fn, unsigned index);
unsigned cartridge_call_get_num_images(retro_get_num_images_t fn);
void cartridge_call_cheat_set(void (*fn)(unsigned, bool, const char *), unsigned index, bool enabled, const char *code);

void cartridge_convert_xrgb8888(uint8_t *destination, size_t destinationPitch, const uint8_t *source, size_t sourcePitch, uint32_t width, uint32_t height);
void cartridge_convert_rgb565(uint8_t *destination, size_t destinationPitch, const uint8_t *source, size_t sourcePitch, uint32_t width, uint32_t height);
void cartridge_convert_0rgb1555(uint8_t *destination, size_t destinationPitch, const uint8_t *source, size_t sourcePitch, uint32_t width, uint32_t height);

#pragma clang assume_nonnull end

#endif
