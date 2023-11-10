/*
 * simd-string.c
 * Copyright (C) 2023 Kovid Goyal <kovid at kovidgoyal.net>
 *
 * Distributed under terms of the GPL3 license.
 */

#include "data-types.h"
#include "simd-string.h"
#include <immintrin.h>

uint8_t
byte_loader_peek(const ByteLoader *self) {
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    return self->m & 0xff;
#define SHIFT_OP >>
#elif __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    // no idea if this is correct needs testing
    return (self->m >> ((sizeof(self->m) - 1)*8)) & 0xff;
#define SHIFT_OP <<
#else
#error "Unsupported endianness"
#endif
}

void
byte_loader_init(ByteLoader *self, const uint8_t *buf, unsigned int sz) {
    size_t extra = ((uintptr_t)buf) % sizeof(BYTE_LOADER_T);
    if (extra) { // align loading
        buf -= extra; sz += extra;
    }
    size_t s = MIN(sz, sizeof(self->m));
    self->next_load_at = buf + s;
    self->num_left = sz - extra;
    self->digits_left = sizeof(self->m) - extra;
    self->m = (*((BYTE_LOADER_T*)buf)) SHIFT_OP (8 * extra);
    self->sz_of_next_load = sz - s;
}

uint8_t
byte_loader_next(ByteLoader *self) {
    uint8_t ans = byte_loader_peek(self);
    self->num_left--; self->digits_left--; self->m = self->m SHIFT_OP 8;
    if (!self->digits_left) byte_loader_init(self, self->next_load_at, self->sz_of_next_load);
    return ans;
}

static void
byte_loader_skip(ByteLoader *self) {
    if (self->num_left >= sizeof(BYTE_LOADER_T)) {
        self->m = *(BYTE_LOADER_T*)self->next_load_at;
        self->num_left -= sizeof(BYTE_LOADER_T);
        self->digits_left = sizeof(BYTE_LOADER_T);
        self->next_load_at += sizeof(BYTE_LOADER_T);
    } else {
        self->num_left = 0;
    }
}

#define haszero(v) (((v) - 0x0101010101010101ULL) & ~(v) & 0x8080808080808080ULL)
#define prepare_for_hasvalue(n) (~0ULL/255 * (n))
#define hasvalue(x,n) (haszero((x) ^ (n)))

static uint8_t*
find_either_of_two_chars_simple(uint8_t *haystack, const size_t sz, const uint8_t x, const uint8_t y) {
    ByteLoader it; byte_loader_init(&it, haystack, sz);

    // first align by testing the first few bytes one at a time
    while (it.num_left && it.digits_left < sizeof(BYTE_LOADER_T)) {
        const uint8_t ch = byte_loader_next(&it);
        if (ch == x || ch == y) return haystack + sz - it.num_left - 1;
    }

    const BYTE_LOADER_T a = prepare_for_hasvalue(x), b = prepare_for_hasvalue(y);
    while (it.num_left) {
        if (hasvalue(it.m, a) || hasvalue(it.m, b)) {
            uint8_t *ans = haystack + sz - it.num_left, q = hasvalue(it.m, a) ? x : y;
            while (it.num_left) {
                if (byte_loader_next(&it) == q) return ans;
                ans++;
            }
            return NULL; // happens for final word and it.num_left < sizeof(BYTE_LOADER_T)
        }
        byte_loader_skip(&it);
    }
    return NULL;
}
#undef SHIFT_OP

uint8_t*
find_either_of_two_chars(uint8_t *haystack, const size_t sz, const uint8_t a, const uint8_t b) {
    return find_either_of_two_chars_simple(haystack, sz, a, b);
}
