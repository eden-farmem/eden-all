// Original source: Linux selftest from Nadav Amit's patch
// https://lore.kernel.org/lkml/20210225072910.2811795-4-namit@vmware.com/

/*
 * Extending "vdso_test_prefetch_page.c: Test vDSO's prefetch_page()" for user faults
 * Backed by Kona's userfault manager
 */

#define _GNU_SOURCE

#include <stdint.h>
#include <elf.h>
#include <stdio.h>
#include <assert.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdbool.h>
#include <string.h>
#include <sys/auxv.h>
#include <sys/time.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <errno.h>
#include <stdlib.h>
#include <time.h>
#include <linux/userfaultfd.h>

#include "utils.h"
#include "logging.h"
#include "ops.h"
#include "klib.h"
#include "klib_sfaults.h"

#ifdef USE_PREFETCH 
#include "parse_vdso.h"
#endif

#ifdef USE_PREFETCH 
const char *version = "LINUX_2.6";
const char *name = "__vdso_prefetch_page";
typedef long (*prefetch_page_t)(const void *p);
static prefetch_page_t prefetch_page;
#endif

#define GIGA (1ULL << 30)

const int NODE0_CORES[] = {
    0,  1,  2,  3,  4,  5,  6, 
    7,  8,  9,  10, 11, 12, 13, 
    28, 29, 30, 31, 32, 33, 34, 
    35, 36, 37, 38, 39, 40, 41 };
const int NODE1_CORES[] = {
    14, 15, 16, 17, 18, 19, 20, 
    21, 22, 23, 24, 25, 26, 27, 
    42, 43, 44, 45, 46, 47, 48, 
    49, 50, 51, 52, 53, 54, 55 };
const int KONA_CORES[] = { 
	PIN_EVICTION_HANDLER_CORE, PIN_FAULT_HANDLER_CORE, 
	PIN_POLLER_CORE, PIN_ACCOUNTING_CORE };
#define CORELIST NODE1_CORES		/*RNIC on node 1*/
#define EXCLUDED KONA_CORES
#define NUM_CORES (sizeof(CORELIST)/sizeof(CORELIST[0]))
#define NUM_EXCLUDED (sizeof(EXCLUDED)/sizeof(EXCLUDED[0]))
#define MAX_APP_CORES (NUM_CORES - NUM_EXCLUDED)
#define MAX_THREADS (MAX_APP_CORES-1)
#define RUNTIME_SECS 5

uint64_t cycles_per_us;
pthread_barrier_t ready;
int start_button = 0, stop_button = 0;

struct thread_data {
    int tid;
	int core;
    struct rand_state rs;
	uint64_t range_start;
	uint64_t range_len;
	int xput_ops;
	int errors;
} CACHE_ALIGN;

int is_page_mapped(const void* p) {
	p = page_align(p);

#ifdef USE_PREFETCH
	return prefetch_page(p) == 0;
#else
	/* NOTE: mincore() doesn't exactly get whether page is 
	 * is mapped but for userfaultfd purposes it seems to be ok? */
	char vec;
	if (mincore((void *)p, PAGE_SIZE, &vec)) {
		pr_err("mincore failed: %s\n", strerror(errno));
		ASSERT(0);
	}
	return vec & 1;
#endif
}

int next_available_core(int coreidx) {
	int i;
	ASSERT(coreidx < NUM_CORES);
	coreidx++;
	while (coreidx < NUM_CORES) {
		for(i = 0; i < NUM_EXCLUDED; i++) {
			if (EXCLUDED[i] == CORELIST[i])
				break;
		}
		if (i == NUM_EXCLUDED)
			break;
		coreidx++;
	}
	ASSERT(coreidx < NUM_CORES);	/*out of cores!*/
	return coreidx;
}

