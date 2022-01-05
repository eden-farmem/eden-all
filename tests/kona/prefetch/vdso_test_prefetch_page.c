// Original source: Linux selftest from Nadav Amit's patch
// https://lore.kernel.org/lkml/20210225072910.2811795-4-namit@vmware.com/

// SPDX-License-Identifier: GPL-2.0-only
/*
 * vdso_test_prefetch_page.c: Test vDSO's prefetch_page())
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

#include "kselftest.h"
#include "parse_vdso.h"

const char *version = "LINUX_2.6";
const char *name = "__vdso_prefetch_page";

struct getcpu_cache;
typedef long (*prefetch_page_t)(const void *p);

#define MEM_SIZE_K	(9500000ull)
#define PAGE_SIZE	(4096ull)

#define SKIP_MINCORE_BEFORE	(1 << 0)
#define SKIP_MINCORE_AFTER	(1 << 1)

static prefetch_page_t prefetch_page;

static const void *ptr_align(const void *p)
{
	return (const void *)((unsigned long)p & ~(PAGE_SIZE - 1));
}


static int __test_prefetch(const void *p, bool expected_no_io,
			   const char *test_name, unsigned int skip_mincore)
{
	bool no_io;
	char vec;
	long r;
	uint64_t start;

	p = ptr_align(p);

	/*
	 * First, run a sanity check to use mincore() to see if the page is in
	 * memory when we expect it not to be.  We can only trust mincore to
	 * tell us when a page is already in memory when it should not be.
	 */
	if (!(skip_mincore & SKIP_MINCORE_BEFORE)) {
		if (mincore((void *)p, PAGE_SIZE, &vec)) {
			printf("[SKIP]\t%s: mincore failed: %s\n", test_name,
			       strerror(errno));
			return 0;
		}

		no_io = vec & 1;
		if (!skip_mincore && no_io && !expected_no_io) {
			printf("[SKIP]\t%s: unexpected page state: %s\n",
			       test_name,
			       no_io ? "in memory" : "not in memory");
			return 0;
		}
	}

	/*
	 * Check we got the expected result from prefetch page.
	 */
	r = prefetch_page(p);

	no_io = r == 0;
	if (no_io != expected_no_io) {
		printf("[FAIL]\t%s: prefetch_page() returned %ld\n",
			       test_name, r);
		return KSFT_FAIL;
	}

	if (skip_mincore & SKIP_MINCORE_AFTER)
		return 0;

	/*
	 * Check again using mincore that the page state is as expected.
	 * A bit racy. Skip the test if mincore fails.
	 */
	if (mincore((void *)p, PAGE_SIZE, &vec)) {
		printf("[SKIP]\t%s: mincore failed: %s\n", test_name,
		       strerror(errno));
		return 0;
	}

	no_io = vec & 1;
	if (0 && no_io != expected_no_io) {
		printf("[FAIL]\t%s: mincore reported page is %s\n",
			       test_name, no_io ? "in memory" : "not in memory");
		return KSFT_FAIL;

	}
	return 0;
}

#define test_prefetch(p, expected_no_io, test_name, skip_mincore)	\
	do {								\
		long _r = __test_prefetch(p, expected_no_io,		\
					  test_name, skip_mincore);	\
									\
		if (_r)							\
			return _r;					\
	} while (0)

static void wait_for_io_completion(const void *p)
{
	char vec;
	int i;

	/* Wait to allow the I/O to complete */
	p = ptr_align(p);

	vec = 0;

	/* Wait for 5 seconds and keep probing the page to get it */
	for (i = 0; i < 5000; i++) {
		if (mincore((void *)p, PAGE_SIZE, &vec) == 0 && (vec & 1))
			break;
		prefetch_page(p);
		usleep(1000);
	}
}

