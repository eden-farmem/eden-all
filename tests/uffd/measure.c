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
#include "config.h"
#include "ops.h"
#include "uffd.h"
#include "region.h"

#ifdef USE_PREFETCH 
#include "parse_vdso.h"
#endif

#ifdef USE_PREFETCH 
const char *version = "LINUX_2.6";
const char *name = "__vdso_prefetch_page";
typedef long (*prefetch_page_t)(const void *p);
static prefetch_page_t prefetch_page;
#endif

#define GIGA 			(1ULL << 30)
#define MAX_CORES 		28	/*cores per numa node*/
#define MAX_THREADS 	(MAX_CORES-1)
#define MAX_MEMORY 		(128*GIGA)
#define RUNTIME_SECS 	5

uint64_t cycles_per_us;
pthread_barrier_t ready;
const int NODE0_CORES[MAX_CORES] = {
    0,  1,  2,  3,  4,  5,  6, 
    7,  8,  9,  10, 11, 12, 13, 
    28, 29, 30, 31, 32, 33, 34, 
    35, 36, 37, 38, 39, 40, 41 };
#define CORELIST NODE0_CORES
int start_button = 0, stop_button = 0;

struct thread_data {
    int tid;
	int core;
    struct rand_state rs;
	uint64_t range_start;
	uint64_t range_len;
	int xput_ops;
	int errors;
	int uffd;
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

void* uffd_copy_main(void* args) {
    struct thread_data * tdata = (struct thread_data *)args;
    ASSERTZ(pin_thread(tdata->core));
    int self = tdata->tid;
	int r, retries;
	void *p = (void*)tdata->range_start; 
	void *page_buf = malloc(PAGE_SIZE);

	r = pthread_barrier_wait(&ready);	/*signal ready*/
    ASSERT(r != EINVAL);

	while(!start_button)	cpu_relax();
	while(!stop_button) {
		p = (void*) page_align(p);
		r = uffd_copy(tdata->uffd, (unsigned long)p, 
			(unsigned long) page_buf, 0, true, &retries, false);
		if (r)	tdata->errors++;
		else tdata->xput_ops++;
		p += PAGE_SIZE;
		ASSERT((uint64_t)p < (tdata->range_start + tdata->range_len));		/*out of memory region*/
	}
	tdata->range_len = (uint64_t)(p - PAGE_SIZE);		/*new range that is actually filled in*/
}

void* madvise_main(void* args) {
    struct thread_data * tdata = (struct thread_data *)args;
    ASSERTZ(pin_thread(tdata->core));
    int self = tdata->tid;
	int r, retries;
	void *p = (void*)tdata->range_start; 

	r = pthread_barrier_wait(&ready);	/*signal ready*/
    ASSERT(r != EINVAL);

	while(!start_button)	cpu_relax();
	while(!stop_button) {
		p = (void*) page_align(p);
		r = madvise(p, PAGE_SIZE, MADV_DONTNEED);
		if (r)	tdata->errors++;
		else tdata->xput_ops++;
		p += PAGE_SIZE;
		ASSERT((uint64_t)p < (tdata->range_start + tdata->range_len));		/*out of memory region*/
	}
}

int main(int argc, char **argv)
{
	unsigned long sysinfo_ehdr;
	char *p;
	bool page_mapped;
	int i, j, r, num_threads;
	uint64_t start, duration;
	double duration_secs;
	size_t size;
	bool uffd_per_thread = true;

	/* parse & validate args */
    if (argc > 3) {
        printf("Invalid args\n");
        printf("Usage: %s [num_threads] [uffd_per_thread]\n", argv[0]);
        return 1;
    }
    num_threads = atoi(argv[1]);
	uffd_per_thread = (argc > 2) ? atoi(argv[2]) : false;
	ASSERT(num_threads > 0 && num_threads <= MAX_THREADS);
	ASSERT(MAX_UFFD > num_threads);
	ASSERTZ(num_threads & (num_threads - 1));	/*power of 2*/

	/*init*/
    ASSERT(sizeof(struct thread_data) % CACHE_LINE_SIZE == 0);
	cycles_per_us = time_calibrate_tsc();
	ASSERT(cycles_per_us);

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

	/*uffd init*/
	uffd_info.fd_count = 0;
	for(i = 0; i < num_threads; i++) {
		uffd_info.userfault_fds[i] = uffd_init();
		ASSERT(uffd_info.userfault_fds[i] >= 0);
		uffd_info.fd_count++;
		// printf("userfault-fd %d: %d\n", i, uffd_info.userfault_fds[i]);
		if (!uffd_per_thread)	
			break; /*one is enough*/
	}

	/* NOTE: While we registered a uffd region, we don't have a manager 
	 * handling uffd events from the kernel in this test. Any access to uffd 
	 * region will trigger such an event so we can't do any direct access.
	 * Prefetch_page access won't trigger this event so we're fine. */

    struct thread_data tdata[MAX_THREADS] CACHE_ALIGN = {0};
	int coreidx = 0;
	pthread_t threads[MAX_THREADS];
	ASSERTZ(pthread_barrier_init(&ready, NULL, num_threads + 1));
	pin_thread(coreidx++);	/*main thread on core 0*/

	/* UFFD COPY */
	/*create/register uffd regions*/
	int writeable = 1, fd;
	struct uffd_region_t* reg;
	size = MAX_MEMORY / num_threads;
	ASSERT(size % PAGE_SIZE == 0);
	for(i = 0; i < num_threads; i++) {
		fd = uffd_per_thread ? uffd_info.userfault_fds[i]: uffd_info.userfault_fds[0];
		reg = create_uffd_region(fd, size, writeable);
		ASSERT(reg != NULL);
		ASSERT(reg->addr);
		r = uffd_register(fd, reg->addr, reg->size, writeable);
		ASSERTZ(r);

		tdata[i].tid = i;
		tdata[i].uffd = fd;
		ASSERTZ(rand_seed(&tdata[i].rs, time(NULL) ^ i));
        ASSERT(coreidx < MAX_CORES);
        tdata[i].core = CORELIST[coreidx++];
		tdata[i].range_start = reg->addr;
		tdata[i].range_len = size;
        pthread_create(&threads[i], NULL, uffd_copy_main, (void*)&tdata[i]);
	}

	stop_button = 0;
	r = pthread_barrier_wait(&ready);	/*until all threads ready*/
    ASSERT(r != EINVAL);
	
	start = rdtsc();
	start_button = 1;
	do {
		duration = rdtscp(NULL) - start;
		duration_secs = duration / (1000000.0 * cycles_per_us);
	} while(duration_secs <= RUNTIME_SECS);
	stop_button = 1;

	uint64_t uffd_xput = 0, uffd_errors = 0;
	for (i = 0; i < num_threads; i++) {
		uffd_xput += tdata[i].xput_ops;
		uffd_errors += tdata[i].errors;
	}
	uffd_xput /= duration_secs;

	/* MADVISE */
	coreidx = 1;
	// init_madvise();
	for(i = 0; i < num_threads; i++) {
		tdata[i].tid = i;
		tdata[i].uffd = fd;
		ASSERTZ(rand_seed(&tdata[i].rs, time(NULL) ^ i));
        ASSERT(coreidx < MAX_CORES);
        tdata[i].core = CORELIST[coreidx++];
		/*tdata->range_start and range_len should be set already*/
		tdata[i].xput_ops = tdata[i].errors = 0;
        pthread_create(&threads[i], NULL, madvise_main, (void*)&tdata[i]);
	}

	stop_button = 0;
	r = pthread_barrier_wait(&ready);	/*until all threads ready*/
    ASSERT(r != EINVAL);

	start = rdtsc();
	start_button = 1;
	do {
		duration = rdtscp(NULL) - start;
		duration_secs = duration / (1000000.0 * cycles_per_us);
	} while(duration_secs <= RUNTIME_SECS);
	stop_button = 1;

	uint64_t madv_xput = 0, madv_errors = 0;
	for (i = 0; i < num_threads; i++) {
		madv_xput += tdata[i].xput_ops;
		madv_errors += tdata[i].errors;
	}
	madv_xput /= duration_secs;

	printf("%d,%lu,%lu,%lu,%lu\n", num_threads, 
		uffd_xput, uffd_errors, 
		madv_xput, madv_errors);
	// printf("%.2lfµs\n", duration_secs * 1000000 / xput);

	return 0;
}
