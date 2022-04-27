// Copyright © 2018-2021 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: BSD-2-Clause

#define _GNU_SOURCE

#include "region.h"

#include <arpa/inet.h>
#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/userfaultfd.h>
#include <netdb.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/queue.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/sysinfo.h>
#include <sys/types.h>
#include <ucontext.h>
#include <unistd.h>

#include "uffd.h"
#include "logging.h"

struct uffd_region_t *create_uffd_region(int uffd, size_t size, int writeable) {
  void *ptr = NULL;
  size_t page_flags_size;
  int r;

  // Allocate a new region_t object
  struct uffd_region_t *mr = (struct uffd_region_t *)mmap(
      NULL, sizeof(struct uffd_region_t), PROT_READ | PROT_WRITE,
      MAP_SHARED | MAP_ANONYMOUS, -1, 0);
  mr->size = size;

  r = pthread_mutex_init(&mr->mapping_mutex, NULL);
  if (r < 0) {
    pr_debug_err("pthread_mutex_init");
    goto out_err2;
  }

  int mmap_flags = MAP_PRIVATE | MAP_ANONYMOUS;

  if (writeable)
    ptr = mmap(NULL, mr->size, PROT_READ | PROT_WRITE, mmap_flags, -1, 0);
  else
    ptr = mmap(NULL, mr->size, PROT_READ, mmap_flags, -1, 0);

  if (ptr == MAP_FAILED) {
    pr_debug_err("mmap failed");
    goto out_err2;
  }
  mr->addr = (unsigned long)ptr;

  ASSERT(mr->addr == (unsigned long)ptr);
  if (mr->addr != (unsigned long)ptr) {
    pr_err("Mmap address doesn't match!");
    mr->addr = (unsigned long)ptr;
  }

  pr_debug("mmap ptr %p addr mr %p, size %ld\n", ptr, (void *)mr->addr, mr->size);

  r = uffd_register(uffd, mr->addr, mr->size, writeable);
  if (r < 0) goto out_err2;

  page_flags_size = align_up((mr->size >> CHUNK_SHIFT), 8) * PAGE_FLAGS_NUM / 8;

  // mr->page_flags = calloc(1, page_flags_size);
  mr->page_flags =
      (atomic_char *)mmap(NULL, page_flags_size, PROT_READ | PROT_WRITE,
                          MAP_SHARED | MAP_ANONYMOUS, -1, 0);
  if (mr->page_flags == NULL) goto out_err2;

  mr->ref_cnt = ATOMIC_VAR_INIT(1);
  mr->current_offset = ATOMIC_VAR_INIT(0);
  mr->uffd = uffd;

  uffd_regions_lock();
  SLIST_INSERT_HEAD(&uffd_info.region_list, mr, link);
  uffd_regions_unlock();

  return mr;
out_err2:
  __delete_uffd_region(mr);
out_err:
  return NULL;
}

void __delete_uffd_region(struct uffd_region_t *mr) {
  int r = 0;

  pr_debug("deleting region %p", mr);

  // TODO(irina): if we get here after an error, mr is not in the list, so
  // no need to try to remove
  uffd_regions_lock();
  SLIST_REMOVE(&uffd_info.region_list, mr, uffd_region_t, link);
  uffd_regions_unlock();

  if (mr->addr != 0) {
    uffd_unregister(mr->uffd, mr->addr, mr->size);
    // TODO(irina): if we got here bc of an error, we might want to delete
    // the remote region too;if we are cleaning up on client exit,
    // we want to keep the remote region in ther server for next time.
    //// delete_remote_uffd_region(mr);
    r = munmap((void *)mr->addr, mr->size);
    if (r < 0) pr_debug_err("munmap");
    // free(mr->page_flags);
    size_t page_flags_size =
        align_up((mr->size >> CHUNK_SHIFT), 8) * PAGE_FLAGS_NUM / 8;
    r = munmap(mr->page_flags, page_flags_size);
    if (r < 0) pr_debug_err("munmap page_flags");

    r = pthread_mutex_destroy(&mr->mapping_mutex);
    if (r < 0) pr_debug_err("pthread_mutex_destroy");
  }

  munmap(mr, sizeof(struct uffd_region_t));
}

void delete_region_list(void) {
  pr_debug("deleting local list of regions");
  while (!SLIST_EMPTY(&uffd_info.region_list)) {
    struct uffd_region_t *mr = SLIST_FIRST(&uffd_info.region_list);
    /*TODO: delete any remote slabs associated with this region here */
    if (mr->ref_cnt != 1) pr_debug("found memory region with ref_cnt > 1");
    __delete_uffd_region(mr);
  }
}

static void close_uffd_region(struct uffd_region_t *mr) {
  int r = 0;
  pr_debug("closing region %p", mr);

  // TODO(irina): if we get here after an error, mr is not in the list, so
  // no need to try to remove
  // TODO(irina): leave region in the list for the time being, to be able to
  // serve another open after a close
#if 0
  uffd_regions_lock();
  SLIST_REMOVE(&uffd_info.region_list, mr, uffd_region_t, link);
  uffd_regions_unlock();
#endif

  if (mr->addr != 0) {
    uffd_unregister(mr->uffd, mr->addr, mr->size);
    // TODO(irina): if we got here bc of an error, we might want to delete
    // the remote region too;if we are cleaning up on client exit,
    // we want to keep the remote region in ther server for next time.
    //// delete_remote_uffd_region(mr);
    r = munmap((void *)mr->addr, mr->size);
    if (r < 0) pr_debug_err("munmap");
    // free(mr->page_flags);
    size_t page_flags_size =
        align_up((mr->size >> CHUNK_SHIFT), 8) * PAGE_FLAGS_NUM / 8;
    r = munmap(mr->page_flags, page_flags_size);
    if (r < 0) pr_debug_err("munmap page_flags");

    r = pthread_mutex_destroy(&mr->mapping_mutex);
    if (r < 0) pr_debug_err("pthread_mutex_destroy");
  }

  mr->addr = 0;
}