int main(int argc, char **argv)
{
	unsigned long sysinfo_ehdr;
	long ret, i, test_ret = 0;
	int fd, drop_fd;
	char *p, vec;

	printf("[RUN]\tTesting vdso_prefetch_page\n");

	sysinfo_ehdr = getauxval(AT_SYSINFO_EHDR);
	if (!sysinfo_ehdr) {
		printf("[SKIP]\tAT_SYSINFO_EHDR is not present!\n");
		return KSFT_SKIP;
	}

	vdso_init_from_sysinfo_ehdr(getauxval(AT_SYSINFO_EHDR));

	prefetch_page = (prefetch_page_t)vdso_sym(version, name);
	if (!prefetch_page) {
		printf("[SKIP]\tCould not find %s in vdso\n", name);
		return KSFT_SKIP;
	}

	test_prefetch(NULL, false, "NULL access",
		      SKIP_MINCORE_BEFORE|SKIP_MINCORE_AFTER);

	test_prefetch(name, true, "present", 0);

	p = mmap(0, PAGE_SIZE, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
	if (p == MAP_FAILED) {
		perror("mmap anon");
		return KSFT_FAIL;
	}

	/*
	 * Mincore would not tell us that no I/O is needed to retrieve the page,
	 * so tell test_prefetch() to skip it.
	 */
	test_prefetch(p, true, "anon prefetch", SKIP_MINCORE_BEFORE);

	/* Drop the caches before testing file mmap */
	drop_fd = open("/proc/sys/vm/drop_caches", O_WRONLY);
	if (drop_fd < 0) {
		perror("open /proc/sys/vm/drop_caches");
		return KSFT_FAIL;
	}

	sync();
	ret = write(drop_fd, "3", 1);
	if (ret != 1) {
		perror("write to /proc/sys/vm/drop_caches");
		return KSFT_FAIL;
	}

	/* close, which would also flush */
	ret = close(drop_fd);
	if (ret) {
		perror("close /proc/sys/vm/drop_caches");
		return KSFT_FAIL;
	}

	/* Using /etc/passwd as a file that should alway exist */
	fd = open("/etc/hosts", O_RDONLY);
	if (fd < 0) {
		perror("open /etc/passwd");
		return KSFT_FAIL;
	}

	p = mmap(0, PAGE_SIZE, PROT_READ, MAP_SHARED, fd, 0);
	if (p == MAP_FAILED) {
		perror("mmap file");
		return KSFT_FAIL;
	}

	test_prefetch(p, false, "Minor-fault (io) file prefetch", 0);

	wait_for_io_completion(p);

	test_prefetch(p, true, "Minor-fault (cached) file prefetch", 0);

	munmap(p, PAGE_SIZE);

	/*
	 * Try to lock all to avoid unrelated page-faults before we create
	 * memory pressure to prevent unrelated page-faults.
	 */
	mlockall(MCL_CURRENT);

	p = mmap(0, 1024 * MEM_SIZE_K, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANON, -1, 0);
	if (p == MAP_FAILED) {
		perror("mmap file");
		return KSFT_FAIL;
	}

	/*
	 * Write random value to avoid try to prevent KSM from deduplicating
	 * this page.
	 */
	*(volatile unsigned long *)p = 0x43454659;
	ret = madvise(p, PAGE_SIZE, MADV_PAGEOUT);
	if (ret != 0) {
		perror("madvise(MADV_PAGEOUT)");
		return KSFT_FAIL;
	}

	/* Wait to allow the page-out to complete */
	usleep(2000000);

	/* Cause some memory pressure */
	for (i = PAGE_SIZE; i < MEM_SIZE_K * 1024; i += PAGE_SIZE)
		*(volatile unsigned long *)((unsigned long)p + i) = i + 1;

	/* Check if we managed to evict the page */
	ret = mincore(p, PAGE_SIZE, &vec);
	if (ret != 0) {
		perror("mincore");
		return KSFT_FAIL;
	}

	test_prefetch(p, false, "Minor-fault (io) anon prefetch", 0);
	wait_for_io_completion(p);

	test_prefetch(p, true, "Minor-fault (cached) anon prefetch", false);

	printf("[PASS]\tvdso_prefetch_page\n");
	return 0;
}
