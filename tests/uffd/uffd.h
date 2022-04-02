// Copyright © 2018-2021 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: BSD-2-Clause

#ifndef __KLIB_UFFD_H__
#define __KLIB_UFFD_H__

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
#include <stdbool.h>
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

#include "utils.h"

struct uffd_region_t {
  int uffd;
  volatile size_t size;
  uint64_t flags;
  unsigned long addr;

  atomic_char *page_flags;
  atomic_int ref_cnt;
  atomic_ullong current_offset;
  SLIST_ENTRY(uffd_region_t) link;

  pthread_mutex_t mapping_mutex;
} CACHE_ALIGN;
SLIST_HEAD(region_listhead, uffd_region_t);

struct uffd_info_t {
  /* file descriptors that are used for management */
  int userfault_fds[MAX_UFFD];
  int fd_count;
  struct pollfd *evt;
  int evt_count;
  /*regions*/
  struct region_listhead region_list;
  pthread_mutex_t region_mutex;
};

extern struct uffd_info_t uffd_info;

int userfaultfd(int flags);
int uffd_init(void);
int uffd_register(int fd, unsigned long addr, size_t size, int writeable);
int uffd_unregister(int fd, unsigned long addr, size_t size);

int uffd_copy(int fd, unsigned long dst, unsigned long src, int wpmode,
              bool retry, int *n_retries, bool wake_on_exist);
int uffd_copy_size(int fd, unsigned long dst, unsigned long src, size_t size,
                   int wpmode);
int uffd_wp(int fd, unsigned long addr, size_t size, int wpmode, bool retry,
            int *n_retries);
int uffd_zero(int fd, unsigned long addr, size_t size, bool retry,
              int *n_retries);
int uffd_wake(int fd, unsigned long addr, size_t size);

void init_uffd_evt_fd(void);
void add_uffd_evt_fd(int fd);

#endif  // __KLIB_UFFD_H__
