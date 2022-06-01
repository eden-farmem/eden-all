// Copyright © 2018-2021 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: BSD-2-Clause

#ifndef __UTILS_H__
#define __UTILS_H__

#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#include "config.h"
#include "logging.h"
#include "ops.h"

// #define DEBUG

#define ASSERT(x) assert((x))
#define ASSERTZ(x) ASSERT(!(x))

#define CACHE_LINE_SIZE 64
#define __aligned(x) __attribute__((aligned(x)))
#define CACHE_ALIGN __aligned(CACHE_LINE_SIZE)

/********************************************
************************************************/

void dump_stack(void);

static inline const void *page_align(const void *p)
{
	return (const void *)((unsigned long)p & ~(PAGE_SIZE - 1));
}

static inline unsigned long align_up(unsigned long v, unsigned long a) {
  return (v + a - 1) & ~(a - 1);
}

static inline unsigned int uint_min(unsigned int a, unsigned int b) {
  return (a < b) ? a : b;
}

static inline void *xmalloc(size_t size) {
  void *ptr = malloc(size);
  assert(ptr);
  return ptr;
}

/* Returns number of rdtsc cycles based on CPU freq */
/* derived from DPDK */
static uint64_t time_calibrate_tsc(void)
{
	/* TODO: New Intel CPUs report this value in CPUID */
	struct timespec sleeptime = {.tv_nsec = 5E8 }; /* 1/2 second */
	struct timespec t_start, t_end;

	cpu_serialize();
	if (clock_gettime(CLOCK_MONOTONIC_RAW, &t_start) == 0) {
		uint64_t ns, end, start;
		double secs;

		start = rdtsc();
		nanosleep(&sleeptime, NULL);
		clock_gettime(CLOCK_MONOTONIC_RAW, &t_end);
		end = rdtscp(NULL);
		ns = ((t_end.tv_sec - t_start.tv_sec) * 1E9);
		ns += (t_end.tv_nsec - t_start.tv_nsec);

		secs = (double)ns / 1000;
		pr_debug("time: detected %lu ticks / us", (uint64_t)((end - start) / secs));
		return (uint64_t)((end - start) / secs);
	}
	return 0;
}

#endif  // __UTILS_H__
