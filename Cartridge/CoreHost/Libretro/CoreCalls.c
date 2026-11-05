#include "../CoreHostC.h"

#define CARTRIDGE_RESTORE_FP_REGISTERS() \
    __asm__ volatile("" ::: "d8", "d9", "d10", "d11", "d12", "d13", "d14", "d15")

void cartridge_call_void(void (*fn)(void))
{
    fn();
    CARTRIDGE_RESTORE_FP_REGISTERS();
}

bool cartridge_call_load_game(bool (*fn)(const struct retro_game_info *), const struct retro_game_info *game)
{
    bool result = fn(game);
    CARTRIDGE_RESTORE_FP_REGISTERS();
    return result;
}

void cartridge_call_get_system_info(void (*fn)(struct retro_system_info *), struct retro_system_info *info)
{
    fn(info);
    CARTRIDGE_RESTORE_FP_REGISTERS();
}

void cartridge_call_get_system_av_info(void (*fn)(struct retro_system_av_info *), struct retro_system_av_info *info)
{
    fn(info);
    CARTRIDGE_RESTORE_FP_REGISTERS();
}

void cartridge_call_set_controller_port_device(void (*fn)(unsigned, unsigned), unsigned port, unsigned device)
{
    fn(port, device);
    CARTRIDGE_RESTORE_FP_REGISTERS();
}

size_t cartridge_call_serialize_size(size_t (*fn)(void))
{
    size_t result = fn();
    CARTRIDGE_RESTORE_FP_REGISTERS();
    return result;
}

bool cartridge_call_serialize(bool (*fn)(void *, size_t), void *data, size_t size)
{
    bool result = fn(data, size);
    CARTRIDGE_RESTORE_FP_REGISTERS();
    return result;
}

bool cartridge_call_unserialize(bool (*fn)(const void *, size_t), const void *data, size_t size)
{
    bool result = fn(data, size);
    CARTRIDGE_RESTORE_FP_REGISTERS();
    return result;
}

void *cartridge_call_get_memory_data(void *(*fn)(unsigned), unsigned id)
{
    void *result = fn(id);
    CARTRIDGE_RESTORE_FP_REGISTERS();
    return result;
}

size_t cartridge_call_get_memory_size(size_t (*fn)(unsigned), unsigned id)
{
    size_t result = fn(id);
    CARTRIDGE_RESTORE_FP_REGISTERS();
    return result;
}

bool cartridge_call_set_eject_state(retro_set_eject_state_t fn, bool ejected)
{
    bool result = fn(ejected);
    CARTRIDGE_RESTORE_FP_REGISTERS();
    return result;
}

bool cartridge_call_set_image_index(retro_set_image_index_t fn, unsigned index)
{
    bool result = fn(index);
    CARTRIDGE_RESTORE_FP_REGISTERS();
    return result;
}

void cartridge_call_cheat_set(void (*fn)(unsigned, bool, const char *), unsigned index, bool enabled, const char *code)
{
    fn(index, enabled, code);
    CARTRIDGE_RESTORE_FP_REGISTERS();
}

unsigned cartridge_call_get_num_images(retro_get_num_images_t fn)
{
    unsigned result = fn();
    CARTRIDGE_RESTORE_FP_REGISTERS();
    return result;
}
