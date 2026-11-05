/* Changed by ul0gic for Cartridge on 2026-11-01. */
#include "qemu/osdep.h"
#include "qemu/bswap.h"
#include "qapi/error.h"
#include "crypto/init.h"
#include "hw/xbox/eeprom_generation.h"

#include "libfatx/fatx.h"
#include "cartridge_xemu.h"

#define BASE_DRIVE_SIZE 0x1DDD80000ULL

#define EEPROM_SIZE 256
#define EEPROM_USER_CHECKSUM 0x60
#define EEPROM_USER_SECTION 0x64
#define EEPROM_USER_SECTION_CHECKSUMMED 0x5C
#define EEPROM_VIDEO_FLAGS 0x94
#define EEPROM_VIDEO_480P 0x00080000

/* docs/interop/qcow2.rst field offsets and values */
#define QCOW2_MAGIC 0x514649fbU
#define QCOW2_VERSION 3
#define QCOW2_CLUSTER_BITS 16
#define QCOW2_CLUSTER_SIZE (1ULL << QCOW2_CLUSTER_BITS)
#define QCOW2_REFCOUNT_ORDER 4
#define QCOW2_HEADER_LENGTH 112
#define QCOW2_EXT_BACKING_FORMAT 0xe2792acaU
#define QCOW2_BACKING_NAME_MAX 1023
#define QCOW2_REFCOUNT_TABLE_CLUSTER 1
#define QCOW2_REFCOUNT_BLOCK_CLUSTER 2
#define QCOW2_L1_CLUSTER 3
#define QCOW2_CLUSTERS 4

static CartridgeXemuStatus status_for_errno(int err)
{
    return (err == ENOSPC || err == EDQUOT) ? CARTRIDGE_XEMU_DISK_FULL
                                            : CARTRIDGE_XEMU_DRIVE_FAILED;
}

static bool path_is_absolute(const char *path)
{
    return path != NULL && path[0] == '/';
}

static bool path_is_free(const char *path, CartridgeXemuStatus *status)
{
    struct stat st;
    if (lstat(path, &st) == 0) {
        fprintf(stderr, "cartridge: %s already exists\n", path);
        *status = CARTRIDGE_XEMU_BAD_ARGUMENT;
        return false;
    }
    if (errno != ENOENT) {
        fprintf(stderr, "cartridge: lstat %s: %s\n", path, strerror(errno));
        *status = CARTRIDGE_XEMU_DRIVE_FAILED;
        return false;
    }
    return true;
}

static CartridgeXemuStatus write_all(int fd, const uint8_t *buf, size_t len)
{
    while (len > 0) {
        ssize_t written = write(fd, buf, len);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            return status_for_errno(errno);
        }
        buf += written;
        len -= (size_t)written;
    }
    return CARTRIDGE_XEMU_OK;
}

static CartridgeXemuStatus sync_and_rename(const char *partial,
                                           const char *path)
{
    int fd = open(partial, O_RDONLY);
    if (fd < 0) {
        return status_for_errno(errno);
    }
    int sync_errno = fsync(fd) == 0 ? 0 : errno;
    close(fd);
    if (sync_errno != 0) {
        return status_for_errno(sync_errno);
    }
    if (rename(partial, path) != 0) {
        return status_for_errno(errno);
    }
    return CARTRIDGE_XEMU_OK;
}

static CartridgeXemuStatus write_file(const char *partial, const uint8_t *buf,
                                      size_t len)
{
    int fd = open(partial, O_WRONLY | O_CREAT | O_EXCL, 0644);
    if (fd < 0) {
        return status_for_errno(errno);
    }
    CartridgeXemuStatus status = write_all(fd, buf, len);
    close(fd);
    return status;
}

static void finish(const char *what, const char *path, const char *partial,
                   CartridgeXemuStatus status)
{
    if (status != CARTRIDGE_XEMU_OK) {
        fprintf(stderr, "cartridge: %s %s failed (status %d)\n", what, path,
                     status);
        unlink(partial);
    }
}

CartridgeXemuStatus cartridge_xemu_prepare_eeprom(const char *path)
{
    static bool crypto_ready;

    if (!path_is_absolute(path)) {
        return CARTRIDGE_XEMU_BAD_ARGUMENT;
    }
    if (access(path, F_OK) == 0) {
        return CARTRIDGE_XEMU_OK;
    }

    if (!crypto_ready) {
        Error *err = NULL;
        if (qcrypto_init(&err) < 0) {
            fprintf(stderr, "cartridge: %s\n", error_get_pretty(err));
            error_free(err);
            return CARTRIDGE_XEMU_DRIVE_FAILED;
        }
        crypto_ready = true;
    }

    g_autofree char *partial = g_strdup_printf("%s.partial", path);
    unlink(partial);

    CartridgeXemuStatus status = CARTRIDGE_XEMU_OK;
    uint8_t eeprom[EEPROM_SIZE];
    if (!xbox_eeprom_generate(partial, XBOX_EEPROM_VERSION_R1)) {
        status = status_for_errno(errno);
    } else {
        FILE *f = fopen(partial, "rb");
        if (f == NULL) {
            status = status_for_errno(errno);
        } else {
            if (fread(eeprom, 1, sizeof(eeprom), f) != sizeof(eeprom)) {
                status = CARTRIDGE_XEMU_DRIVE_FAILED;
            }
            fclose(f);
        }
        unlink(partial);
    }

    if (status == CARTRIDGE_XEMU_OK) {
        stl_le_p(eeprom + EEPROM_VIDEO_FLAGS,
                 ldl_le_p(eeprom + EEPROM_VIDEO_FLAGS) | EEPROM_VIDEO_480P);
        stl_le_p(eeprom + EEPROM_USER_CHECKSUM,
                 xbox_eeprom_crc(eeprom + EEPROM_USER_SECTION,
                                 EEPROM_USER_SECTION_CHECKSUMMED));
        status = write_file(partial, eeprom, sizeof(eeprom));
    }
    if (status == CARTRIDGE_XEMU_OK) {
        status = sync_and_rename(partial, path);
    }
    finish("eeprom", path, partial, status);
    return status;
}

