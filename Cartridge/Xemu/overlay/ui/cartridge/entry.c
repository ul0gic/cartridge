/* Changed by ul0gic for Cartridge on 2026-11-01. */
#include "qemu/osdep.h"
#include "qapi/error.h"
#include "block/snapshot.h"
#include "migration/snapshot.h"
#include "system/runstate.h"
#include "hw/boards.h"
#include "ui/xemu-settings.h"
#include "ui/xui/xemu-hud.h"
#include "hw/xbox/nv2a/debug.h"

#include <sys/statvfs.h>

#include "cartridge-host.h"

// IOSurface pixel format 'BGRA'.
#define SURFACE_PIXEL_FORMAT 0x42475241
#define SURFACE_MIN_WIDTH 1440
#define SURFACE_MIN_HEIGHT 960

static CartridgeXemuHost host;
static bool host_ready;
static bool started;
static bool finished;
static IOSurfaceRef surfaces[2];

void cartridge_host_log(CartridgeXemuLogLevel level, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    g_autofree char *message = g_strdup_vprintf(format, args);
    va_end(args);

    if (qatomic_read(&host_ready)) {
        host.log(host.context, level, message);
    } else {
        fprintf(stderr, "cartridge: %s\n", message);
    }
}

void cartridge_host_frame_ready(uint32_t surface_index, uint32_t width,
                                uint32_t height)
{
    host.frame_ready(host.context, surface_index, width, height);
}

void cartridge_host_read_pad(CartridgeXemuPad *pad)
{
    host.read_pad(host.context, pad);
}

void cartridge_host_audio(const int16_t *frames, uint32_t frame_count)
{
    host.audio(host.context, frames, frame_count);
}

void cartridge_host_audio_underrun(void)
{
    host.audio_underrun(host.context);
}

void cartridge_host_guest_stopped(void)
{
    host.guest_stopped(host.context);
}

IOSurfaceRef cartridge_host_surface(uint32_t index)
{
    return surfaces[index];
}

uint32_t cartridge_xemu_abi_version(void)
{
    return CARTRIDGE_XEMU_ABI_VERSION;
}

static void toml_string(GString *out, const char *key, const char *value)
{
    g_string_append_printf(out, "%s = \"", key);
    for (const char *p = value; *p; p++) {
        unsigned char c = (unsigned char)*p;
        if (c == '"' || c == '\\') {
            g_string_append_c(out, '\\');
            g_string_append_c(out, (char)c);
        } else if (c < 0x20 || c == 0x7f) {
            g_string_append_printf(out, "\\u%04x", c);
        } else {
            g_string_append_c(out, (char)c);
        }
    }
    g_string_append(out, "\"\n");
}

static bool write_settings(const CartridgeXemuConfig *config, const char *path)
{
    g_autoptr(GString) toml = g_string_new(NULL);

    g_string_append(toml, "[general]\n"
                          "show_welcome = false\n"
                          "skip_boot_anim = true\n\n");
    g_string_append(toml, "[input.bindings]\n"
                          "port1_driver = \"usb-xbox-gamepad-s\"\n\n");
    g_string_append_printf(toml, "[display.quality]\n"
                                 "surface_scale = %u\n"
                                 "depth_precision = \"fast\"\n\n",
                           config->render_scale);
    g_string_append(toml, "[display.ui]\n"
                          "show_notifications = false\n"
                          "show_menubar = false\n\n");
    g_string_append(toml, "[sys]\n"
                          "mem_limit = \"64\"\n"
                          "avpack = \"hdtv\"\n\n");
    g_string_append(toml, "[sys.files]\n");
    toml_string(toml, "bootrom_path", config->bootrom_path);
    toml_string(toml, "flashrom_path", config->flash_path);
    toml_string(toml, "eeprom_path", config->eeprom_path);
    toml_string(toml, "hdd_path", config->hdd_path);
    toml_string(toml, "dvd_path", config->dvd_path);

    g_autoptr(GError) err = NULL;
    if (!g_file_set_contents(path, toml->str, (gssize)toml->len, &err)) {
        cartridge_host_log(CARTRIDGE_XEMU_LOG_ERROR, "could not write %s: %s",
                           path, err->message);
        return false;
    }
    return true;
}

static bool is_absolute(const char *path)
{
    return path != NULL && path[0] == '/';
}

static bool surface_usable(IOSurfaceRef surface)
{
    return surface != NULL &&
           IOSurfaceGetPixelFormat(surface) == SURFACE_PIXEL_FORMAT &&
           IOSurfaceGetWidth(surface) >= SURFACE_MIN_WIDTH &&
           IOSurfaceGetHeight(surface) >= SURFACE_MIN_HEIGHT;
}

static CartridgeXemuStatus check_access(const char *path, int mode,
                                        CartridgeXemuStatus failure)
{
    if (access(path, mode) != 0) {
        cartridge_host_log(CARTRIDGE_XEMU_LOG_ERROR, "%s: %s", path,
                           strerror(errno));
        return failure;
    }
    return CARTRIDGE_XEMU_OK;
}

