// Copyright © 2018-2021 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: BSD-2-Clause

#define _GNU_SOURCE

#include "uffd.h"

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
#include "logging.h"
#include "config.h"

struct uffd_info_t uffd_info = {
  .fd_count = 0
};

int userfaultfd(int flags) { return syscall(SYS_userfaultfd, flags); }

int uffd_init(void) {
  int r;
  struct uffdio_api api = {
      .api = UFFD_API,
#ifdef REGISTER_MADVISE_NOTIF
      .features = UFFD_FEATURE_EVENT_FORK | UFFD_FEATURE_EVENT_REMAP |
                  UFFD_FEATURE_EVENT_REMOVE | UFFD_FEATURE_EVENT_UNMAP
#else
      .features = UFFD_FEATURE_EVENT_FORK | UFFD_FEATURE_EVENT_REMAP |
                  UFFD_FEATURE_EVENT_UNMAP
#endif
  };

#ifdef UFFD_APP_POLL
  api.features |= UFFD_FEATURE_POLL;
#endif

  uint64_t ioctl_mask =
      (1ull << _UFFDIO_REGISTER) | (1ull << _UFFDIO_UNREGISTER);

  int fd = userfaultfd(O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) {
    pr_err("userfaultfd failed");
    ASSERT(0);
    return -1;
  }

  r = ioctl(fd, UFFDIO_API, &api);
  if (r < 0) {
    pr_err("ioctl(fd, UFFDIO_API, ...) failed");
    ASSERT(0);
    return -1;
  }
  if ((api.ioctls & ioctl_mask) != ioctl_mask) {
    pr_err("supported features %llx ioctls %llx", api.features, api.ioctls);
    ASSERT(0);
    return -1;
  }

  return fd;
}

int uffd_register(int fd, unsigned long addr, size_t size, int writeable) {
  int r;
  uint64_t ioctls_mask = (1ull << _UFFDIO_COPY);

  int mode;
  if (writeable)
    mode = UFFDIO_REGISTER_MODE_MISSING | UFFDIO_REGISTER_MODE_WP;
  else
    mode = UFFDIO_REGISTER_MODE_MISSING;

  struct uffdio_register reg = {.mode = mode,
                                .range = {.start = addr, .len = size}};

  r = ioctl(fd, UFFDIO_REGISTER, &reg);
  if (r < 0) {
    pr_debug_err("ioctl(fd, UFFDIO_REGISTER, ...) failed: size %ld addr %lx",
                 size, addr);
    ASSERT(0);
    goto out;
  }

  if ((reg.ioctls & ioctls_mask) != ioctls_mask) {
    pr_debug("unexpected UFFD ioctls");
    r = -1;
    goto out;
  }
  pr_debug("ioctl(fd, UFFDIO_REGISTER, ...) succeed: size %ld addr %lx", size,
           addr);

out:
  return r;
}

int uffd_unregister(int fd, unsigned long addr, size_t size) {
  int r = 0;
  struct uffdio_range range = {.start = addr, .len = size};

  r = ioctl(fd, UFFDIO_UNREGISTER, &range);
  if (r < 0) pr_debug_err("ioctl(fd, UFFDIO_UNREGISTER, ...) failed");

  return r;
}

int uffd_copy(int fd, unsigned long dst, unsigned long src, size_t size, 
    bool wrprotect, bool no_wake, bool retry, int *n_retries) 
{
    int r;
    int mode = 0;

    if (n_retries)
        *n_retries = 0;

    if (wrprotect)  
        mode |= UFFDIO_COPY_MODE_WP;
    if (no_wake)    
        mode |= UFFDIO_COPY_MODE_DONTWAKE;
    struct uffdio_copy copy = {
        .dst = dst, 
        .src = src, 
        .len = size, 
        .mode = mode
    };

    do {
        pr_debug("uffd_copy from src %lx, size %lu to dst %lx wpmode %d nowake %d", 
            src, size, dst, wrprotect, no_wake);
        errno = 0;

        /* TODO: Use UFFD_USE_PWRITE (see kona)? */
        r = ioctl(fd, UFFDIO_COPY, &copy);
        if (r < 0) {
            pr_debug("uffd_copy copied %lld bytes, addr=%lx, errno=%d", 
                copy.copy, dst, errno);

            if (errno == ENOSPC) {
                // The child process has exited.
                // We should drop this request.
                r = 0;
                break;

            } else if (errno == EEXIST) {
                /* something wrong with our page locking */
                pr_err("uffd_copy err EEXIST on %lx", dst);
                BUG();
            } else if (errno == EAGAIN) {
                /* layout change in progress; try again */
                if (retry == false) {
                    /* do not retry, let the caller handle it */
                    r = EAGAIN;
                    break;
                }
                (*n_retries)++;
            } else {
                pr_info("uffd_copy errno=%d: unhandled error", errno);
                BUG();
            }
        }
    } while (r && errno == EAGAIN);
    return r;
}

