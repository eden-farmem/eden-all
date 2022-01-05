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

#include "kselftest.h"
#include "parse_vdso.h"
#include "klib.h"
#include <linux/userfaultfd.h>

const char *version = "LINUX_2.6";
const char *name = "__vdso_prefetch_page";

struct getcpu_cache;
typedef long (*prefetch_page_t)(const void *p);

#define MEM_SIZE_K	(9500000ull) /* how was this chosen? */
#define PAGE_SIZE	(4096ull)

#define SKIP_MINCORE_BEFORE	(1 << 0)
#define SKIP_MINCORE_AFTER	(1 << 1)

static prefetch_page_t prefetch_page;
extern int mr_mgr_userfault_fd;

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
					return KSFT_FAIL;
				}
			} else {
				printf("uffd_copy errno=%d: unhandled error\n", errno);
				return KSFT_FAIL;
			}
		}
	} while (r && errno == EAGAIN);
	return 0;
}

int main(int argc, char **argv)
{
	unsigned long sysinfo_ehdr;
	long ret, i, test_ret = 0;
	int fd, drop_fd;
	char *p, vec;
	bool expect_io;

	printf("[RUN]\tTesting vdso_prefetch_page\n");

	rinit();

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

	expect_io = false;
	test_prefetch(NULL, expect_io, "NULL access", 
		SKIP_MINCORE_BEFORE|SKIP_MINCORE_AFTER);

	test_prefetch(name, true, "present", 0);

	p = rmalloc(PAGE_SIZE);	/*rmalloc keeps it page-aligned*/
	if (p == NULL) {
		perror("kona rmalloc at anon kona prefetch");
		return KSFT_FAIL;
	}
	*p = 'a'; //bring in the page, we are testing page-present case
	expect_io = true;

	/*
	 * Mincore would not tell us that no I/O is needed to retrieve the page,
	 * so tell test_prefetch() to skip it.
	 */
	test_prefetch(p, expect_io, "anon prefetch", SKIP_MINCORE_BEFORE);

	p = rmalloc(PAGE_SIZE);	/*new page*/
	if (p == NULL) {
		perror("kona rmalloc at Minor-fault anon prefetch");
		return KSFT_FAIL;
	}
	/*With Kona, page is not allocated until first access so first 
	 *access should expect io*/
	expect_io = false;
	test_prefetch(p, false, "Minor-fault (io) anon prefetch", 0);

	/*bring in page*/
	ret = uffd_plug_page_at((unsigned long)p);
	if (ret != 0)
		return KSFT_FAIL;

	expect_io = true;
	test_prefetch(p, expect_io, "Minor-fault (cached) anon prefetch", false);

	printf("[PASS]\tvdso_prefetch_page\n");
	return 0;
}
