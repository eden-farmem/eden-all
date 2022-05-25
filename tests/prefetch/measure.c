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

#define USE_PREFETCH
#ifdef USE_PREFETCH 
#include "parse_vdso.h"
#endif

#ifdef USE_PREFETCH 
const char *version = "LINUX_2.6";
const char *name = "__vdso_prefetch_page";
typedef long (*prefetch_page_t)(const void *p);
static prefetch_page_t prefetch_page;
#endif

uint64_t cycles_per_us;

int main(int argc, char **argv)
{
	unsigned long sysinfo_ehdr;
	char *p;
	bool page_mapped;
	int i, r, retries;
	const int SAMPLES = 100;
	uint64_t start, duration;

	/*init*/
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

	/*create/register uffd region*/
	int writeable = 1;
	struct uffd_region_t* reg = create_uffd_region(SAMPLES * PAGE_SIZE, writeable);
	ASSERT(reg != NULL);
	ASSERT(reg->addr);
	r = uffd_register(uffd_info.userfault_fd, reg->addr, reg->size, writeable);
	ASSERTZ(r);

	/* NOTE: While we registered a uffd region, we don't have a manager 
	 * handling uffd events from the kernel in this test. Any access to uffd 
	 * region will trigger such an event so we can't do any direct access.
	 * Prefetch_page access won't trigger this event so we're fine. */

	uint64_t page_mapped_cycles = 0;
	uint64_t page_not_mapped_cycles = 0;
	uint64_t uffd_copy_cycles = 0;
	for (i = 0; i < SAMPLES; i++) {
		p = (void*)(reg->addr + i*PAGE_SIZE);
		if (p == NULL) {
			perror("kona rmalloc failed");
			return 1;
		}

		/*measure when page is not mapped*/
		page_mapped = false;
		start = rdtsc();
		r = prefetch_page(p);
		ASSERT(page_mapped == (r == 0));
		duration = rdtscp(NULL) - start;
		page_not_mapped_cycles += duration;

		/*map the page*/
		void* page_buf = malloc(PAGE_SIZE);
		start = rdtsc();
		r = uffd_copy(uffd_info.userfault_fd, (unsigned long)p, 
			(unsigned long) page_buf, 0, true, &retries, false);
		// r = uffd_zero(uffd_info.userfault_fd, (unsigned long)p, 
		// 	PAGE_SIZE, true, &retries);
		ASSERTZ(r); /* plugging uffd page failed */
		duration = rdtsc() - start;
		uffd_copy_cycles += duration;

		/*measure after page is mapped*/
		page_mapped = true;
		start = rdtsc();
		r = prefetch_page(p);
		ASSERT(page_mapped == (r == 0));
		duration = rdtsc() - start;
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
