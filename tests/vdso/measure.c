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
#include "parse_vdso.h"

const char *version = "LINUX_2.6";
const char *name_mapped = "__vdso_is_page_mapped";
const char *name_wp = "__vdso_is_page_mapped_and_wrprotected";
typedef long (*vdso_check_page_t)(const void *p);
static vdso_check_page_t is_page_mapped;
static vdso_check_page_t is_page_mapped_and_wrprotected;
#define SUCCESS 0

uint64_t cycles_per_us;

int main(int argc, char **argv)
{
	unsigned long sysinfo_ehdr;
	char *p;
	bool page_mapped;
	int i, r, retries, mode;
	const int SAMPLES = 100;
	uint64_t start, duration;

	/*init*/
	cycles_per_us = time_calibrate_tsc();
	ASSERT(cycles_per_us);

	/*find prefetch_page vDSO symbol*/
	sysinfo_ehdr = getauxval(AT_SYSINFO_EHDR);
	if (!sysinfo_ehdr) {
		printf("[ERROR]\tAT_SYSINFO_EHDR is not present!\n");
		return 1;
	}

	vdso_init_from_sysinfo_ehdr(getauxval(AT_SYSINFO_EHDR));
	is_page_mapped = (vdso_check_page_t)vdso_sym(version, name_mapped);
	if (!is_page_mapped) {
		printf("[ERROR]\tCould not find %s in vdso\n", name_mapped);
		return 1;
	}
	is_page_mapped_and_wrprotected = (vdso_check_page_t)vdso_sym(version, name_wp);
	if (!is_page_mapped_and_wrprotected) {
		printf("[ERROR]\tCould not find %s in vdso\n", name_wp);
		return 1;
	}

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

	uint64_t page_map_hit_cycles = 0;
	uint64_t page_map_miss_cycles = 0;
	uint64_t page_wp_hit_cycles = 0;
	uint64_t page_wp_miss_no_page_cycles = 0;
	uint64_t page_wp_miss_cycles = 0;
	uint64_t page_not_mapped_cycles = 0;
	uint64_t uffd_copy_cycles = 0;
	uint64_t uffd_wp_cycles = 0;
	for (i = 0; i < SAMPLES; i++) {
		p = (void*)(reg->addr + i*PAGE_SIZE);
		if (p == NULL) {
			perror("kona rmalloc failed");
			return 1;
		}

		/* page is not mapped; both vdso calls should miss */
		start = rdtsc();
		r = is_page_mapped(p);
		ASSERT(!r);
		duration = rdtscp(NULL) - start;
		page_map_miss_cycles += duration;

		start = rdtsc();
		r = is_page_mapped_and_wrprotected(p);
		ASSERT(!r);
		duration = rdtscp(NULL) - start;
		page_wp_miss_no_page_cycles += duration;

		/* map the page with write-protect on */
		void* page_buf = malloc(PAGE_SIZE);
		start = rdtsc();
		mode = UFFDIO_COPY_MODE_DONTWAKE | UFFDIO_COPY_MODE_WP;
		r = uffd_copy(uffd_info.userfault_fd, (unsigned long)p, 
			(unsigned long) page_buf, mode, true, &retries, false);
		ASSERTZ(r); /* plugging uffd page failed */
		duration = rdtsc() - start;
		uffd_copy_cycles += duration;

		/* page is mapped but still write-protected */
		start = rdtsc();
		r = is_page_mapped(p);
		ASSERT(r);
		duration = rdtsc() - start;
		page_map_hit_cycles += duration;

		start = rdtsc();
		r = is_page_mapped_and_wrprotected(p);
		ASSERT(!r);
		duration = rdtsc() - start;
		page_wp_miss_cycles += duration;

		/* remove write protection */
		start = rdtsc();
		mode = 0;
		r = uffd_wp(uffd_info.userfault_fd, (unsigned long)p, 
			PAGE_SIZE, mode, true, &retries);
		ASSERTZ(r); /* uffd wp failed */
		duration = rdtsc() - start;
		uffd_wp_cycles += duration;

		// /* wp removed */
		*(uint64_t*)p = (uint64_t)-1;
		start = rdtsc();
		r = is_page_mapped_and_wrprotected(p);
		ASSERT(r);
		/* make sure the check doesn't corrupt the page */
		ASSERT(*(uint64_t*)p == (uint64_t)-1);
		duration = rdtsc() - start;
		page_wp_hit_cycles += duration;
	}

	printf("=================== RESULT ====================\n");
	printf("is_page_mapped (hit): \t\t\t\t %lu cycles \t %.2lf µs\n", 
		page_map_hit_cycles / SAMPLES,
		page_map_hit_cycles * 1.0 / (SAMPLES * cycles_per_us));
	printf("is_page_mapped (miss):  \t\t\t %lu cycles \t %.2lf µs\n", 
		page_map_miss_cycles / SAMPLES,
		page_map_miss_cycles * 1.0 / (SAMPLES * cycles_per_us));
	printf("is_page_mapped_and_wp (hit):  \t\t\t %lu cycles \t %.2lf µs\n", 
		page_wp_hit_cycles / SAMPLES,
		page_wp_hit_cycles * 1.0 / (SAMPLES * cycles_per_us));
	printf("is_page_mapped_and_wp (miss - no page):  \t %lu cycles \t %.2lf µs\n", 
		page_wp_miss_no_page_cycles / SAMPLES,
		page_wp_miss_no_page_cycles * 1.0 / (SAMPLES * cycles_per_us));
	printf("is_page_mapped_and_wp (miss - wprotected):  \t %lu cycles \t %.2lf µs\n", 
		page_wp_miss_cycles / SAMPLES,
		page_wp_miss_cycles * 1.0 / (SAMPLES * cycles_per_us));
	printf("UFFD copy time (page mapping): \t\t\t %lu cycles \t %.2lf µs\n", 
		uffd_copy_cycles / SAMPLES,
		uffd_copy_cycles * 1.0 / (SAMPLES * cycles_per_us));
	printf("UFFD wp time (page write-protecting): \t\t %lu cycles \t %.2lf µs\n", 
		uffd_wp_cycles / SAMPLES,
		uffd_wp_cycles * 1.0 / (SAMPLES * cycles_per_us));
	printf("==============================================\n");

	return 0;
}
