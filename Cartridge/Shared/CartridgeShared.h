#ifndef CartridgeShared_h
#define CartridgeShared_h

#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#define CARTRIDGE_SHM_MAGIC 0x43415254u
#define CARTRIDGE_SHM_VERSION 6u
#define CARTRIDGE_SHM_SIZE 4096

#define CARTRIDGE_SPEED_NORMAL 0u
#define CARTRIDGE_SPEED_REWIND 1u
#define CARTRIDGE_SPEED_FAST_FORWARD 2u

#define CARTRIDGE_ACTIVE_NORMAL 0u
#define CARTRIDGE_ACTIVE_REWINDING 1u
#define CARTRIDGE_ACTIVE_REWIND_HOLDING 2u
#define CARTRIDGE_ACTIVE_FAST_FORWARD 3u

typedef struct {
    _Atomic uint32_t surface;
    _Atomic uint32_t width;
    _Atomic uint32_t height;
    _Atomic uint32_t pacingInterval;
    _Atomic uint64_t startNs;
} CartridgeSharedFrame;

typedef struct {
    uint32_t magic;
    uint32_t version;
    _Atomic uint64_t frameSequence;
    CartridgeSharedFrame latestFrame;
    CartridgeSharedFrame previousFrame;
    _Atomic uint32_t joypad0;
    _Atomic int16_t analogLeftX;
    _Atomic int16_t analogLeftY;
    _Atomic int16_t analogRightX;
    _Atomic int16_t analogRightY;
    _Atomic uint64_t framesProduced;
    _Atomic uint64_t audioUnderruns;
    _Atomic uint32_t paused;
    _Atomic uint32_t inputSequence;
    _Atomic uint32_t displaySequence;
    _Atomic uint64_t displayTickNs;
    _Atomic uint64_t displayPeriodNs;
    _Atomic int32_t corePolicy;
    _Atomic int32_t corePriority;
    _Atomic uint32_t speedRequest;
    _Atomic uint32_t speedActive;
    _Atomic uint8_t leftTrigger;
    _Atomic uint8_t rightTrigger;
} CartridgeSharedMemory;

_Static_assert(sizeof(CartridgeSharedMemory) <= CARTRIDGE_SHM_SIZE, "CartridgeSharedMemory exceeds one page");

typedef struct {
    uint32_t joypad0;
    int16_t analogLeftX;
    int16_t analogLeftY;
    int16_t analogRightX;
    int16_t analogRightY;
    uint8_t leftTrigger;
    uint8_t rightTrigger;
} CartridgeInputState;

typedef struct {
    uint64_t sequence;
    uint32_t front;
    uint32_t width;
    uint32_t height;
} CartridgeFrameInfo;

typedef struct {
    uint32_t surface;
    uint32_t width;
    uint32_t height;
    uint32_t pacingInterval;
    uint64_t startNs;
} CartridgeFrame;

typedef struct {
    uint64_t sequence;
    CartridgeFrame latest;
    CartridgeFrame previous;
} CartridgeFrames;

typedef struct {
    uint64_t framesProduced;
    uint64_t audioUnderruns;
    uint32_t paused;
} CartridgeCounters;

typedef struct {
    uint64_t tickNs;
    uint64_t periodNs;
} CartridgeDisplayTiming;

typedef struct {
    int32_t policy;
    int32_t priority;
} CartridgeCoreSchedule;

