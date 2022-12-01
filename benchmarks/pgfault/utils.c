// Copyright © 2018-2021 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: BSD-2-Clause

#include "utils.h"
#include "stdint.h"

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

#include "log.h"

/* Returns number of rdtsc cycles based on CPU freq */
/* derived from DPDK */
uint64_t time_calibrate_tsc(void)
{
	/* TODO: New Intel CPUs report this value in CPUID */
	struct timespec sleeptime = {.tv_nsec = 5E8 }; /* 1/2 second */
	struct timespec t_start, t_end;

	/* cpu serialize */
	__asm__ volatile("cpuid" : : : "%rax", "%rbx", "%rcx", "%rdx");
	
	if (clock_gettime(CLOCK_MONOTONIC_RAW, &t_start) == 0) {
		uint64_t ns, end, start;
		double secs;

		start = RDTSC();
		nanosleep(&sleeptime, NULL);
		clock_gettime(CLOCK_MONOTONIC_RAW, &t_end);
		end = RDTSCP(NULL);
		ns = ((t_end.tv_sec - t_start.tv_sec) * 1E9);
		ns += (t_end.tv_nsec - t_start.tv_nsec);

		secs = (double)ns / 1000;
		pr_debug("time: detected %lu ticks / us", 
			(uint64_t)((end - start) / secs));
		return (uint64_t)((end - start) / secs);
	}
	return 0;
}

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