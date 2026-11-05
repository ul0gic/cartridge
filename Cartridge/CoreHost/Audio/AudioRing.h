#ifndef AudioRing_h
#define AudioRing_h

#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>

#include "../../Shared/CartridgeShared.h"

#define CARTRIDGE_AUDIO_STEP_MIN 0.95
#define CARTRIDGE_AUDIO_STEP_MAX 1.05
#define CARTRIDGE_AUDIO_FILL_GAIN 0.01
#define CARTRIDGE_AUDIO_WARMUP_SECONDS 2.0
#define CARTRIDGE_AUDIO_AVERAGE_SECONDS 60.0
// Long enough that one late 50 fps frame moves a window by 2%, inside the 5% step ceiling.
#define CARTRIDGE_AUDIO_WINDOW_SECONDS 1.0

#pragma clang assume_nonnull begin

typedef struct {
    int16_t *samples;
    uint32_t mask;
    uint32_t limit;
    uint32_t prime;
    uint32_t target;
    uint32_t nominalRate;
    _Atomic uint32_t head;
    _Atomic uint32_t tail;
    _Atomic uint32_t rate;
    _Atomic uint32_t paused;
    _Atomic uint32_t reprime;
    _Atomic uint32_t rejectedWindows;
    _Atomic uint32_t rejectedRate;
    uint32_t primed;
    uint32_t lastDelivered;
    double position;
    double elapsed;
    double running;
    double windowDelivered;
    double windowSeconds;
    double windowStartElapsed;
    double windowStartRunning;
    double previousDelivered;
    double previousSeconds;
} CartridgeAudioRing;

static inline CartridgeAudioRing *_Nullable cartridge_audio_ring_create(uint32_t sampleRate, uint32_t primeFrames, uint32_t limitFrames, uint32_t targetFrames)
{
    if (sampleRate == 0 || targetFrames == 0 || primeFrames > limitFrames || targetFrames > limitFrames) {
        return NULL;
    }
    uint32_t capacity = 1;
    while (capacity < limitFrames * 2) {
        capacity <<= 1;
    }
    CartridgeAudioRing *ring = calloc(1, sizeof(CartridgeAudioRing));
    if (ring == NULL) {
        return NULL;
    }
    ring->samples = calloc((size_t)capacity * 2, sizeof(int16_t));
    if (ring->samples == NULL) {
        free(ring);
        return NULL;
    }
    ring->mask = capacity - 1;
    ring->limit = limitFrames;
    ring->prime = primeFrames;
    ring->target = targetFrames;
    ring->nominalRate = sampleRate;
    atomic_store_explicit(&ring->rate, sampleRate, memory_order_relaxed);
    return ring;
}

static inline void cartridge_audio_ring_destroy(CartridgeAudioRing *ring)
{
    free(ring->samples);
    free(ring);
}

static inline void cartridge_audio_write(CartridgeAudioRing *ring, const int16_t *frames, uint32_t count)
{
    uint32_t head = atomic_load_explicit(&ring->head, memory_order_relaxed);
    uint32_t skipped = 0;
    if (count > ring->limit) {
        skipped = count - ring->limit;
        frames += (size_t)skipped * 2;
        count = ring->limit;
    }
    for (uint32_t i = 0; i < count; i++) {
        uint32_t slot = ((head + skipped + i) & ring->mask) * 2;
        ring->samples[slot] = frames[i * 2];
        ring->samples[slot + 1] = frames[i * 2 + 1];
    }
    atomic_store_explicit(&ring->head, head + skipped + count, memory_order_release);
}

static inline uint32_t cartridge_audio_fill(const CartridgeAudioRing *ring)
{
    uint32_t head = atomic_load_explicit(&ring->head, memory_order_relaxed);
    uint32_t tail = atomic_load_explicit(&ring->tail, memory_order_relaxed);
    uint32_t fill = head - tail;
    return fill > ring->limit ? ring->limit : fill;
}

static inline uint32_t cartridge_audio_rate(const CartridgeAudioRing *ring)
{
    return atomic_load_explicit(&ring->rate, memory_order_relaxed);
}

static inline uint32_t cartridge_audio_rejected_windows(const CartridgeAudioRing *ring)
{
    return atomic_load_explicit(&ring->rejectedWindows, memory_order_acquire);
}

static inline uint32_t cartridge_audio_rejected_rate(const CartridgeAudioRing *ring)
{
    return atomic_load_explicit(&ring->rejectedRate, memory_order_relaxed);
}

static inline void cartridge_audio_set_paused(CartridgeAudioRing *ring, uint32_t paused)
{
    if (!paused) {
        atomic_store_explicit(&ring->reprime, 1, memory_order_relaxed);
    }
    atomic_store_explicit(&ring->paused, paused, memory_order_release);
}

static inline void cartridge_audio_silence(float *left, float *right, uint32_t from, uint32_t count)
{
    for (uint32_t i = from; i < count; i++) {
        left[i] = 0;
        right[i] = 0;
    }
}