static inline CartridgeSharedMemory *cartridge_shm_create(const char *name)
{
    int fd = shm_open(name, O_CREAT | O_EXCL | O_RDWR, 0600);
    if (fd < 0) {
        return NULL;
    }
    if (ftruncate(fd, CARTRIDGE_SHM_SIZE) != 0) {
        int failure = errno;
        close(fd);
        shm_unlink(name);
        errno = failure;
        return NULL;
    }
    void *memory = mmap(NULL, CARTRIDGE_SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    int failure = errno;
    close(fd);
    if (memory == MAP_FAILED) {
        shm_unlink(name);
        errno = failure;
        return NULL;
    }
    CartridgeSharedMemory *shm = (CartridgeSharedMemory *)memory;
    shm->magic = CARTRIDGE_SHM_MAGIC;
    shm->version = CARTRIDGE_SHM_VERSION;
    return shm;
}

static inline CartridgeSharedMemory *cartridge_shm_open(const char *name)
{
    int fd = shm_open(name, O_RDWR);
    if (fd < 0) {
        return NULL;
    }
    void *memory = mmap(NULL, CARTRIDGE_SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    int failure = errno;
    close(fd);
    if (memory == MAP_FAILED) {
        errno = failure;
        return NULL;
    }
    CartridgeSharedMemory *shm = (CartridgeSharedMemory *)memory;
    if (shm->magic != CARTRIDGE_SHM_MAGIC || shm->version != CARTRIDGE_SHM_VERSION) {
        munmap(memory, CARTRIDGE_SHM_SIZE);
        errno = EINVAL;
        return NULL;
    }
    return shm;
}

static inline void cartridge_shm_unmap(CartridgeSharedMemory *shm)
{
    munmap(shm, CARTRIDGE_SHM_SIZE);
}

static inline int cartridge_shm_unlink(const char *name)
{
    return shm_unlink(name);
}

static inline void cartridge_shm_write_joypad(CartridgeSharedMemory *shm, uint32_t mask)
{
    atomic_store_explicit(&shm->joypad0, mask, memory_order_release);
    atomic_fetch_add_explicit(&shm->inputSequence, 1, memory_order_release);
}

static inline void cartridge_shm_write_analog(CartridgeSharedMemory *shm, uint32_t stick, int16_t x, int16_t y)
{
    if (stick == 0) {
        atomic_store_explicit(&shm->analogLeftX, x, memory_order_release);
        atomic_store_explicit(&shm->analogLeftY, y, memory_order_release);
    } else {
        atomic_store_explicit(&shm->analogRightX, x, memory_order_release);
        atomic_store_explicit(&shm->analogRightY, y, memory_order_release);
    }
    atomic_fetch_add_explicit(&shm->inputSequence, 1, memory_order_release);
}

static inline void cartridge_shm_write_triggers(CartridgeSharedMemory *shm, uint8_t left, uint8_t right)
{
    atomic_store_explicit(&shm->leftTrigger, left, memory_order_release);
    atomic_store_explicit(&shm->rightTrigger, right, memory_order_release);
    atomic_fetch_add_explicit(&shm->inputSequence, 1, memory_order_release);
}

static inline CartridgeInputState cartridge_shm_read_input(const CartridgeSharedMemory *shm)
{
    CartridgeInputState input;
    input.joypad0 = atomic_load_explicit(&shm->joypad0, memory_order_acquire);
    input.analogLeftX = atomic_load_explicit(&shm->analogLeftX, memory_order_acquire);
    input.analogLeftY = atomic_load_explicit(&shm->analogLeftY, memory_order_acquire);
    input.analogRightX = atomic_load_explicit(&shm->analogRightX, memory_order_acquire);
    input.analogRightY = atomic_load_explicit(&shm->analogRightY, memory_order_acquire);
    input.leftTrigger = atomic_load_explicit(&shm->leftTrigger, memory_order_acquire);
    input.rightTrigger = atomic_load_explicit(&shm->rightTrigger, memory_order_acquire);
    return input;
}

static inline void cartridge_shm_store_frame(CartridgeSharedFrame *slot, CartridgeFrame frame)
{
    atomic_store_explicit(&slot->surface, frame.surface, memory_order_relaxed);
    atomic_store_explicit(&slot->width, frame.width, memory_order_relaxed);
    atomic_store_explicit(&slot->height, frame.height, memory_order_relaxed);
    atomic_store_explicit(&slot->pacingInterval, frame.pacingInterval, memory_order_relaxed);
    atomic_store_explicit(&slot->startNs, frame.startNs, memory_order_relaxed);
}

static inline CartridgeFrame cartridge_shm_load_frame(const CartridgeSharedFrame *slot)
{
    CartridgeFrame frame;
    frame.surface = atomic_load_explicit(&slot->surface, memory_order_relaxed);
    frame.width = atomic_load_explicit(&slot->width, memory_order_relaxed);
    frame.height = atomic_load_explicit(&slot->height, memory_order_relaxed);
    frame.pacingInterval = atomic_load_explicit(&slot->pacingInterval, memory_order_relaxed);
    frame.startNs = atomic_load_explicit(&slot->startNs, memory_order_relaxed);
    return frame;
}

static inline void cartridge_shm_publish_frame(CartridgeSharedMemory *shm, CartridgeFrame frame)
{
    cartridge_shm_store_frame(&shm->previousFrame, cartridge_shm_load_frame(&shm->latestFrame));
    cartridge_shm_store_frame(&shm->latestFrame, frame);
    atomic_fetch_add_explicit(&shm->frameSequence, 1, memory_order_release);
}

static inline CartridgeFrames cartridge_shm_read_frames(const CartridgeSharedMemory *shm)
{
    CartridgeFrames frames;
    frames.sequence = atomic_load_explicit(&shm->frameSequence, memory_order_acquire);
    frames.latest = cartridge_shm_load_frame(&shm->latestFrame);
    frames.previous = cartridge_shm_load_frame(&shm->previousFrame);
    return frames;
}

static inline CartridgeFrameInfo cartridge_shm_read_frame(const CartridgeSharedMemory *shm)
{
    CartridgeFrames frames = cartridge_shm_read_frames(shm);
    CartridgeFrameInfo info;
    info.sequence = frames.sequence;
    info.front = frames.latest.surface;
    info.width = frames.latest.width;
    info.height = frames.latest.height;
    return info;
}

static inline void cartridge_shm_add_frames_produced(CartridgeSharedMemory *shm, uint64_t count)
{
    atomic_fetch_add_explicit(&shm->framesProduced, count, memory_order_relaxed);
}

static inline void cartridge_shm_add_audio_underruns(CartridgeSharedMemory *shm, uint64_t count)
{
    atomic_fetch_add_explicit(&shm->audioUnderruns, count, memory_order_relaxed);
}

static inline void cartridge_shm_set_paused(CartridgeSharedMemory *shm, uint32_t paused)
{
    atomic_store_explicit(&shm->paused, paused, memory_order_relaxed);
}

static inline CartridgeCounters cartridge_shm_read_counters(const CartridgeSharedMemory *shm)
{
    CartridgeCounters counters;
    counters.framesProduced = atomic_load_explicit(&shm->framesProduced, memory_order_relaxed);
    counters.audioUnderruns = atomic_load_explicit(&shm->audioUnderruns, memory_order_relaxed);
    counters.paused = atomic_load_explicit(&shm->paused, memory_order_relaxed);
    return counters;
}

static inline void cartridge_shm_write_core_schedule(CartridgeSharedMemory *shm, CartridgeCoreSchedule schedule)
{
    atomic_store_explicit(&shm->corePolicy, schedule.policy, memory_order_relaxed);
    atomic_store_explicit(&shm->corePriority, schedule.priority, memory_order_relaxed);
}

static inline CartridgeCoreSchedule cartridge_shm_read_core_schedule(const CartridgeSharedMemory *shm)
{
    CartridgeCoreSchedule schedule;
    schedule.policy = atomic_load_explicit(&shm->corePolicy, memory_order_relaxed);
    schedule.priority = atomic_load_explicit(&shm->corePriority, memory_order_relaxed);
    return schedule;
}

static inline void cartridge_shm_write_speed_request(CartridgeSharedMemory *shm, uint32_t speed)
{
    atomic_store_explicit(&shm->speedRequest, speed, memory_order_release);
}

static inline uint32_t cartridge_shm_read_speed_request(const CartridgeSharedMemory *shm)
{
    return atomic_load_explicit(&shm->speedRequest, memory_order_acquire);
}

static inline void cartridge_shm_write_speed_active(CartridgeSharedMemory *shm, uint32_t active)
{
    atomic_store_explicit(&shm->speedActive, active, memory_order_relaxed);
}

static inline uint32_t cartridge_shm_read_speed_active(const CartridgeSharedMemory *shm)
{
    return atomic_load_explicit(&shm->speedActive, memory_order_relaxed);
}

// Seqlock (Boehm, "Can Seqlocks Get Along with Programming Language Memory Models?"): odd while writing.
static inline void cartridge_shm_write_display(CartridgeSharedMemory *shm, uint64_t tickNs, uint64_t periodNs)
{
    atomic_fetch_add_explicit(&shm->displaySequence, 1, memory_order_relaxed);
    atomic_thread_fence(memory_order_release);
    atomic_store_explicit(&shm->displayTickNs, tickNs, memory_order_relaxed);
    atomic_store_explicit(&shm->displayPeriodNs, periodNs, memory_order_relaxed);
    atomic_fetch_add_explicit(&shm->displaySequence, 1, memory_order_release);
}

static inline bool cartridge_shm_read_display(const CartridgeSharedMemory *shm, CartridgeDisplayTiming *timing)
{
    uint32_t before = atomic_load_explicit(&shm->displaySequence, memory_order_acquire);
    uint64_t tickNs = atomic_load_explicit(&shm->displayTickNs, memory_order_relaxed);
    uint64_t periodNs = atomic_load_explicit(&shm->displayPeriodNs, memory_order_relaxed);
    atomic_thread_fence(memory_order_acquire);
    uint32_t after = atomic_load_explicit(&shm->displaySequence, memory_order_relaxed);
    if ((before & 1u) != 0 || before != after) {
        return false;
    }
    timing->tickNs = tickNs;
    timing->periodNs = periodNs;
    return true;
}

#endif
