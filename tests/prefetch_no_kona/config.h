// Copyright © 2018-2021 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: BSD-2-Clause

#ifndef __CONFIG_H__
#define __CONFIG_H__

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

#define MAX_EVENT_FD 100

#define PAGE_SHIFT (12)
#define PAGE_SIZE (1ull << PAGE_SHIFT)
#define PAGE_MASK (~(PAGE_SIZE - 1))

#define CHUNK_SHIFT (12)
#define CHUNK_SIZE (1ull << CHUNK_SHIFT)
#define CHUNK_MASK (~(CHUNK_SIZE - 1))
_Static_assert(CHUNK_SIZE >= PAGE_SIZE,
               "Chunk size must be bigger or equal to a page");

#endif  // __CONFIG_H__