static inline double cartridge_audio_clamp(double value, double low, double high)
{
    return value < low ? low : (value > high ? high : value);
}

static inline void cartridge_audio_close_window(CartridgeAudioRing *ring)
{
    double ceiling = CARTRIDGE_AUDIO_STEP_MAX * (double)ring->nominalRate;
    double rate = ring->windowDelivered / ring->windowSeconds;
    double pairRate = (ring->windowDelivered + ring->previousDelivered) / (ring->windowSeconds + ring->previousSeconds);
    if (rate > ceiling && pairRate > ceiling) {
        ring->elapsed = ring->windowStartElapsed;
        ring->running = ring->windowStartRunning;
        atomic_store_explicit(&ring->rejectedRate, (uint32_t)cartridge_audio_clamp(rate, 0.0, (double)UINT32_MAX), memory_order_relaxed);
        atomic_fetch_add_explicit(&ring->rejectedWindows, 1, memory_order_release);
    }
    ring->previousDelivered = ring->windowDelivered;
    ring->previousSeconds = ring->windowSeconds;
    ring->windowDelivered = 0;
    ring->windowSeconds = 0;
}

static inline void cartridge_audio_pull(CartridgeAudioRing *ring, CartridgeSharedMemory *shm, float *left, float *right, uint32_t count)
{
    if (atomic_load_explicit(&ring->paused, memory_order_acquire)) {
        cartridge_audio_silence(left, right, 0, count);
        return;
    }
    uint32_t head = atomic_load_explicit(&ring->head, memory_order_acquire);
    uint32_t tail = atomic_load_explicit(&ring->tail, memory_order_relaxed);
    if (atomic_exchange_explicit(&ring->reprime, 0, memory_order_relaxed)) {
        tail = head;
        ring->primed = 0;
        ring->position = 0;
        ring->windowDelivered = 0;
        ring->windowSeconds = 0;
        ring->previousDelivered = 0;
        ring->previousSeconds = 0;
    }
    uint32_t available = head - tail;
    if (available > ring->limit) {
        tail = head - ring->limit;
        available = ring->limit;
    }
    if (!ring->primed && available >= ring->prime) {
        ring->primed = 1;
    }
    if (!ring->primed) {
        ring->lastDelivered = head;
        atomic_store_explicit(&ring->tail, tail, memory_order_release);
        cartridge_audio_silence(left, right, 0, count);
        return;
    }

    double seconds = (double)count / (double)ring->nominalRate;
    double delivered = (double)(uint32_t)(head - ring->lastDelivered);
    ring->lastDelivered = head;
    if (ring->windowSeconds == 0) {
        ring->windowStartElapsed = ring->elapsed;
        ring->windowStartRunning = ring->running;
    }
    ring->windowDelivered += delivered;
    ring->windowSeconds += seconds;
    ring->elapsed += seconds;
    double window = ring->elapsed < CARTRIDGE_AUDIO_AVERAGE_SECONDS ? ring->elapsed : CARTRIDGE_AUDIO_AVERAGE_SECONDS;
    ring->running += (delivered / seconds - ring->running) * seconds / window;
    if (ring->windowSeconds >= CARTRIDGE_AUDIO_WINDOW_SECONDS) {
        cartridge_audio_close_window(ring);
    }
    double rate = ring->elapsed < CARTRIDGE_AUDIO_WARMUP_SECONDS ? (double)ring->nominalRate : ring->running;
    atomic_store_explicit(&ring->rate, (uint32_t)rate, memory_order_relaxed);

    double fillError = cartridge_audio_clamp(((double)available - (double)ring->target) / (double)ring->target, -1.0, 1.0);
    double step = cartridge_audio_clamp(rate / (double)ring->nominalRate * (1.0 + CARTRIDGE_AUDIO_FILL_GAIN * fillError), CARTRIDGE_AUDIO_STEP_MIN, CARTRIDGE_AUDIO_STEP_MAX);

    double position = ring->position;
    uint32_t produced = 0;
    while (produced < count) {
        uint32_t whole = (uint32_t)position;
        if (whole + 1 >= available) {
            break;
        }
        float fraction = (float)(position - (double)whole);
        const int16_t *first = &ring->samples[((tail + whole) & ring->mask) * 2];
        const int16_t *second = &ring->samples[((tail + whole + 1) & ring->mask) * 2];
        left[produced] = ((float)first[0] + (float)(second[0] - first[0]) * fraction) * (1.0f / 32768.0f);
        right[produced] = ((float)first[1] + (float)(second[1] - first[1]) * fraction) * (1.0f / 32768.0f);
        position += step;
        produced++;
    }
    if (produced < count) {
        cartridge_audio_silence(left, right, produced, count);
        cartridge_shm_add_audio_underruns(shm, 1);
    }
    uint32_t consumed = (uint32_t)position;
    ring->position = position - (double)consumed;
    atomic_store_explicit(&ring->tail, tail + consumed, memory_order_release);
}

#pragma clang assume_nonnull end

#endif
