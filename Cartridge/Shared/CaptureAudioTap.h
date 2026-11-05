#ifndef CaptureAudioTap_h
#define CaptureAudioTap_h

#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define CARTRIDGE_TAP_MAGIC 0x43544150u
#define CARTRIDGE_TAP_VERSION 1u
#define CARTRIDGE_TAP_FRAMES 65536u
#define CARTRIDGE_TAP_TAGS 1024u
#define CARTRIDGE_TAP_SIZE 294912
// Most frames one write copies before publishing; readers treat this many frames past samplesWritten as in flight.
#define CARTRIDGE_TAP_WRITE_CHUNK 4096u

typedef struct {
    uint64_t frameSequence;
    uint64_t sampleEnd;
} CartridgeTapTag;

typedef struct {
    uint32_t magic;
    uint32_t version;
    _Atomic uint32_t sampleRate;
    uint32_t reserved;
    _Atomic uint64_t samplesWritten;
    _Atomic uint64_t tagsWritten;
    CartridgeTapTag tags[CARTRIDGE_TAP_TAGS];
    int16_t samples[CARTRIDGE_TAP_FRAMES * 2];
} CartridgeAudioTap;

_Static_assert(sizeof(CartridgeAudioTap) <= CARTRIDGE_TAP_SIZE, "CartridgeAudioTap exceeds its mapping");

static inline CartridgeAudioTap *cartridge_tap_create(const char *name)
{
    int fd = shm_open(name, O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0) {
        return NULL;
    }
    if (ftruncate(fd, CARTRIDGE_TAP_SIZE) != 0) {
        int failure = errno;
        close(fd);
        shm_unlink(name);
        errno = failure;
        return NULL;
    }
    void *memory = mmap(NULL, CARTRIDGE_TAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    int failure = errno;
    close(fd);
    if (memory == MAP_FAILED) {
        shm_unlink(name);
        errno = failure;
        return NULL;
    }
    CartridgeAudioTap *tap = (CartridgeAudioTap *)memory;
    tap->magic = CARTRIDGE_TAP_MAGIC;
    tap->version = CARTRIDGE_TAP_VERSION;
    return tap;
}

static inline CartridgeAudioTap *cartridge_tap_open(const char *name)
{
    int fd = shm_open(name, O_RDWR);
    if (fd < 0) {
        return NULL;
    }
    void *memory = mmap(NULL, CARTRIDGE_TAP_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    int failure = errno;
    close(fd);
    if (memory == MAP_FAILED) {
        errno = failure;
        return NULL;
    }
    CartridgeAudioTap *tap = (CartridgeAudioTap *)memory;
    if (tap->magic != CARTRIDGE_TAP_MAGIC || tap->version != CARTRIDGE_TAP_VERSION) {
        munmap(memory, CARTRIDGE_TAP_SIZE);
        errno = EINVAL;
        return NULL;
    }
    return tap;
}

static inline void cartridge_tap_unmap(CartridgeAudioTap *tap)
{
    munmap(tap, CARTRIDGE_TAP_SIZE);
}

static inline int cartridge_tap_unlink(const char *name)
{
    return shm_unlink(name);
}

static inline void cartridge_tap_set_rate(CartridgeAudioTap *tap, uint32_t sampleRate)
{
    atomic_store_explicit(&tap->sampleRate, sampleRate, memory_order_release);
}

static inline uint32_t cartridge_tap_sample_rate(const CartridgeAudioTap *tap)
{
    return atomic_load_explicit(&tap->sampleRate, memory_order_acquire);
}

static inline uint64_t cartridge_tap_samples_written(const CartridgeAudioTap *tap)
{
    return atomic_load_explicit(&tap->samplesWritten, memory_order_acquire);
}

static inline uint64_t cartridge_tap_tags_written(const CartridgeAudioTap *tap)
{
    return atomic_load_explicit(&tap->tagsWritten, memory_order_acquire);
}

// Seqlock writer (Boehm, "Can Seqlocks Get Along with Programming Language Memory Models?"): the fence orders
// the previous publish before this chunk's data, so a reader that sees the data also sees the chunk start.
static inline void cartridge_tap_write(CartridgeAudioTap *tap, const int16_t *samples, size_t frames)
{
    uint64_t written = atomic_load_explicit(&tap->samplesWritten, memory_order_relaxed);
    while (frames > 0) {
        size_t chunk = frames < CARTRIDGE_TAP_WRITE_CHUNK ? frames : CARTRIDGE_TAP_WRITE_CHUNK;
        size_t position = (size_t)(written % CARTRIDGE_TAP_FRAMES);
        size_t first = CARTRIDGE_TAP_FRAMES - position < chunk ? CARTRIDGE_TAP_FRAMES - position : chunk;
        atomic_thread_fence(memory_order_release);
        memcpy(&tap->samples[position * 2], samples, first * 2 * sizeof(int16_t));
        memcpy(tap->samples, samples + first * 2, (chunk - first) * 2 * sizeof(int16_t));
        written += chunk;
        samples += chunk * 2;
        frames -= chunk;
        atomic_store_explicit(&tap->samplesWritten, written, memory_order_release);
    }
}

static inline void cartridge_tap_tag(CartridgeAudioTap *tap, uint64_t frameSequence)
{
    uint64_t index = atomic_load_explicit(&tap->tagsWritten, memory_order_relaxed);
    CartridgeTapTag *slot = &tap->tags[index % CARTRIDGE_TAP_TAGS];
    atomic_thread_fence(memory_order_release);
    slot->frameSequence = frameSequence;
    slot->sampleEnd = atomic_load_explicit(&tap->samplesWritten, memory_order_relaxed);
    atomic_store_explicit(&tap->tagsWritten, index + 1, memory_order_release);
}

static inline bool cartridge_tap_read_tag(const CartridgeAudioTap *tap, uint64_t index, CartridgeTapTag *tag)
{
    uint64_t written = atomic_load_explicit(&tap->tagsWritten, memory_order_acquire);
    if (index >= written || index + CARTRIDGE_TAP_TAGS <= written) {
        return false;
    }
    CartridgeTapTag copy = tap->tags[index % CARTRIDGE_TAP_TAGS];
    atomic_thread_fence(memory_order_acquire);
    uint64_t after = atomic_load_explicit(&tap->tagsWritten, memory_order_relaxed);
    if (index + CARTRIDGE_TAP_TAGS <= after) {
        return false;
    }
    *tag = copy;
    return true;
}

static inline bool cartridge_tap_copy(const CartridgeAudioTap *tap, uint64_t from, size_t frames, int16_t *destination)
{
    uint64_t written = atomic_load_explicit(&tap->samplesWritten, memory_order_acquire);
    if (from > written || frames > written - from || from + CARTRIDGE_TAP_FRAMES < written + CARTRIDGE_TAP_WRITE_CHUNK) {
        return false;
    }
    size_t position = (size_t)(from % CARTRIDGE_TAP_FRAMES);
    size_t first = CARTRIDGE_TAP_FRAMES - position < frames ? CARTRIDGE_TAP_FRAMES - position : frames;
    memcpy(destination, &tap->samples[position * 2], first * 2 * sizeof(int16_t));
    memcpy(destination + first * 2, tap->samples, (frames - first) * 2 * sizeof(int16_t));
    atomic_thread_fence(memory_order_acquire);
    uint64_t after = atomic_load_explicit(&tap->samplesWritten, memory_order_relaxed);
    return from + CARTRIDGE_TAP_FRAMES >= after + CARTRIDGE_TAP_WRITE_CHUNK;
}

#endif
