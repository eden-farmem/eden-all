// Copyright © 2018-2021 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: BSD-2-Clause

#ifndef __REGION_H__
#define __REGION_H__

#include "logging.h"
#include "uffd.h"
#include "pflags.h"

struct uffd_region_t *create_uffd_region(size_t size, int writeable);
void delete_region_list(void);
void __delete_uffd_region(struct uffd_region_t *mr);

/*****************************************************************************
 *****************************************************************************/

static inline void uffd_regions_lock(void) {
  BUG_ON(pthread_mutex_lock(&uffd_info.region_mutex) < 0);
}

static inline void uffd_regions_unlock(void) {
  BUG_ON(pthread_mutex_unlock(&uffd_info.region_mutex) < 0);
}

static inline void mapping_lock(struct uffd_region_t *mr) {
  BUG_ON(pthread_mutex_lock(&mr->mapping_mutex) < 0);
}

static inline int mapping_trylock(struct uffd_region_t *mr) {
  return pthread_mutex_trylock(&mr->mapping_mutex);
}

static inline void mapping_unlock(struct uffd_region_t *mr) {
  BUG_ON(pthread_mutex_unlock(&mr->mapping_mutex) < 0);
}

// this is called while holding uffd_regions_lock
static inline bool get_mr(struct uffd_region_t *mr) {
  int r = atomic_fetch_add_explicit(&mr->ref_cnt, 1, memory_order_acquire);

  BUG_ON(r < 0);
  return (r > 0);
}

/*****************************************************************************
 *****************************************************************************/

static inline bool is_in_uffd_region(struct uffd_region_t *mr,
                                       unsigned long addr) {
  return addr >= mr->addr && addr < mr->addr + mr->size;
}

static inline bool within_uffd_region(void *ptr) {
  if (ptr == NULL || &uffd_info == NULL || &(uffd_info.region_list) == NULL ||
      SLIST_EMPTY(&uffd_info.region_list))
    return false;

  struct uffd_region_t *mr = NULL;
  SLIST_FOREACH(mr, &uffd_info.region_list, link) {
    if (is_in_uffd_region(mr, (unsigned long)ptr)) {
      return true;
    }
  }
  return false;
}

static inline struct uffd_region_t *get_available_mr(size_t size) {
  struct uffd_region_t *mr = NULL;
  SLIST_FOREACH(mr, &uffd_info.region_list, link) {
    size_t required_space = size;
    if (mr->current_offset + required_space <= mr->size) {
      pr_debug("%s:found avilable mr:%p for size:%ld", __func__, mr, size);
      ///      pid_t pid = getpid();
      ///      printf("%s:%d:found avilable mr:%p for size:%ld\n", __func__,
      ///      pid, mr, size);
      return mr;
    } else {
      pr_debug("%s: mr:%p is out of memory. size:%ld, current offset:%lld",
                __func__, mr, mr->size, mr->current_offset);
    }
  }
  pr_err("available mr does not have enough memory to serve, add new slab");
  return NULL;
}

static inline struct uffd_region_t *find_region_by_addr(unsigned long addr) {
  struct uffd_region_t *mr = NULL;
  /*
   * First check the special case that the caller may not have considered
   * of a NULL pointer.
   */
  if (addr == 0) return NULL;

  SLIST_FOREACH(mr, &uffd_info.region_list, link) {
    if (is_in_uffd_region(mr, addr)) {
      get_mr(mr);
      break;
    }
  }

  return mr;
}

static inline void put_mr_references(struct uffd_region_t *mr, int n) {
  pr_debug("decreasing ref_cnt for mr %p", mr);
  int r = atomic_fetch_sub_explicit(&mr->ref_cnt, n, memory_order_consume);
  if (r > 1) return;
  ASSERT(r == 1);
  __delete_uffd_region(mr);
}

static inline void put_mr(struct uffd_region_t *mr) {
  ASSERT(mr);
  if (mr != NULL) put_mr_references(mr, 1);
}

static inline int close_remove_uffd_region(struct uffd_region_t *reg) {
  pr_debug("close remove uffd region");
  if (!reg) {
    ASSERT(0);
    return -1;
  }
  put_mr_references(reg, 1);
  return 0;
}

#endif  // __REGION_H__