CartridgeXemuStatus cartridge_xemu_start(const CartridgeXemuConfig *config,
                                         const CartridgeXemuHost *callbacks)
{
    if (started || finished) {
        return CARTRIDGE_XEMU_ALREADY_STARTED;
    }
    if (config == NULL || callbacks == NULL || callbacks->frame_ready == NULL ||
        callbacks->read_pad == NULL || callbacks->audio == NULL ||
        callbacks->audio_underrun == NULL || callbacks->log == NULL ||
        callbacks->guest_stopped == NULL) {
        return CARTRIDGE_XEMU_BAD_ARGUMENT;
    }
    if (!is_absolute(config->bootrom_path) || !is_absolute(config->flash_path) ||
        !is_absolute(config->eeprom_path) || !is_absolute(config->hdd_path) ||
        !is_absolute(config->config_directory) || config->dvd_path == NULL ||
        (config->dvd_path[0] != '\0' && !is_absolute(config->dvd_path)) ||
        (config->render_scale != 1 && config->render_scale != 2) ||
        !surface_usable(config->surfaces[0]) ||
        !surface_usable(config->surfaces[1])) {
        return CARTRIDGE_XEMU_BAD_ARGUMENT;
    }

    host = *callbacks;
    qatomic_set(&host_ready, true);

    CartridgeXemuStatus status =
        check_access(config->bootrom_path, R_OK,
                     CARTRIDGE_XEMU_FIRMWARE_UNREADABLE);
    if (status == CARTRIDGE_XEMU_OK) {
        status = check_access(config->flash_path, R_OK,
                              CARTRIDGE_XEMU_FIRMWARE_UNREADABLE);
    }
    if (status == CARTRIDGE_XEMU_OK && config->dvd_path[0] != '\0') {
        status = check_access(config->dvd_path, R_OK,
                              CARTRIDGE_XEMU_DISC_UNREADABLE);
    }
    if (status == CARTRIDGE_XEMU_OK) {
        status = check_access(config->hdd_path, R_OK | W_OK,
                              CARTRIDGE_XEMU_DRIVE_FAILED);
    }
    if (status == CARTRIDGE_XEMU_OK) {
        status = check_access(config->eeprom_path, R_OK | W_OK,
                              CARTRIDGE_XEMU_DRIVE_FAILED);
    }
    if (status != CARTRIDGE_XEMU_OK) {
        return status;
    }

    g_autofree char *settings_path =
        g_build_filename(config->config_directory, "xemu.toml", NULL);
    if (!write_settings(config, settings_path)) {
        return CARTRIDGE_XEMU_INIT_FAILED;
    }
    xemu_settings_set_path(settings_path);
    if (!xemu_settings_load()) {
        cartridge_host_log(CARTRIDGE_XEMU_LOG_ERROR, "%s",
                           xemu_settings_get_error_message());
        return CARTRIDGE_XEMU_INIT_FAILED;
    }

    surfaces[0] = (IOSurfaceRef)CFRetain(config->surfaces[0]);
    surfaces[1] = (IOSurfaceRef)CFRetain(config->surfaces[1]);

    GPtrArray *args = g_ptr_array_new();
    g_ptr_array_add(args, g_strdup("xemu"));
    if (config->start_stopped) {
        g_ptr_array_add(args, g_strdup("-S"));
    }
    g_ptr_array_add(args, g_strdup("-dvd_path"));
    g_ptr_array_add(args, g_strdup(config->dvd_path));
    if (config->dvd_offset > 0) {
        g_ptr_array_add(args, g_strdup("-dvd_offset"));
        g_ptr_array_add(args,
                        g_strdup_printf("%" PRIu64, config->dvd_offset));
    }
    int argc = (int)args->len;
    g_ptr_array_add(args, NULL);
    char **argv = (char **)g_ptr_array_free(args, false);

    status = cartridge_display_start(argc, argv);
    if (status != CARTRIDGE_XEMU_OK) {
        finished = true;
        CFRelease(surfaces[0]);
        CFRelease(surfaces[1]);
        return status;
    }
    started = true;
    return CARTRIDGE_XEMU_OK;
}

typedef struct Request {
    const char *tag;
    bool running;
    void (*each)(void *context, const char *tag);
    void *context;
    CartridgeXemuStatus status;
} Request;

static CartridgeXemuStatus run(CartridgeDisplayTask task, Request *request)
{
    if (!started) {
        return CARTRIDGE_XEMU_NOT_STARTED;
    }
    if (!cartridge_display_run(task, request)) {
        return CARTRIDGE_XEMU_NOT_STARTED;
    }
    return request->status;
}

static void log_error(const char *what, const char *tag, Error *err)
{
    cartridge_host_log(CARTRIDGE_XEMU_LOG_ERROR, "%s %s: %s", what, tag,
                       error_get_pretty(err));
    error_free(err);
}

static void set_running_task(void *opaque)
{
    Request *request = opaque;
    xemu_main_loop_lock();
    if (request->running) {
        vm_start();
    } else {
        vm_stop(RUN_STATE_PAUSED);
    }
    xemu_main_loop_unlock();
    request->status = CARTRIDGE_XEMU_OK;
}

