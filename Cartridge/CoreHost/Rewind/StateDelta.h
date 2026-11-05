#ifndef StateDelta_h
#define StateDelta_h

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#pragma clang assume_nonnull begin

size_t state_delta_block_size(size_t state_size);
size_t state_delta_block_allocation(size_t state_size);
size_t state_delta_max_patch_size(size_t state_size);
void state_delta_mark_blocks(uint8_t *this_block, uint8_t *next_block, size_t state_size);
size_t state_delta_compress(const void *older, const void *newer, size_t block_size, void *patch);
bool state_delta_apply(const void *patch, size_t patch_len, void *data, size_t block_size);

#pragma clang assume_nonnull end

#endif
