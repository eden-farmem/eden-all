/*
 * Userfaultfd Page Ops Benchmarks 
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
#include <sys/syscall.h>
#include <sys/ioctl.h>
#include <errno.h>
#include <stdlib.h>
#include <time.h>
#include <linux/userfaultfd.h>
#include <sys/uio.h>       /* Definition of struct iovec type */

#include "utils.h"
#include "logging.h"
#include "config.h"
#include "ops.h"
#include "uffd.h"

#define GIGA 				(1ULL << 30)
#define PHY_CORES_PER_NODE 	14
#define MAX_CORES 			(2*PHY_CORES_PER_NODE) /* cores per numa node */
#define MAX_THREADS 		(MAX_CORES-1)
#define MAX_FDS				MAX_THREADS
#define RUNTIME_SECS 		10
#define NO_TIMEOUT 			-1
#define NPAGE_ACCESSES 		10
#ifndef BATCH_SIZE
#define BATCH_SIZE 			1
#endif
#define NSTRIPS				BATCH_SIZE

/* max I could register with a single uffd region. note that this goes across 
 * numa domains which may affect the numbers */
#define MAX_MEMORY 			(160*GIGA)
#define MAX_MEM_PER_THREAD 	(20*GIGA)

uint64_t cycles_per_us;
pthread_barrier_t ready;
const int NODE0_CORES[MAX_CORES] = {
    0,  1,  2,  3,  4,  5,  6, 
    7,  8,  9,  10, 11, 12, 13, 
    28, 29, 30, 31, 32, 33, 34, 
    35, 36, 37, 38, 39, 40, 41 };
const int NODE1_CORES[MAX_CORES] = {
    14, 15, 16, 17, 18, 19, 20, 
    21, 22, 23, 24, 25, 26, 27, 
    42, 43, 44, 45, 46, 47, 48, 
    49, 50, 51, 52, 53, 54, 55 };
#define CORELIST NODE0_CORES
#define HYPERTHREAD_OFFSET 14
int start_button = 0, stop_button = 0;
int pidfd;

enum app_op {
	OP_MAP_PAGE_WP,
	OP_MAP_PAGE_WP_NO_WAKE,
	OP_MAP_PAGE_NO_WP,
	OP_MAP_PAGE_NO_WP_NO_WAKE,
	OP_PROTECT_PAGE,
	OP_PROTECT_PAGE_VEC,
	OP_UNPROTECT_PAGE,
	OP_UNPROTECT_PAGE_VEC,
	OP_UNPROTECT_PAGE_NO_WAKE,
	OP_UNMAP_PAGE,					/* madvise DONT_NEED */
	OP_UNMAP_PAGE_VEC,				/* process_madvise DONT_NEED */
	OP_ACCESS_PAGE,
	OP_ACCESS_PAGE_WHOLE,
};

struct thread_data {
	int uffd;
    int tid;
	int core;
	enum app_op optype;
    struct rand_state rs;
	uint64_t range_start;
	uint64_t range_len;
	uint64_t prev_stripe_size;
	int ops;
	int errors;
	unsigned long time_tsc;
} CACHE_ALIGN;

struct handler_data {
    int tid;
	int core;
	int ops;
	int errors;
	int uffds[MAX_FDS];
	int nfds;
	/* allocating some per-thread data here to make sure  
	 * they go in different cachelines. easier than ensuring 
	 * that malloc'd data from different threads goes on 
	 * separate cachelines */
	struct pollfd evt[MAX_FDS];	
} CACHE_ALIGN;

/* create and register uffd region */
struct uffd_region_t *create_uffd_region(int uffd, size_t size, int writeable)
{
	void *ptr = NULL;
	size_t page_flags_size;
	int r;