void* thread_main(void* args) {
    struct thread_data * tdata = (struct thread_data *)args;
    ASSERTZ(pin_thread(tdata->core));
	pr_debug("thread %d pinned to core %d\n", tdata->tid, tdata->core);

    int self = tdata->tid;
	int r, retries, tmp;
	void *p, *page_buf = malloc(PAGE_SIZE);

	r = pthread_barrier_wait(&ready);	/*signal ready*/
    ASSERT(r != EINVAL);

	while(!start_button)	cpu_relax();
	p = (void*)(tdata->range_start);
	p = (void*) page_align(p);
	printf("thread %d with memory start %lu, size %lu\n", self, tdata->range_start, tdata->range_len);
	while(!stop_button) {
		// p = (void*)(tdata->range_start + rand_next(&tdata->rs) % tdata->range_len);
		// p = (void*) page_align(p);
		// tmp = (int*) p;
		// if (r)	tdata->errors++;
		// else tdata->xput_ops++;
		tmp = *(int*)p;	/*access*/
		tdata->xput_ops++;
		BUG_ON((unsigned long) p > tdata->range_start + tdata->range_len); 
		p += PAGE_SIZE;
		// if (tdata->xput_ops == 10)	break;
	}
}

int main(int argc, char **argv)
{
	unsigned long sysinfo_ehdr;
	char *p;
	bool page_mapped;
	int i, j, r, num_threads, max_threads;
	uint64_t start, duration;
	double duration_secs;
	size_t size;

	/* parse & validate args */
    if (argc > 2) {
        printf("Invalid args\n");
        printf("Usage: %s [num_threads]\n", argv[0]);
        return 1;
    }
	else if (argc == 2) {
    	num_threads = atoi(argv[1]);
		max_threads = MAX_THREADS;
		ASSERT(num_threads > 0 && num_threads <= max_threads);
	}
	else {
		num_threads = 1;
	}

	/*init*/
    ASSERT(sizeof(struct thread_data) == CACHE_LINE_SIZE);
	cycles_per_us = time_calibrate_tsc();
	printf("time calibration - cycles per µs: %lu\n", cycles_per_us);
	ASSERT(cycles_per_us);

	/*kona init*/
	putenv("MEMORY_LIMIT=34359738368");		/*32gb, BIG to avoid eviction*/
	putenv("EVICTION_THRESHOLD=1");			/*32gb, BIG to avoid eviction*/
	putenv("EVICTION_DONE_THRESHOLD=1");	/*32gb, BIG to avoid eviction*/
	size = 34359738368;
	rinit();

#ifdef USE_PREFETCH 
	/*find prefetch_page vDSO symbol*/
	sysinfo_ehdr = getauxval(AT_SYSINFO_EHDR);
	if (!sysinfo_ehdr) {
		printf("[ERROR]\tAT_SYSINFO_EHDR is not present!\n");
		return 1;
	}

	vdso_init_from_sysinfo_ehdr(getauxval(AT_SYSINFO_EHDR));
	prefetch_page = (prefetch_page_t)vdso_sym(version, name);
	if (!prefetch_page) {
		printf("[ERROR]\tCould not find %s in vdso\n", name);
		return 1;
	}
#endif

	p = rmalloc(size);
	ASSERT(p != NULL);

    struct thread_data tdata[MAX_THREADS] CACHE_ALIGN = {0};
	int coreidx = 0;
	pthread_t threads[MAX_THREADS];
	ASSERTZ(pthread_barrier_init(&ready, NULL, num_threads + 1));
	pin_thread(coreidx);	/*main thread on core 0*/
	
	for(i = 0; i < num_threads; i++) {
		tdata[i].tid = i;
		ASSERTZ(rand_seed(&tdata[i].rs, time(NULL) ^ i));
        ASSERT(coreidx < NUM_CORES);
		coreidx = next_available_core(coreidx);
        tdata[i].core = coreidx;
		tdata[i].range_start = ((unsigned long) p) + i * (size / num_threads);
		tdata[i].range_len = (size / num_threads);
        pthread_create(&threads[i], NULL, thread_main, (void*)&tdata[i]);
	}

	r = pthread_barrier_wait(&ready);	/*until all threads ready*/
    ASSERT(r != EINVAL);
	
	start = rdtsc();
	start_button = 1;
	do {
		duration = rdtscp(NULL) - start;
		duration_secs = duration / (1000000.0 * cycles_per_us);
	} while(duration_secs <= RUNTIME_SECS);
	stop_button = 1;

	uint64_t xput = 0, errors = 0;
	for (i = 0; i < num_threads; i++) {
		xput += tdata[i].xput_ops;
		errors += tdata[i].errors;
	}
	
	// printf("ran for %.1lf secs; total xput %lu\n", duration_secs, xput);
	printf("result:%d,%.0lf\n", num_threads, xput / duration_secs);
	// printf("%.2lfµs\n", duration_secs * 1000000 / xput);

	rdestroy();

	return 0;
}
