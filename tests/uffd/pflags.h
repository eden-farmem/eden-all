// Copyright © 2018-2021 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: BSD-2-Clause

#ifndef __PFLAGS_H__
#define __PFLAGS_H__

#include "uffd.h"

enum {
  PAGE_FLAG_P_SHIFT,
  PAGE_FLAG_D_SHIFT,
  PAGE_FLAG_E_SHIFT,
  PAGE_FLAG_Z_SHIFT,
  PAGE_FLAGS_NUM
};

static_assert(!(PAGE_FLAGS_NUM & (PAGE_FLAGS_NUM - 1)),
              "page flags num must be power of 2");

#define PAGE_FLAG_P (1u << PAGE_FLAG_P_SHIFT)  // Page is present
#define PAGE_FLAG_D (1u << PAGE_FLAG_D_SHIFT)  // Page is dirty
#define PAGE_FLAG_E (1u << PAGE_FLAG_E_SHIFT)  // Do not evict page
#define PAGE_FLAG_Z (1u << PAGE_FLAG_Z_SHIFT)  // Zeropage done
#define PAGE_FLAGS_MASK ((1u << PAGE_FLAGS_NUM) - 1)

inline atomic_char *page_flags_ptr(struct uffd_region_t *mr, unsigned long addr,
                                   int *bits_offset) {
  int b = ((addr - mr->addr) >> CHUNK_SHIFT) * PAGE_FLAGS_NUM;

  *bits_offset = b % 8;
  return &mr->page_flags[b / 8];
}

inline unsigned char get_page_flags(struct uffd_region_t *mr, unsigned long addr) {
  int bit_offset;
  atomic_char *ptr = page_flags_ptr(mr, addr, &bit_offset);

  return (*ptr >> bit_offset) & PAGE_FLAGS_MASK;
}

static inline bool is_page_dirty(struct uffd_region_t *mr, unsigned long addr) {
  return !!(get_page_flags(mr, addr) & PAGE_FLAG_D);
}

static inline bool is_page_present(struct uffd_region_t *mr, unsigned long addr) {
  return !!(get_page_flags(mr, addr) & PAGE_FLAG_P);
}

inline bool is_page_do_not_evict(struct uffd_region_t *mr, unsigned long addr) {
  return !!(get_page_flags(mr, addr) & PAGE_FLAG_E);
}

static inline bool is_page_zeropage_done(struct uffd_region_t *mr,
                                         unsigned long addr) {
  return !!(get_page_flags(mr, addr) & PAGE_FLAG_Z);
}

static inline bool is_page_dirty_flags(unsigned char flags) {
  return !!(flags & PAGE_FLAG_D);
}

static inline bool is_page_present_flags(unsigned char flags) {
  return !!(flags & PAGE_FLAG_P);
}

static inline bool is_page_do_not_evict_flags(unsigned char flags) {
  return !!(flags & PAGE_FLAG_E);
}

static inline bool is_page_zeropage_done_flags(unsigned char flags) {
  return !!(flags & PAGE_FLAG_Z);
}

static inline unsigned char set_page_flags(struct uffd_region_t *mr,
                                           unsigned long addr,
                                           unsigned char flags) {
  int bit_offset;
  unsigned char old_flags;
  atomic_char *ptr = page_flags_ptr(mr, addr, &bit_offset);

  old_flags = atomic_fetch_or(ptr, flags << bit_offset);
  return (old_flags >> bit_offset) & PAGE_FLAGS_MASK;
}

static inline unsigned char set_page_present(struct uffd_region_t *mr,
                                             unsigned long addr) {
  return set_page_flags(mr, addr, PAGE_FLAG_P);
}

static inline unsigned char set_page_dirty(struct uffd_region_t *mr,
                                           unsigned long addr) {
  return set_page_flags(mr, addr, PAGE_FLAG_D | PAGE_FLAG_P);
}

static inline unsigned char set_page_do_not_evict(struct uffd_region_t *mr,
                                                  unsigned long addr) {
  return set_page_flags(mr, addr, PAGE_FLAG_E);
}

static inline unsigned char set_page_zeropage_done(struct uffd_region_t *mr,
                                                   unsigned long addr) {
  return set_page_flags(mr, addr, PAGE_FLAG_Z);
}

static inline unsigned char clear_page_flags(struct uffd_region_t *mr,
                                             unsigned long addr,
                                             unsigned char flags) {
  int bit_offset;
  unsigned char old_flags;
  atomic_char *ptr = page_flags_ptr(mr, addr, &bit_offset);

  old_flags = atomic_fetch_and(ptr, ~(flags << bit_offset));
  return (old_flags >> bit_offset) & PAGE_FLAGS_MASK;
}

static inline unsigned char clear_page_present(struct uffd_region_t *mr,
                                               unsigned long addr) {
  return clear_page_flags(mr, addr, PAGE_FLAG_P | PAGE_FLAG_D | PAGE_FLAG_E);
}

static inline unsigned char clear_page_dirty(struct uffd_region_t *mr,
                                             unsigned long addr) {
  return clear_page_flags(mr, addr, PAGE_FLAG_D);
}

static inline unsigned char clear_page_do_not_evict(struct uffd_region_t *mr,
                                                    unsigned long addr) {
  return clear_page_flags(mr, addr, PAGE_FLAG_E);
}

static inline unsigned char clear_page_zeropage_done(struct uffd_region_t *mr,
                                                     unsigned long addr) {
  return clear_page_flags(mr, addr, PAGE_FLAG_Z);
}

static inline int mark_chunks_nonpresent(struct uffd_region_t *mr, unsigned long addr, size_t size) {
  unsigned long offset;
  int old_flags, chunks = 0;

  for (offset = 0; offset < size; offset += CHUNK_SIZE) {
    old_flags = clear_page_present(mr, addr + offset);

    if (!!(old_flags & PAGE_FLAG_P)) {
      pr_debug("Clear page present for: %lx", addr + offset);
      chunks++;
    }
  }
  // Return how many pages were marked as not present
  return chunks;
}

#endif  // __PFLAGS_H_
