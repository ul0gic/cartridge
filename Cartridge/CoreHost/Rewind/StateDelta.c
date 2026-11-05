#include "StateDelta.h"

#include <string.h>

// Ported from RetroArch state_manager.c:50-86 and :128-478; arm64 takes the scalar NO_UNALIGNED_MEM scan (:63-69).
#define STATE_DELTA_MEMCPY_WORDS 32
#define STATE_DELTA_SCAN_PAD 64

static size_t find_change(const uint16_t *a, const uint16_t *b)
{
    const uint16_t *a_org = a;
    while (((uintptr_t)a & (sizeof(size_t) - 1)) && *a == *b) {
        a++;
        b++;
    }
    if (*a == *b) {
        const size_t *a_big = (const size_t *)a;
        const size_t *b_big = (const size_t *)b;
        while (*a_big == *b_big) {
            a_big++;
            b_big++;
        }
        a = (const uint16_t *)a_big;
        b = (const uint16_t *)b_big;
        while (*a == *b) {
            a++;
            b++;
        }
    }
    return (size_t)(a - a_org);
}

static size_t find_same(const uint16_t *a, const uint16_t *b)
{
    const uint16_t *a_org = a;
    if (((uintptr_t)a & (sizeof(uint32_t) - 1)) && *a != *b) {
        a++;
        b++;
    }
    if (*a != *b) {
        const uint32_t *a_big = (const uint32_t *)a;
        const uint32_t *b_big = (const uint32_t *)b;
        while (*a_big != *b_big) {
            a_big++;
            b_big++;
        }
        a = (const uint16_t *)a_big;
        b = (const uint16_t *)b_big;
        if (a != a_org && a[-1] == b[-1]) {
            a--;
            b--;
        }
    }
    return (size_t)(a - a_org);
}

size_t state_delta_block_size(size_t state_size)
{
    return (state_size + sizeof(uint16_t) - 1) & ~(sizeof(uint16_t) - 1);
}

size_t state_delta_block_allocation(size_t state_size)
{
    return state_delta_block_size(state_size) + sizeof(uint16_t) * 4 + STATE_DELTA_SCAN_PAD;
}

size_t state_delta_max_patch_size(size_t state_size)
{
    const size_t max_block_cover = UINT16_MAX * sizeof(uint16_t);
    size_t blocks = (state_size + max_block_cover - 1) / max_block_cover;
    return state_delta_block_size(state_size) + blocks * sizeof(uint16_t) * 2 + sizeof(uint16_t) * 3;
}

// The scans stop only on these differing words past the data (state_manager.c:597-601); the blocks must be zeroed.
void state_delta_mark_blocks(uint8_t *this_block, uint8_t *next_block, size_t state_size)
{
    size_t sentinel = state_delta_block_size(state_size) / sizeof(uint16_t) + 3;
    ((uint16_t *)this_block)[sentinel] = 0;
    ((uint16_t *)next_block)[sentinel] = 1;
}

size_t state_delta_compress(const void *older, const void *newer, size_t block_size, void *patch)
{
    const uint16_t *old16 = (const uint16_t *)older;
    const uint16_t *new16 = (const uint16_t *)newer;
    uint16_t *compressed16 = (uint16_t *)patch;
    size_t num16s = (block_size + sizeof(uint16_t) - 1) / sizeof(uint16_t);

    while (num16s) {
        size_t skip = find_change(old16, new16);
        if (skip >= num16s) {
            break;
        }
        old16 += skip;
        new16 += skip;
        num16s -= skip;

        if (skip > UINT16_MAX) {
            if (skip > UINT32_MAX) {
                skip = UINT32_MAX;
            }
            *compressed16++ = 0;
            *compressed16++ = (uint16_t)skip;
            *compressed16++ = (uint16_t)(skip >> 16);
            continue;
        }

        size_t changed = find_same(old16, new16);
        if (changed > UINT16_MAX) {
            changed = UINT16_MAX;
        }
        *compressed16++ = (uint16_t)changed;
        *compressed16++ = (uint16_t)skip;
        if (changed >= STATE_DELTA_MEMCPY_WORDS) {
            memcpy(compressed16, old16, changed * sizeof(uint16_t));
        } else {
            for (size_t i = 0; i < changed; i++) {
                compressed16[i] = old16[i];
            }
        }
        old16 += changed;
        new16 += changed;
        num16s -= changed;
        compressed16 += changed;
    }

    compressed16[0] = 0;
    compressed16[1] = 0;
    compressed16[2] = 0;
    return (size_t)((uint8_t *)(compressed16 + 3) - (uint8_t *)patch);
}

bool state_delta_apply(const void *patch, size_t patch_len, void *data, size_t block_size)
{
    const uint16_t *patch16 = (const uint16_t *)patch;
    const uint16_t *p = patch16;
    size_t patch_words = patch_len / sizeof(uint16_t);
    size_t words = block_size / sizeof(uint16_t);
    size_t at = 0;
    uint16_t *out16 = (uint16_t *)data;

    for (;;) {
        if ((size_t)(p - patch16) >= patch_words) {
            return false;
        }
        uint16_t numchanged = *p++;
        if (numchanged) {
            if ((size_t)(p - patch16) + 1 + numchanged > patch_words) {
                return false;
            }
            uint16_t skip = *p++;
            if (skip > words - at) {
                return false;
            }
            at += skip;
            if (numchanged > words - at) {
                return false;
            }
            at += numchanged;
            p += numchanged;
        } else {
            if ((size_t)(p - patch16) + 2 > patch_words) {
                return false;
            }
            uint32_t numunchanged = p[0] | ((uint32_t)p[1] << 16);
            if (!numunchanged) {
                break;
            }
            p += 2;
            if (numunchanged > words - at) {
                return false;
            }
            at += numunchanged;
        }
    }

    for (p = patch16;;) {
        uint16_t numchanged = *p++;
        if (numchanged) {
            out16 += *p++;
            if (numchanged >= STATE_DELTA_MEMCPY_WORDS) {
                memcpy(out16, p, numchanged * sizeof(uint16_t));
            } else {
                for (uint16_t i = 0; i < numchanged; i++) {
                    out16[i] = p[i];
                }
            }
            p += numchanged;
            out16 += numchanged;
        } else {
            uint32_t numunchanged = p[0] | ((uint32_t)p[1] << 16);
            if (!numunchanged) {
                break;
            }
            p += 2;
            out16 += numunchanged;
        }
    }
    return true;
}