int uffd_copy_size(int fd, unsigned long dst, unsigned long src, size_t size,
                   int wpmode) {
  struct uffdio_copy copy = {
      .dst = dst, .src = (long)src, .len = size, .mode = wpmode};
  int r;

  ASSERT(size >= PAGE_SIZE);

  r = ioctl(fd, UFFDIO_COPY, &copy);

  if (r < 0) pr_debug_err("UFFDIO_COPY");

  return r;
}

int uffd_wp(int fd, unsigned long addr, size_t size, bool wrprotect, 
    bool no_wake, bool retry, int *n_retries) 
{
    int r;
    int mode = 0;

    if (wrprotect)  
        mode |= UFFDIO_WRITEPROTECT_MODE_WP;
    if (no_wake)    
        mode |= UFFDIO_WRITEPROTECT_MODE_DONTWAKE;
    struct uffdio_writeprotect wp = {
        .mode = mode,
        .range = {.start = addr, .len = size}
    };

    do {
        pr_debug("uffd_wp start %p size %lx mode %d nowake %d", 
            (void *)addr, size, wrprotect, no_wake);
        errno = 0;
        r = ioctl(fd, UFFDIO_WRITEPROTECT, &wp);
        if (r < 0) {
            pr_debug("uffd_wp errno=%d", errno);
            if (errno == EEXIST || errno == ENOSPC) {
                /* This page is already write-protected OR the child process 
                    has exited. We should drop this request. */
                r = 0;
                break;
            } else if (errno == EAGAIN) {
                /* layout change in progress; try again */
                if (retry == false) {
                    /* do not retry, let the caller handle it */
                    r = EAGAIN;
                    break;
                }
                (*n_retries)++;
            } else {
                pr_info("uffd_wp errno=%d: unhandled error", errno);
                BUG();
            }
        }
    } while (r && errno == EAGAIN);
    return r;
}

int uffd_zero(int fd, unsigned long addr, size_t size, bool retry,
              int *n_retries) {
  struct uffdio_zeropage zero = {.mode = 0,
                                 .range = {.start = addr, .len = size}};
  int r;

  do {
    pr_debug("uffd_zero to addr %lx size=%lu", addr, size);
    errno = 0;
    r = ioctl(fd, UFFDIO_ZEROPAGE, &zero);

    if (r < 0) {
      pr_debug("uffd_zero copied %lld bytes, errno=%d", zero.zeropage, errno);

      if (errno == ENOSPC) {
        // The child process has exited.
        // We should drop this request.
        r = 0;
        break;

      } else if (errno == EAGAIN || errno == EEXIST) {
        // layout change in progress; try again
        errno = EAGAIN;
        if (retry == false) {
          // Do not spin in this function and retry, let the caller handle it.
          r = EAGAIN;
          break;
        }
        (*n_retries)++;
      } else {
        pr_info("uffd_zero errno=%d: unhandled error", errno);
        ASSERT(0);
      }
    }
  } while (r && errno == EAGAIN);

  return r;
}

int uffd_wake(int fd, unsigned long addr, size_t size) {
  // This will wake all threads waiting on this range:
  // From https://lore.kernel.org/lkml/5661B62B.2020409@gmail.com/T/:
  //
  // userfaults won't wait in "pending" state to be read anymore and any
  // UFFDIO_WAKE or similar operations that has the objective of waking
  // userfaults after their resolution, will wake all blocked userfaults
  // for the resolved range, including those that haven't been read() by
  // userland yet.

  struct uffdio_range range = {.start = addr, .len = size};
  int r;

  r = ioctl(fd, UFFDIO_WAKE, &range);

  if (r < 0) pr_debug_err("UFFDIO_WAKE");
  return r;
}

void add_uffd_evt_fd(int fd) {
#ifdef FORK_SUPPORT
  uffd_info.evt[uffd_info.evt_count++].fd = fd;
  pr_info("added fd:%d at position %d", fd, uffd_info.evt_count - 1);
#endif
}