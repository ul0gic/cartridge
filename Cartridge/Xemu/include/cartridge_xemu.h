#ifndef cartridge_xemu_h
#define cartridge_xemu_h

#include <IOSurface/IOSurfaceRef.h>
#include <stdbool.h>
#include <stdint.h>

#define CARTRIDGE_XEMU_ABI_VERSION 1u

#define CARTRIDGE_XEMU_PAD_DPAD_UP 0x0001
#define CARTRIDGE_XEMU_PAD_DPAD_DOWN 0x0002
#define CARTRIDGE_XEMU_PAD_DPAD_LEFT 0x0004
#define CARTRIDGE_XEMU_PAD_DPAD_RIGHT 0x0008
#define CARTRIDGE_XEMU_PAD_START 0x0010
#define CARTRIDGE_XEMU_PAD_BACK 0x0020
#define CARTRIDGE_XEMU_PAD_LEFT_THUMB 0x0040
#define CARTRIDGE_XEMU_PAD_RIGHT_THUMB 0x0080

typedef enum CartridgeXemuStatus {
    CARTRIDGE_XEMU_OK = 0,
    CARTRIDGE_XEMU_BAD_ARGUMENT = 1,
    CARTRIDGE_XEMU_ALREADY_STARTED = 2,
    CARTRIDGE_XEMU_NOT_STARTED = 3,
    CARTRIDGE_XEMU_FIRMWARE_UNREADABLE = 4,
    CARTRIDGE_XEMU_DISC_UNREADABLE = 5,
    CARTRIDGE_XEMU_DRIVE_FAILED = 6,
    CARTRIDGE_XEMU_DISK_FULL = 7,
    CARTRIDGE_XEMU_GL_FAILED = 8,
    CARTRIDGE_XEMU_AUDIO_FAILED = 9,
    CARTRIDGE_XEMU_INIT_FAILED = 10,
    CARTRIDGE_XEMU_SNAPSHOT_FAILED = 11,
    CARTRIDGE_XEMU_SNAPSHOT_NOT_FOUND = 12
} CartridgeXemuStatus;

typedef enum CartridgeXemuLogLevel {
    CARTRIDGE_XEMU_LOG_DEBUG = 0,
    CARTRIDGE_XEMU_LOG_INFO = 1,
    CARTRIDGE_XEMU_LOG_WARN = 2,
    CARTRIDGE_XEMU_LOG_ERROR = 3
} CartridgeXemuLogLevel;

typedef struct CartridgeXemuPad {
    uint16_t buttons;
    uint8_t a, b, x, y, black, white;
    uint8_t left_trigger, right_trigger;
    int16_t left_x, left_y, right_x, right_y;
} CartridgeXemuPad;

typedef struct CartridgeXemuConfig {
    const char *bootrom_path;
    const char *flash_path;
    const char *eeprom_path;
    const char *hdd_path;
    const char *dvd_path;
    const char *config_directory;
    uint64_t dvd_offset;
    uint32_t render_scale;
    bool start_stopped;
    IOSurfaceRef surfaces[2];
} CartridgeXemuConfig;

// A callback never blocks, calls no ABI function but cartridge_xemu_guest_frames, and returns within 1 ms.
typedef struct CartridgeXemuHost {
    void *context;
    // Display thread.
    void (*frame_ready)(void *context, uint32_t surface_index, uint32_t width, uint32_t height);
    // QEMU thread at each XID poll, with the big lock held.
    void (*read_pad)(void *context, CartridgeXemuPad *pad);
    // APU thread.
    void (*audio)(void *context, const int16_t *frames, uint32_t frame_count);
    // APU thread.
    void (*audio_underrun)(void *context);
    // Any thread.
    void (*log)(void *context, CartridgeXemuLogLevel level, const char *message);
    // Once, on the QEMU thread, only when the guest halts or powers off; never for cartridge_xemu_stop.
    void (*guest_stopped)(void *context);
} CartridgeXemuHost;

extern uint32_t cartridge_xemu_abi_version(void);
extern CartridgeXemuStatus cartridge_xemu_prepare_eeprom(const char *path);
extern CartridgeXemuStatus cartridge_xemu_format_base_drive(const char *path);
extern CartridgeXemuStatus cartridge_xemu_create_game_drive(const char *path, const char *base_path);
extern CartridgeXemuStatus cartridge_xemu_start(const CartridgeXemuConfig *config, const CartridgeXemuHost *host);
extern CartridgeXemuStatus cartridge_xemu_set_running(bool running);
extern CartridgeXemuStatus cartridge_xemu_reset(void);
extern CartridgeXemuStatus cartridge_xemu_save_snapshot(const char *tag);
extern CartridgeXemuStatus cartridge_xemu_load_snapshot(const char *tag);
extern CartridgeXemuStatus cartridge_xemu_delete_snapshot(const char *tag);
extern CartridgeXemuStatus cartridge_xemu_list_snapshots(void (*each)(void *context, const char *tag), void *context);
extern uint64_t cartridge_xemu_guest_frames(void);
// No ABI call is valid after this returns.
extern void cartridge_xemu_stop(void);

#endif