CartridgeXemuStatus cartridge_xemu_format_base_drive(const char *path)
{
    if (!path_is_absolute(path)) {
        return CARTRIDGE_XEMU_BAD_ARGUMENT;
    }
    CartridgeXemuStatus status;
    if (!path_is_free(path, &status)) {
        return status;
    }

    g_autofree char *partial = g_strdup_printf("%s.partial", path);
    unlink(partial);

    status = CARTRIDGE_XEMU_OK;
    int fd = open(partial, O_RDWR | O_CREAT | O_EXCL, 0644);
    if (fd < 0) {
        status = status_for_errno(errno);
    } else {
        if (ftruncate(fd, (off_t)BASE_DRIVE_SIZE) != 0) {
            status = status_for_errno(errno);
        }
        close(fd);
    }

    if (status == CARTRIDGE_XEMU_OK) {
        struct fatx_fs fs;
        memset(&fs, 0, sizeof(fs));
        fatx_log_init(&fs, stderr, FATX_LOG_LEVEL_WARNING);
        errno = 0;
        // fatx/pyfatx/pyfatx/__init__.py:269 formats with these arguments.
        if (fatx_disk_format(&fs, partial, 512, FATX_FORMAT_RETAIL, 128) !=
            FATX_STATUS_SUCCESS) {
            status = status_for_errno(errno);
        }
    }
    if (status == CARTRIDGE_XEMU_OK) {
        status = sync_and_rename(partial, path);
    }
    finish("base drive", path, partial, status);
    return status;
}

CartridgeXemuStatus cartridge_xemu_create_game_drive(const char *path,
                                                     const char *base_path)
{
    if (!path_is_absolute(path) || !path_is_absolute(base_path)) {
        return CARTRIDGE_XEMU_BAD_ARGUMENT;
    }
    CartridgeXemuStatus status;
    if (!path_is_free(path, &status)) {
        return status;
    }

    struct stat base;
    if (stat(base_path, &base) != 0 || !S_ISREG(base.st_mode)) {
        fprintf(stderr, "cartridge: base drive %s is not a regular file\n",
                     base_path);
        return CARTRIDGE_XEMU_BAD_ARGUMENT;
    }

    size_t name_len = strlen(base_path);
    uint64_t size = (uint64_t)base.st_size;
    uint64_t l2_coverage = (QCOW2_CLUSTER_SIZE / sizeof(uint64_t)) *
                           QCOW2_CLUSTER_SIZE;
    uint64_t l1_size = DIV_ROUND_UP(size, l2_coverage);
    if (name_len > QCOW2_BACKING_NAME_MAX ||
        l1_size * sizeof(uint64_t) > QCOW2_CLUSTER_SIZE) {
        fprintf(stderr, "cartridge: base drive %s cannot back a game drive\n",
                     base_path);
        return CARTRIDGE_XEMU_BAD_ARGUMENT;
    }

    g_autofree uint8_t *image = g_malloc0(QCOW2_CLUSTERS * QCOW2_CLUSTER_SIZE);
    uint8_t *header = image;
    uint32_t ext_offset = QCOW2_HEADER_LENGTH;
    uint32_t name_offset = ext_offset + 8 + 8 + 8;

    stl_be_p(header + 0, QCOW2_MAGIC);
    stl_be_p(header + 4, QCOW2_VERSION);
    stq_be_p(header + 8, name_offset);
    stl_be_p(header + 16, (uint32_t)name_len);
    stl_be_p(header + 20, QCOW2_CLUSTER_BITS);
    stq_be_p(header + 24, size);
    stl_be_p(header + 36, (uint32_t)l1_size);
    stq_be_p(header + 40, QCOW2_L1_CLUSTER * QCOW2_CLUSTER_SIZE);
    stq_be_p(header + 48, QCOW2_REFCOUNT_TABLE_CLUSTER * QCOW2_CLUSTER_SIZE);
    stl_be_p(header + 56, 1);
    stl_be_p(header + 96, QCOW2_REFCOUNT_ORDER);
    stl_be_p(header + 100, QCOW2_HEADER_LENGTH);

    stl_be_p(header + ext_offset, QCOW2_EXT_BACKING_FORMAT);
    stl_be_p(header + ext_offset + 4, 3);
    memcpy(header + ext_offset + 8, "raw", 3);
    memcpy(header + name_offset, base_path, name_len);

    stq_be_p(image + QCOW2_REFCOUNT_TABLE_CLUSTER * QCOW2_CLUSTER_SIZE,
             QCOW2_REFCOUNT_BLOCK_CLUSTER * QCOW2_CLUSTER_SIZE);
    uint8_t *refcounts = image + QCOW2_REFCOUNT_BLOCK_CLUSTER *
                                 QCOW2_CLUSTER_SIZE;
    for (int i = 0; i < QCOW2_CLUSTERS; i++) {
        stw_be_p(refcounts + i * 2, 1);
    }

    g_autofree char *partial = g_strdup_printf("%s.partial", path);
    unlink(partial);

    status = write_file(partial, image, QCOW2_CLUSTERS * QCOW2_CLUSTER_SIZE);
    if (status == CARTRIDGE_XEMU_OK) {
        status = sync_and_rename(partial, path);
    }
    finish("game drive", path, partial, status);
    return status;
}
