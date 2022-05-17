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

#ifdef WITH_KONA
#include "klib.h"
#define remoteable_alloc rmalloc
#define remoteable_free rfree
#else 
#define remoteable_alloc malloc
#define remoteable_free free
#endif

#define ASSERT(x) assert((x))
#define ASSERTZ(x) ASSERT(!(x))

#define PAGE_SIZE 4096
#define CACHE_LINE_SIZE 64
#define __aligned(x) __attribute__((aligned(x)))
#define CACHE_ALIGN __aligned(CACHE_LINE_SIZE)

/********************************************
************************************************/

void dump_stack(void);
uint64_t time_calibrate_tsc(void);

static inline const void *page_align(const void *p)
{
	return (const void *)((unsigned long)p & ~(PAGE_SIZE - 1));
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

/* returns exponent of the number rounded upto the next power of two*/
static int next_power_of_two(unsigned long num) {
  unsigned long power =  1;
  int exp = 0;
  while (power < num) {
    power *= 2;
    exp++;
  }
  return exp;
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
