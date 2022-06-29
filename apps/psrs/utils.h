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
#include <pthread.h>
#include <math.h>

#include "logging.h"
#include "asm/ops.h"

// #define DEBUG

#define ASSERT(x) assert((x))
#define ASSERTZ(x) ASSERT(!(x))

#define _PAGE_SHIFT       (12)
#define _PAGE_SIZE        (1ull << _PAGE_SHIFT)
#define _PAGE_OFFSET_MASK (_PAGE_SIZE - 1)
#define _PAGE_MASK        (~_PAGE_OFFSET_MASK)
#define CACHE_LINE_SIZE 64
#define __aligned(x) __attribute__((aligned(x)))
#define CACHE_ALIGN __aligned(CACHE_LINE_SIZE)

/********************************************
************************************************/

void dump_stack(void);
uint64_t time_calibrate_tsc(void);

static inline const void *page_align(const void *p)
{
	return (const void *)((unsigned long)p & ~(_PAGE_SIZE - 1));
}

static inline unsigned int uint_min(unsigned int a, unsigned int b) {
  return (a < b) ? a : b;
}

static inline void *xmalloc(size_t size) {
  void *ptr = malloc(size);
  assert(ptr);
  return ptr;
}

/* pin this thread to a particular core */
static int pin_thread(int core) {
  cpu_set_t cpuset;
  CPU_ZERO(&cpuset);
  CPU_SET(core, &cpuset);
  int retcode = pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
  if (retcode) { 
      errno = retcode;
      perror("pthread_setaffinitity_np");
  }
  return retcode;
}

/* returns the next time interval for events based on poisson arrivals */
static inline double poisson_event(double rate, unsigned long rnd)
{
    return -logf(1.0f - ((double)(rnd % RAND_MAX)) 
		/ (double)(RAND_MAX)) 
		/ rate;
}

/* a fast xorshift pseudo-random generator
 * from https://prng.di.unimi.it/xoshiro256plusplus.c */
struct rand_state {
  uint64_t s[4];
};

/* from wikipedia: https://en.wikipedia.org/wiki/Xorshift */ 
int rand_seed(struct rand_state* result, uint64_t seed);
uint64_t rand_next(struct rand_state* state);

#endif  // __UTILS_H__
