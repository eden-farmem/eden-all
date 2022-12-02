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

/* a fast xorshift pseudo-random generator
 * from https://prng.di.unimi.it/xoshiro256plusplus.c */
static inline uint64_t app_rotl(const uint64_t x, int k) {
	return (x << k) | (x >> (64 - k));
}

uint64_t app_splitmix64(uint64_t* state) {
	uint64_t result = ((*state) += 0x9E3779B97f4A7C15);
	result = (result ^ (result >> 30)) * 0xBF58476D1CE4E5B9;
	result = (result ^ (result >> 27)) * 0x94D049BB133111EB;
	return result ^ (result >> 31);
}

/* from wikipedia: https://en.wikipedia.org/wiki/Xorshift */ 
int app_rand_seed(struct app_rand_state* result, uint64_t seed) {
	uint64_t smx_state = seed;
	uint64_t tmp = app_splitmix64(&smx_state);
	result->s[0] = (uint32_t)tmp;
	result->s[1] = (uint32_t)(tmp >> 32);

	tmp = app_splitmix64(&smx_state);
	result->s[2] = (uint32_t)tmp;
	result->s[3] = (uint32_t)(tmp >> 32);
	if (result->s[0] == 0 && result->s[1] == 0 && 
		result->s[2] == 0 && result->s[3] == 0)
			return 1;	/*bad seed*/
	return 0;
}

uint64_t app_rand_next(struct app_rand_state* state) {
  uint64_t* s = state->s;
	const uint64_t result = app_rotl(s[0] + s[3], 23) + s[0];
	const uint64_t t = s[1] << 17;

	s[2] ^= s[0];
	s[3] ^= s[1];
	s[1] ^= s[2];
	s[0] ^= s[3];

	s[2] ^= t;

	s[3] = app_rotl(s[3], 45);
	return result;
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