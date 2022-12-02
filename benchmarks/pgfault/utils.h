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

static inline unsigned long RDTSC(void)
{
	unsigned int a, d;
	__asm__ volatile("rdtsc" : "=a" (a), "=d" (d));
	return ((unsigned long)a) | (((unsigned long)d) << 32);
}

static inline unsigned long RDTSCP(unsigned int *auxp)
{
	unsigned int a, d, c;
	__asm__ volatile("rdtscp" : "=a" (a), "=d" (d), "=c" (c));
	if (auxp)
		*auxp = c;
	return ((unsigned long)a) | (((unsigned long)d) << 32);
}

/********/

/**
 * is_power_of_two - determines if an integer is a power of two
 * @x: the value
 *
 * Returns true if the integer is a power of two.
 */
#define _is_power_of_two(x) ((x) != 0 && !((x) & ((x) - 1)))

/**
 * align_up - rounds a value up to an alignment
 * @x: the value
 * @align: the alignment (must be power of 2)
 *
 * Returns an aligned value.
 */
#define _align_up(x, align)			\
	({assert(_is_power_of_two(align));	\
	 (((x) - 1) | ((__typeof__(x))(align) - 1)) + 1;})

/**
 * align_down - rounds a value down to an alignment
 * @x: the value
 * @align: the alignment (must be power of 2)
 *
 * Returns an aligned value.
 */
#define _align_down(x, align)			\
	({assert(_is_power_of_two(align));	\
	 ((x) & ~((__typeof__(x))(align) - 1));})

/********/

unsigned long time_calibrate_tsc(void);

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

/* a fast xorshift pseudo-random generator
 * from https://prng.di.unimi.it/xoshiro256plusplus.c */
struct app_rand_state {
  unsigned long s[4];
};

/* from wikipedia: https://en.wikipedia.org/wiki/Xorshift */ 
int app_rand_seed(struct app_rand_state* result, unsigned long seed);
unsigned long app_rand_next(struct app_rand_state* state);

#endif  // __UTILS_H__