CartridgeXemuStatus cartridge_xemu_set_running(bool running)
{
    Request request = { .running = running };
    return run(set_running_task, &request);
}

static void reset_task(void *opaque)
{
    Request *request = opaque;
    xemu_main_loop_lock();
    qemu_system_reset_request(SHUTDOWN_CAUSE_GUEST_RESET);
    xemu_main_loop_unlock();
    request->status = CARTRIDGE_XEMU_OK;
}

CartridgeXemuStatus cartridge_xemu_reset(void)
{
    Request request = { 0 };
    return run(reset_task, &request);
}

static bool drive_lacks_room_for_snapshot(void)
{
    struct statvfs fs;
    if (statvfs(g_config.sys.files.hdd_path, &fs) != 0) {
        return false;
    }
    return (uint64_t)fs.f_bavail * fs.f_frsize < current_machine->ram_size;
}

static void save_task(void *opaque)
{
    Request *request = opaque;
    Error *err = NULL;
    xemu_main_loop_lock();
    bool saved = save_snapshot(request->tag, true, NULL, false, NULL, &err);
    xemu_main_loop_unlock();
    if (saved) {
        request->status = CARTRIDGE_XEMU_OK;
        return;
    }
    request->status = drive_lacks_room_for_snapshot()
                          ? CARTRIDGE_XEMU_DISK_FULL
                          : CARTRIDGE_XEMU_SNAPSHOT_FAILED;
    log_error("save snapshot", request->tag, err);
}

CartridgeXemuStatus cartridge_xemu_save_snapshot(const char *tag)
{
    if (started && (tag == NULL || tag[0] == '\0')) {
        return CARTRIDGE_XEMU_BAD_ARGUMENT;
    }
    Request request = { .tag = tag };
    return run(save_task, &request);
}

static CartridgeXemuStatus find_snapshot(const char *tag)
{
    Error *err = NULL;
    int found = bdrv_all_has_snapshot(tag, false, NULL, &err);
    if (found < 0) {
        log_error("find snapshot", tag, err);
        return CARTRIDGE_XEMU_SNAPSHOT_FAILED;
    }
    return found ? CARTRIDGE_XEMU_OK : CARTRIDGE_XEMU_SNAPSHOT_NOT_FOUND;
}

static void load_task(void *opaque)
{
    Request *request = opaque;
    Error *err = NULL;
    xemu_main_loop_lock();
    request->status = find_snapshot(request->tag);
    if (request->status == CARTRIDGE_XEMU_OK) {
        vm_stop(RUN_STATE_RESTORE_VM);
        if (load_snapshot(request->tag, NULL, false, NULL, &err)) {
            vm_start();
        } else {
            request->status = CARTRIDGE_XEMU_SNAPSHOT_FAILED;
        }
    }
    xemu_main_loop_unlock();
    if (err) {
        log_error("load snapshot", request->tag, err);
    }
}

CartridgeXemuStatus cartridge_xemu_load_snapshot(const char *tag)
{
    Request request = { .tag = tag };
    return run(load_task, &request);
}

static void delete_task(void *opaque)
{
    Request *request = opaque;
    Error *err = NULL;
    xemu_main_loop_lock();
    request->status = find_snapshot(request->tag);
    if (request->status == CARTRIDGE_XEMU_OK &&
        !delete_snapshot(request->tag, false, NULL, &err)) {
        request->status = CARTRIDGE_XEMU_SNAPSHOT_FAILED;
    }
    xemu_main_loop_unlock();
    if (err) {
        log_error("delete snapshot", request->tag, err);
    }
}

CartridgeXemuStatus cartridge_xemu_delete_snapshot(const char *tag)
{
    Request request = { .tag = tag };
    return run(delete_task, &request);
}

static void list_task(void *opaque)
{
    Request *request = opaque;
    Error *err = NULL;
    QEMUSnapshotInfo *snapshots = NULL;
    int count = -1;

    xemu_main_loop_lock();
    BlockDriverState *bs = bdrv_all_find_vmstate_bs(NULL, false, NULL, &err);
    if (bs) {
        count = bdrv_snapshot_list(bs, &snapshots);
    }
    xemu_main_loop_unlock();

    if (count < 0) {
        request->status = CARTRIDGE_XEMU_SNAPSHOT_FAILED;
        if (err) {
            log_error("list snapshots", "", err);
        }
        return;
    }
    for (int i = 0; i < count; i++) {
        request->each(request->context, snapshots[i].name);
    }
    g_free(snapshots);
    request->status = CARTRIDGE_XEMU_OK;
}

CartridgeXemuStatus cartridge_xemu_list_snapshots(
    void (*each)(void *context, const char *tag), void *context)
{
    Request request = { .each = each, .context = context };
    return run(list_task, &request);
}

uint64_t cartridge_xemu_guest_frames(void)
{
    return qatomic_read(&g_nv2a_stats.frame_count);
}

void cartridge_xemu_stop(void)
{
    if (!started) {
        return;
    }
    cartridge_display_stop();
    started = false;
    finished = true;
    CFRelease(surfaces[0]);
    CFRelease(surfaces[1]);
}
