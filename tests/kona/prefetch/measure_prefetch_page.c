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

#include "parse_vdso.h"
#include "klib.h"
#include <linux/userfaultfd.h>
#include "ops.h"

const char *version = "LINUX_2.6";
const char *name = "__vdso_prefetch_page";

typedef long (*prefetch_page_t)(const void *p);

#define PAGE_SIZE	(4096ull)
#define ASSERT(x) assert((x))
#define ASSERTZ(x) ASSERT(!(x))

static prefetch_page_t prefetch_page;
extern int mr_mgr_userfault_fd;

static const void *ptr_align(const void *p)
{
	return (const void *)((unsigned long)p & ~(PAGE_SIZE - 1));
}

/* Time Utils */
/* derived from DPDK */
uint64_t cycles_per_us;
static int time_calibrate_tsc(void)
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
		cycles_per_us = (uint64_t)((end - start) / secs);
		printf("time: detected %lu ticks / us\n", cycles_per_us);
		return 0;
	}
	return -1;
}

/* plug a page at given virtual address */
int uffd_plug_page_at(unsigned long dst) {
	void* page_buf = malloc(PAGE_SIZE);
	struct uffdio_copy copy = {
      .dst = dst, 
	  .src = (unsigned long) page_buf, 
	  .len = PAGE_SIZE, 
	  .mode = 0 //UFFDIO_COPY_MODE_DONTWAKE
	};

	int r;
	bool retry = true;
	do {
		errno = 0;
		r = ioctl(mr_mgr_userfault_fd, UFFDIO_COPY, &copy);
		if (r < 0) {
			printf("uffd_copy copied %lld bytes, addr=%lx, errno=%d\n", copy.copy, dst, errno);

			if (errno == ENOSPC) {
				// The child process has exited.
				// We should drop this request.
				r = 0;
				break;

			} else if (errno == EEXIST) {
				printf("uffd_copy EEXIST\n");
				// We are done with this request
				// Return the return value from uffd_wake
				break;
			} else if (errno == EAGAIN) {
				// layout change in progress; try again
				if (retry) {
					retry = false;
				}
				if (retry == false) {
					printf("uffd_copy errno=%d: EAGAIN on second retry\n", errno);
					return 1;
				}
			} else {
				printf("uffd_copy errno=%d: unhandled error\n", errno);
				return 1;
			}
		}
	} while (r && errno == EAGAIN);
	return 0;
}

int main(int argc, char **argv)
{
	unsigned long sysinfo_ehdr;
	char *p;
	bool page_mapped;
	int i, r;
	const int SAMPLES = 100;
	uint64_t start, duration;

	printf("[RUN]\tTesting vdso_prefetch_page\n");

	rinit();
	time_calibrate_tsc();

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

	uint64_t page_mapped_cycles = 0;
	uint64_t page_not_mapped_cycles = 0;
	uint64_t uffd_copy_cycles = 0;
	for (i = 0; i < SAMPLES; i++) {
		p = rmalloc(PAGE_SIZE);	/*rmalloc keeps it page-aligned*/
		if (p == NULL) {
			perror("kona rmalloc failed");
			return 1;
		}

		/*measure when page is not mapped*/
		page_mapped = false;
		start = rdtsc();
		r = prefetch_page(p);
		duration = rdtsc() - start;
		ASSERT(page_mapped == (r == 0));
		page_not_mapped_cycles += duration;

		/*map the page*/
		start = rdtsc();
		r = uffd_plug_page_at((unsigned long)p);
		duration = rdtsc() - start;
		if (r != 0)
			return 1;
		uffd_copy_cycles += duration;

		/*measure after page is mapped*/
		page_mapped = true;
		start = rdtsc();
		r = prefetch_page(p);
		duration = rdtsc() - start;
		ASSERT(page_mapped == (r == 0));
		page_mapped_cycles += duration;
	}

	printf("=================== RESULT ====================\n");
	printf("Prefetch page time (on hit): %lu cycles, %.2lf µs\n", 
		page_mapped_cycles / SAMPLES,
		page_mapped_cycles * 1.0 / (SAMPLES * cycles_per_us));
	printf("Prefetch page time (on miss): %lu cycles, %.2lf µs\n", 
		page_not_mapped_cycles / SAMPLES,
		page_not_mapped_cycles * 1.0 / (SAMPLES * cycles_per_us));
	printf("UFFD copy time (page mapping): %lu cycles, %.2lf µs\n", 
		uffd_copy_cycles / SAMPLES,
		uffd_copy_cycles * 1.0 / (SAMPLES * cycles_per_us));
	printf("==============================================\n");

	return 0;
}
