// Copyright © 2018-2021 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: BSD-2-Clause

#define _GNU_SOURCE

#include "utils.h"

#include <arpa/inet.h>
#include <assert.h>
#include <errno.h>
#include <execinfo.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <unistd.h>

void dump_stack() {
  void *trace[16];
  char **messages = (char **)NULL;
  int i, trace_size = 0;

  trace_size = backtrace(trace, 16);
  messages = backtrace_symbols(trace, trace_size);
  pr_err("%d==[stack trace]>>>", 0);

  for (i = 0; i < trace_size; i++) pr_err("%s", messages[i]);

  pr_err("<<<[stack trace]==%d\n", 0);
  free(messages);
}
