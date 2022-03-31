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

#define GIGA (1ULL << 30)
#define MAX_CORES 28	/*cores per numa node*/
#define MAX_THREADS (MAX_CORES-1)

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

void* thread_main(void* args) {
    struct thread_data * tdata = (struct thread_data *)args;
    ASSERTZ(pin_thread(tdata->core));
    int self = tdata->tid;
	int r, retries;
	void *p, *page_buf = malloc(PAGE_SIZE);

	r = pthread_barrier_wait(&ready);	/*signal ready*/
    ASSERT(r != EINVAL);

	while(!start_button)	cpu_relax();
	while(!stop_button) {
		p = (void*)(tdata->range_start + rand_next(&tdata->rs) % tdata->range_len);
		p = (void*) page_align(p);
		r = uffd_copy(uffd_info.userfault_fd, (unsigned long)p, 
			(unsigned long) page_buf, 0, true, &retries, false);
		if (r)	tdata->errors++;
		else tdata->xput_ops++;
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

	/* parse & validate args */
    if (argc > 2) {
        printf("Invalid args\n");
        printf("Usage: %s [num_threads]\n", argv[0]);
        return 1;
    }
    num_threads = atoi(argv[1]);
	ASSERT(num_threads > 0 && num_threads <= MAX_THREADS);
	ASSERTZ(num_threads & (num_threads - 1));	/*power of 2*/

	/*init*/
    ASSERT(sizeof(struct thread_data) == CACHE_LINE_SIZE);
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
	uffd_info.userfault_fd = uffd_init();
	ASSERT(uffd_info.userfault_fd >= 0);
	init_uffd_evt_fd();

	int fd2 = uffd_init();
	ASSERT(fd2 >= 0);
	printf("fds: %d, %d\n", uffd_info.userfault_fd, fd2);

	/*create/register uffd region*/
	int writeable = 1;
	size = 128*GIGA;
	struct uffd_region_t* reg = create_uffd_region(size, writeable);
	ASSERT(reg != NULL);
	ASSERT(reg->addr);
	r = uffd_register(uffd_info.userfault_fd, reg->addr, reg->size, writeable);
	ASSERTZ(r);

	/* NOTE: While we registered a uffd region, we don't have a manager 
	 * handling uffd events from the kernel in this test. Any access to uffd 
	 * region will trigger such an event so we can't do any direct access.
	 * Prefetch_page access won't trigger this event so we're fine. */

    struct thread_data tdata[MAX_THREADS] CACHE_ALIGN = {0};
	int coreidx = 0, runtime_secs = 1;
	pthread_t threads[MAX_THREADS];
	ASSERTZ(pthread_barrier_init(&ready, NULL, num_threads + 1));
	pin_thread(coreidx++);	/*main thread on core 0*/
	
	for(i = 0; i < num_threads; i++) {
		tdata[i].tid = i;
		ASSERTZ(rand_seed(&tdata[i].rs, time(NULL) ^ i));
        ASSERT(coreidx < MAX_CORES);
        tdata[i].core = CORELIST[coreidx++];
		tdata[i].range_start = reg->addr + i * (size / num_threads);
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
	} while(duration_secs <= runtime_secs);
	stop_button = 1;

	uint64_t xput = 0, errors = 0;
	for (i = 0; i < num_threads; i++) {
		xput += tdata[i].xput_ops;
		errors += tdata[i].errors;
	}
	xput += errors;	/*count errors too*/
	xput = xput / num_threads;
	// printf("ran for %.1lf secs; errors %lu\n", duration_secs, errors);

	printf("%d,%.0lf\n", num_threads, xput / duration_secs);
	// printf("%.2lfµs\n", duration_secs * 1000000 / xput);

	return 0;
}