	/* allocate a new region_t object */
	struct uffd_region_t *mr = (struct uffd_region_t *)mmap(
		NULL, sizeof(struct uffd_region_t), PROT_READ | PROT_WRITE,
		MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	mr->size = size;

	/* mmap */
	int mmap_flags = MAP_PRIVATE | MAP_ANONYMOUS;
	if (writeable)
		ptr = mmap(NULL, mr->size, PROT_READ | PROT_WRITE, mmap_flags, -1, 0);
	else
		ptr = mmap(NULL, mr->size, PROT_READ, mmap_flags, -1, 0);

	if (ptr == MAP_FAILED) {
		pr_debug_err("mmap failed");
		return NULL;
	}
	mr->addr = (unsigned long)ptr;
	pr_debug("mmap ptr %p addr mr %p, size %ld\n", 
		ptr, (void *)mr->addr, mr->size);

	/* register */
	r = uffd_register(uffd, mr->addr, mr->size, writeable);
	if (r < 0)
		return NULL;

	return mr;
}

/* perform an operation */
int perform_app_op(int uffd, enum app_op optype, struct iovec* iov, int niov,
	unsigned long page_buf, uint64_t offsets[])
{
	int i, j, x, r = 0, retries;
	ssize_t ret;

	/* vectored ops */
	switch(optype) {
		case OP_UNMAP_PAGE_VEC:
			x = *(int*) iov[0].iov_base;	/* access before remove */
			/* FIXME: hardcoded syscall number, need to rebuild glibc */
			ret = syscall(440, pidfd, iov, niov, MADV_DONTNEED, 0);
			if(ret != niov * PAGE_SIZE) {
				pr_err("syscall returned %ld expected %llu, errno %d", 
					ret, niov * PAGE_SIZE, errno);
				BUG();
			}
			return 0;
		case OP_PROTECT_PAGE_VEC:
			r = uffd_wp_vec(uffd, iov, niov, true, false, true, 
				&retries, &ret);
			if (r == 0 && ret != niov * PAGE_SIZE) {
				pr_err("uffd_wp_vec returned %ld expected %llu, errno %d", 
					ret, niov * PAGE_SIZE, errno);
				BUG();
			}
			return r;
		case OP_UNPROTECT_PAGE_VEC:
			r = uffd_wp_vec(uffd, iov, niov, false, false, true, 
				&retries, &ret);
			if (r == 0 && ret != niov * PAGE_SIZE) {
				pr_err("uffd_wp_vec returned %ld expected %llu, errno %d", 
					ret, niov * PAGE_SIZE, errno);
				BUG();
			}
			if (r == 0)
				*(int*) iov[0].iov_base = 0;	/* check */
			return r;
		default:
			break;
	}

	/* non-vectored ops */
	for (i = 0; i < niov; i++) {
		switch(optype) {
			case OP_MAP_PAGE_WP:
				r |= uffd_copy(uffd, (unsigned long) iov[i].iov_base,
					page_buf, iov[i].iov_len, 1, 0, true, &retries);
				break;
			case OP_MAP_PAGE_WP_NO_WAKE:
				r |= uffd_copy(uffd, (unsigned long) iov[i].iov_base,
					page_buf, iov[i].iov_len, 1, 1, true, &retries);
				break;
			case OP_MAP_PAGE_NO_WP:
				r |= uffd_copy(uffd, (unsigned long) iov[i].iov_base,
					page_buf, iov[i].iov_len, 0, 0, true, &retries);
				break;
			case OP_MAP_PAGE_NO_WP_NO_WAKE:
				r |= uffd_copy(uffd, (unsigned long) iov[i].iov_base,
					page_buf, iov[i].iov_len, 0, 1, true, &retries);
				break;
			case OP_UNMAP_PAGE:
				x = *(int*) iov[i].iov_base;	/* access before remove */
				r |= madvise(iov[i].iov_base, iov[i].iov_len, MADV_DONTNEED);
				break;
			case OP_PROTECT_PAGE:
				r |= uffd_wp(uffd, (unsigned long) iov[i].iov_base, 
					iov[i].iov_len, 1, 0, true, &retries);
				break;
			case OP_UNPROTECT_PAGE:
				r |= uffd_wp(uffd, (unsigned long) iov[i].iov_base, 
					iov[i].iov_len, 0, 0, true, &retries);
				*(int*) iov[i].iov_base = 0;	/* check */
				break;
			case OP_UNPROTECT_PAGE_NO_WAKE:
				r |= uffd_wp(uffd, (unsigned long) iov[i].iov_base, 
					iov[i].iov_len, 0, 1, true, &retries);
				break;
			case OP_ACCESS_PAGE:
				x = *(int*) iov[i].iov_base;
				r |= 0;
				break;
			case OP_ACCESS_PAGE_WHOLE:
				for(j = 0; j < NPAGE_ACCESSES; j++) {
					ASSERT(offsets[j] < iov[i].iov_len);
					r = *(int*)(iov[i].iov_base + offsets[j]);
				}
				r |= 0;
				break;
			default:
				printf("unhandled app op: %d\n", optype);
				ASSERT(0);
		}
	}
	return r;
}

/* main for measuring threads */
void* app_main(void* args)
{
    struct thread_data * tdata = (struct thread_data *)args;
    ASSERTZ(pin_thread(tdata->core));
    int self = tdata->tid;
	int i, r, retries, uffd_mode, npages;
	void *p = (void*)tdata->range_start; 
	struct iovec iovs[BATCH_SIZE];
	ssize_t ret;
	size_t stripe_size = tdata->range_len / NSTRIPS;
	size_t strip_offset = 0, offset;
	int cur_strip = 0;
	void *page_buf = malloc(PAGE_SIZE);
	uint64_t offsets[NPAGE_ACCESSES];
	size_t max_stripe_size = (tdata->prev_stripe_size != 0) ?
		tdata->prev_stripe_size : stripe_size;
	unsigned long start_tsc;
	
	/* random page accesses */
	for (i = 0; i < NPAGE_ACCESSES; i++)
		offsets[i] = rand_next(&tdata->rs) % 
			(PAGE_SIZE * BATCH_SIZE - sizeof(int));

	r = pthread_barrier_wait(&ready);	/*signal ready*/
    ASSERT(r != EINVAL);

	while(!start_button)	cpu_relax();

	start_tsc = rdtsc();
	while(!stop_button && strip_offset < max_stripe_size) {
		/* prepare batch */
		npages = 0;
		for (i = 0; i < BATCH_SIZE; i++) {
			offset = stripe_size * cur_strip + strip_offset;
			BUG_ON(offset >= tdata->range_len);
			iovs[i].iov_base = (void*) (tdata->range_start + offset);
			iovs[i].iov_len = PAGE_SIZE;
			cur_strip++;
			if (cur_strip == NSTRIPS) {
				cur_strip = 0;
				strip_offset += PAGE_SIZE;
			}
			npages++;
		}

		/* execute batch */
		r = perform_app_op(tdata->uffd, tdata->optype, iovs, npages, 
			(unsigned long) page_buf, offsets);

		if (r)	tdata->errors++;
		else tdata->ops += npages;

#ifdef DEBUG
		if (tdata->ops +  tdata->errors >= 10)
			break;
#endif
	}

	/* record time */
	tdata->time_tsc = rdtscp(NULL) - start_tsc;

	/* update range to where we reached for next iteration */
	tdata->prev_stripe_size = strip_offset;
}

uint64_t do_app_work(enum app_op optype, int nthreads, 
	struct thread_data* tdata, int starting_core, uint64_t* errors, 
	uint64_t* latencyns, int* memory_covered_gb, int nsecs)
{
	int i, r;
	uint64_t start, duration, xput;
	double duration_secs, time_secs;
	int coreidx = starting_core;
	unsigned long time_tsc;
	unsigned long covered;

	/* spawn threads */
	pthread_t threads[MAX_THREADS];
	for(i = 0; i < nthreads; i++) {
		tdata[i].tid = i;
		ASSERTZ(rand_seed(&tdata[i].rs, time(NULL) ^ i));
        ASSERT(coreidx < MAX_CORES);
        tdata[i].core = CORELIST[coreidx++];
		tdata[i].optype = optype;
		tdata[i].ops = tdata[i].errors = 0;
        pthread_create(&threads[i], NULL, app_main, (void*)&tdata[i]);
	}
	stop_button = 0;
	r = pthread_barrier_wait(&ready);	/*until all threads ready*/
    ASSERT(r != EINVAL);
	
	/* start work */
	start = rdtsc();
	start_button = 1;
	if (nsecs > 0) {
		do {
			duration = rdtscp(NULL) - start;
			duration_secs = duration / (1000000.0 * cycles_per_us);
		} while(duration_secs <= nsecs);
		stop_button = 1;
	}

	/* wait for threads to finish */
	for(i = 0; i < nthreads; i++)
		pthread_join(threads[i], NULL);

	/* gather results */
	xput = 0;
	time_tsc = 0;
	*errors = 0;
	covered = 0;
	for (i = 0; i < nthreads; i++) {
		xput += tdata[i].ops;
		*errors += tdata[i].errors;
		covered += tdata[i].prev_stripe_size * NSTRIPS;
		if (time_tsc < tdata[i].time_tsc)
			time_tsc = tdata[i].time_tsc;
	}
	time_secs = time_tsc / (1000000.0 * cycles_per_us);
	xput /= time_secs;
	pr_debug("ran for %.2f secs, xput: %lu ops/sec, covered %llu gb", 
		time_secs, xput, covered / GIGA);
	
	/* latency seen by any one core */
	if (latencyns)
		*latencyns = tdata[0].ops > 0 ?
			tdata[0].time_tsc * 1000 / (cycles_per_us * tdata[0].ops) : 0;
	if (memory_covered_gb)
		*memory_covered_gb = covered / GIGA;
	return xput;
}

/* main for fault handling threads */
void* handler_main(void* args) {
    struct handler_data * hdata = (struct handler_data *)args;
    ASSERTZ(pin_thread(hdata->core));
    int self = hdata->tid;
	int i, r, retries, fdnow = 0;

	for (i = 0; i < hdata->nfds; i++) {
		hdata->evt[i].fd = hdata->uffds[i];
		hdata->evt[i].events = POLLIN;
		pr_debug("handler %d listening on fd: %d", self, hdata->uffds[i]);
	}
	ssize_t read_size;
	struct uffd_msg msg;
	unsigned long ip;

	while (true) {
		fdnow = (fdnow + 1) % hdata->nfds;
      	if (poll(&hdata->evt[fdnow], 1, 0) > 0) {
			pr_debug("handler %d found a pending event %d:%d:%d", self, 
				hdata->evt[fdnow].fd, hdata->evt[fdnow].events,
				hdata->evt[fdnow].revents);

			/* handle unexpected poll events */
			ASSERT((hdata->evt[fdnow].revents & POLLERR) == 0);
			ASSERT((hdata->evt[fdnow].revents & POLLHUP) == 0);

			/* read fault */
        	read_size = read(hdata->evt[fdnow].fd, &msg, sizeof(struct uffd_msg));
			pr_debug("handler %d read %ld bytes (errno %d) on fd %d", 
				self, read_size, errno, hdata->evt[fdnow].fd);
			if (read_size == -1) {
				/* EAGAIN is fine; another handler got to this message first */
				ASSERT(errno == EAGAIN);
				continue;
			}
			ASSERT(read_size == sizeof(struct uffd_msg));

			/* do something with the fault */
			switch (msg.event) {
				case UFFD_EVENT_PAGEFAULT:
					/* plugin a zero page */
					pr_debug("handler %d resolving fault %llu", 
						self, msg.arg.pagefault.address);
					r = uffd_zero(hdata->evt[fdnow].fd, 
						msg.arg.pagefault.address & PAGE_MASK, PAGE_SIZE, 
						true, &retries);
					ASSERT(r == 0);
					pr_debug("fault ip, addr: 0x%lx 0x%llx", (long) msg.ip,
						msg.arg.pagefault.address);
					break;
				case UFFD_EVENT_FORK:
				case UFFD_EVENT_REMAP:
				case UFFD_EVENT_REMOVE:
				case UFFD_EVENT_UNMAP:
				default:
					printf("ERROR! unhandled uffd event %d\n", msg.event);
					ASSERT(0);
    		}
      	}
    }
}

int main(int argc, char **argv)
{
	unsigned long sysinfo_ehdr;
	char *p;
	bool page_mapped;
	int i, j, r, nthreads;
	int handlers_per_fd, nhandlers, nuffd, handler_start_core;
	uint64_t start, duration;
	double duration_secs;
	size_t size;
	bool share_uffd = true;
	enum app_op op;
	int mem_gb;

	/* parse & validate args */
    if (argc > 4) {
        printf("Invalid args\n");
        printf("Usage: %s [nthreads] [share_uffd] [nhandlers]\n", argv[0]);
        printf("[nthreads]\t number of measuring threads/cores\n");
        printf("[share_uffd]\t whether to share a single fd across threads or have a dedicated fd per thread\n");
        printf("[nhandlers]\t number of handler threads to listen on uffds\n");
        return 1;
    }
    nthreads = (argc > 1) ? atoi(argv[1]) : 1;
	share_uffd = (argc > 2) ? atoi(argv[2]) : true;
	nhandlers = (argc > 3) ? atoi(argv[3]) : 1;
	ASSERT(nthreads > 0);
	ASSERT(nhandlers > 0);
	ASSERT(nthreads + nhandlers <= MAX_THREADS);
	// ASSERT(nthreads <= MAX_THREADS);
	// ASSERT(nhandlers <= MAX_THREADS);
	nuffd = share_uffd ? 1 : nthreads;
	ASSERT(nuffd < MAX_UFFD);
	ASSERT(nuffd < MAX_FDS);
	pr_debug("Running %s with %d threads, %d fds, %d handlers", 
		argv[0], nthreads, nuffd, nhandlers);

	/*init*/
    ASSERT(sizeof(struct thread_data) % CACHE_LINE_SIZE == 0);
    ASSERT(sizeof(struct handler_data) % CACHE_LINE_SIZE == 0);
	cycles_per_us = time_calibrate_tsc();
	ASSERT(cycles_per_us);
	pidfd = syscall(SYS_pidfd_open, getpid(), 0);
	ASSERT(pidfd >= 0);

	/*uffd init*/
	uffd_info.fd_count = 0;
	for(i = 0; i < nuffd; i++) {
		uffd_info.userfault_fds[i] = uffd_init();
		ASSERT(uffd_info.userfault_fds[i] >= 0);
		uffd_info.fd_count++;
		pr_debug("userfault-fd %d: %d\n", i, uffd_info.userfault_fds[i]);
	}

	/* main thread on core 0 */
	int coreidx = 0;
	pin_thread(coreidx++);	

#if defined(ACCESS_PAGE) || defined(ACCESS_PAGE_WHOLE)
	/* start fault handler threads. don't access pages without enabling handlers */
    struct handler_data hdata[MAX_THREADS] CACHE_ALIGN = {0};
	int hcoreidx = 0;
	handler_start_core = coreidx;
	for(i = 0; i < nhandlers; i++) {
		hdata[i].tid = i;
        ASSERT(coreidx < MAX_CORES);
        hdata[i].core = CORELIST[coreidx++];
		hdata[i].nfds = 0;
	}

	/* assign fds among handlers */
	int hcount = 0, fdcount = 0, idx;
	bool hdone = false, fddone = false;
	while (!hdone || !fddone) {
		hdata[hcount].uffds[hdata[hcount].nfds++] = uffd_info.userfault_fds[fdcount];
		ASSERT(hdata[hcount].nfds < MAX_FDS);
		pr_debug("handler %d got fd %d", hcount, fdcount);
		hcount++;	fdcount++;
		if (hcount == nhandlers){ hdone = true;		hcount = 0;  }
		if (fdcount == nuffd)	{ fddone = true;	fdcount = 0; }
	}

	/* start handlers */
	pthread_t handlers[MAX_THREADS];
	for (i = 0; i < nhandlers; i++)
        pthread_create(&handlers[i], NULL, handler_main, (void*)&hdata[i]);
#endif
	
	/* create uffd regions */
	int fd, nregions;
	int writeable = 1;
#ifdef SHARE_REGION
	nregions = 1;
	ASSERT(share_uffd);		/* cannot have shared region over multiple fds */
#else
	nregions = nthreads;
#endif
	size = MAX_MEM_PER_THREAD * nthreads;
	ASSERT(size % PAGE_SIZE == 0);
	ASSERT(size <= MAX_MEMORY);
	struct uffd_region_t** reg = malloc(nregions*sizeof(struct uffd_region_t*));
	for (i = 0; i < nregions; i++) {
		fd = share_uffd ? uffd_info.userfault_fds[0] : uffd_info.userfault_fds[i];
		reg[i] = create_uffd_region(fd, size, writeable);
		ASSERT(reg[i] != NULL);
		ASSERT(reg[i]->addr);
		r = uffd_register(fd, reg[i]->addr, reg[i]->size, writeable);
		ASSERTZ(r);
	}

	/* create/register per-thread uffd regions */
	size_t size_per_thread = (nregions == 1) ? size / nthreads : size;
    struct thread_data tdata[MAX_THREADS] CACHE_ALIGN = {0};
	for(i = 0; i < nthreads; i++) {
		fd = share_uffd ? uffd_info.userfault_fds[0] : uffd_info.userfault_fds[i];
		tdata[i].uffd = fd;
		tdata[i].range_start = (nregions == 1) ? 
			reg[0]->addr + (i * size_per_thread) : reg[i]->addr;
		tdata[i].range_len = size_per_thread;
		tdata[i].prev_stripe_size = 0;
		pr_debug("thread %d working with region %d (%lu, %lu)", i, 
			(nregions == 1) ? 0 : i, tdata[i].range_start, tdata[i].range_len);
	}

	/* start measuring threads */
	uint64_t xput, errors, latns;
	ASSERTZ(pthread_barrier_init(&ready, NULL, nthreads + 1));
#if defined(MAP_PAGE)
	xput = do_app_work(OP_MAP_PAGE_NO_WP, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, RUNTIME_SECS);
#elif defined(MAP_PAGE_NOWAKE)
	xput = do_app_work(OP_MAP_PAGE_NO_WP_NO_WAKE, nthreads, tdata, coreidx, 
		&errors, &latns, &mem_gb, RUNTIME_SECS);
#elif defined(UNMAP_PAGE)
	/* map pages before unmapping them. currently map is faster than unmap 
	 * so we should have enough pages to unmap for a given run duration */
	do_app_work(OP_MAP_PAGE_NO_WP_NO_WAKE, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, NO_TIMEOUT);
	xput = do_app_work(OP_UNMAP_PAGE, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, RUNTIME_SECS);
#elif defined(UNMAP_PAGE_VEC)
	/* map pages before unmapping them. currently map is faster than unmap 
	 * so we should have enough pages to unmap for a given run duration */
	do_app_work(OP_MAP_PAGE_NO_WP_NO_WAKE, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, NO_TIMEOUT);
	xput = do_app_work(OP_UNMAP_PAGE_VEC, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, RUNTIME_SECS);
#elif defined(PROTECT_PAGE)
	/* map pages unprotected before protecting them */
	do_app_work(OP_MAP_PAGE_NO_WP_NO_WAKE, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, NO_TIMEOUT);
	xput = do_app_work(OP_PROTECT_PAGE, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, RUNTIME_SECS);
#elif defined(PROTECT_PAGE_VEC)
	/* map pages unprotected before protecting them */
	do_app_work(OP_MAP_PAGE_NO_WP_NO_WAKE, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, NO_TIMEOUT);
	xput = do_app_work(OP_PROTECT_PAGE_VEC, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, RUNTIME_SECS);
#elif defined(UNPROTECT_PAGE)
	/* map pages protected before unprotecting them */
	do_app_work(OP_MAP_PAGE_WP_NO_WAKE, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, NO_TIMEOUT);
	xput = do_app_work(OP_UNPROTECT_PAGE, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, RUNTIME_SECS);
#elif defined(UNPROTECT_PAGE_VEC)
	/* map pages protected before unprotecting them */
	do_app_work(OP_MAP_PAGE_WP_NO_WAKE, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, NO_TIMEOUT);
	xput = do_app_work(OP_UNPROTECT_PAGE_VEC, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, RUNTIME_SECS);
#elif defined(UNPROTECT_PAGE_NOWAKE)
	/* map pages protected before unprotecting them */
	do_app_work(OP_MAP_PAGE_WP_NO_WAKE, nthreads, tdata, coreidx, &errors, 
		&latns, &mem_gb, NO_TIMEOUT);
	xput = do_app_work(OP_UNPROTECT_PAGE_NO_WAKE, nthreads, tdata, coreidx, 
		&errors, &latns, &mem_gb, RUNTIME_SECS);
#elif defined(ACCESS_PAGE) || defined(ACCESS_PAGE_WHOLE)
	op = OP_ACCESS_PAGE;
#ifdef ACCESS_PAGE_WHOLE
	op = OP_ACCESS_PAGE_WHOLE;
#endif
	int app_start_core;
	#ifdef HT_HANDLERS
	ASSERT(nthreads == nhandlers);	/* only supported for this case */
	ASSERT(coreidx < HYPERTHREAD_OFFSET);	/* handlers should not spill over into hyperthreads */
	app_start_core = handler_start_core + HYPERTHREAD_OFFSET;
	/* check that there are enough threads left for app threads */
	ASSERT(nthreads <= (MAX_CORES - app_start_core));
	#else
	app_start_core = coreidx;
	/* guard against inadvertently hyperthreading handlers */
	ASSERT(app_start_core != handler_start_core + HYPERTHREAD_OFFSET);
	#endif
	xput = do_app_work(op, nthreads, tdata, app_start_core, &errors, 
		&latns, &mem_gb, RUNTIME_SECS);
#else
	printf("Unknown operation\n");
	return 1;
#endif

	printf("%d,%lu,%lu,%lu,%d\n", nthreads, xput, errors, latns, mem_gb);
	return 0;
}
