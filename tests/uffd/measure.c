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

#define GIGA 				(1ULL << 30)
#define PHY_CORES_PER_NODE 	14
#define MAX_CORES 			(2*PHY_CORES_PER_NODE)	/*logical cores per numa node*/
#define MAX_THREADS 		(MAX_CORES-1)
#define MAX_FDS				MAX_THREADS
#define MAX_MEMORY 			(160*GIGA)	/*max I could register with a single uffd region*/
#define RUNTIME_SECS 		10
#define NPAGE_ACCESSES 		10

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

enum app_op {
	OP_MAP_PAGE_WP,
	OP_MAP_PAGE_WP_NO_WAKE,
	OP_MAP_PAGE_NO_WP,
	OP_MAP_PAGE_NO_WP_NO_WAKE,
	OP_PROTECT_PAGE,
	OP_UNPROTECT_PAGE,
	OP_UNPROTECT_PAGE_NO_WAKE,
	OP_UNMAP_PAGE,
	OP_ACCESS_PAGE,
	OP_ACCESS_PAGE_WHOLE,
};

struct thread_data {
    int tid;
	int core;
    struct rand_state rs;
	uint64_t range_start;
	uint64_t range_len;
	int xput_ops;
	int errors;
	int uffd;
	enum app_op optype;
} CACHE_ALIGN;

struct handler_data {
    int tid;
	int core;
	int xput_ops;
	int errors;
	int uffds[MAX_FDS];
	int nfds;
	/* allocating some per-thread data here to make sure  
	 * they go in different cachelines. easier than ensuring 
	 * that malloc'd data from different threads goes on 
	 * separate cachelines */
	struct pollfd evt[MAX_FDS];	
} CACHE_ALIGN;

/* main for measuring threads */
void* app_main(void* args) {
    struct thread_data * tdata = (struct thread_data *)args;
    ASSERTZ(pin_thread(tdata->core));
    int self = tdata->tid;
	int i, r, retries, uffd_mode;
	void *p = (void*)tdata->range_start; 
	void *page_buf = malloc(PAGE_SIZE);
	
	uint64_t offsets[NPAGE_ACCESSES];
	for (i = 0; i < NPAGE_ACCESSES; i++)
		offsets[i] = rand_next(&tdata->rs) % (PAGE_SIZE - sizeof(int));

	r = pthread_barrier_wait(&ready);	/*signal ready*/
    ASSERT(r != EINVAL);

	while(!start_button)	cpu_relax();
	while(!stop_button) {
		p = (void*) page_align(p);
		switch(tdata->optype) {
			case OP_MAP_PAGE_WP:
				r = uffd_copy(tdata->uffd, (unsigned long)p,
					(unsigned long) page_buf, PAGE_SIZE, 1, 0, true, &retries);
				break;
			case OP_MAP_PAGE_WP_NO_WAKE:
				r = uffd_copy(tdata->uffd, (unsigned long)p,
					(unsigned long) page_buf, PAGE_SIZE, 1, 1, true, &retries);
				break;
			case OP_MAP_PAGE_NO_WP:
				r = uffd_copy(tdata->uffd, (unsigned long)p,
					(unsigned long) page_buf, PAGE_SIZE, 0, 0, true, &retries);
				break;
			case OP_MAP_PAGE_NO_WP_NO_WAKE:
				r = uffd_copy(tdata->uffd, (unsigned long)p,
					(unsigned long) page_buf, PAGE_SIZE, 0, 1, true, &retries);
				break;
			case OP_UNMAP_PAGE:
				r = *(int*)p;	/* access before removing */
				r = madvise(p, PAGE_SIZE, MADV_DONTNEED);
				break;
			case OP_PROTECT_PAGE:
				r = uffd_wp(tdata->uffd, (unsigned long)p, PAGE_SIZE, 1, 0, 
					true, &retries);
				break;
			case OP_UNPROTECT_PAGE:
				r = uffd_wp(tdata->uffd, (unsigned long)p, PAGE_SIZE, 0, 0, 
					true, &retries);
				break;
			case OP_UNPROTECT_PAGE_NO_WAKE:
				r = uffd_wp(tdata->uffd, (unsigned long)p, PAGE_SIZE, 0, 1, 
					true, &retries);
				break;
			case OP_ACCESS_PAGE:
				r = *(int*)p;
				r = 0;
				break;
			case OP_ACCESS_PAGE_WHOLE:
				for(i = 0; i < NPAGE_ACCESSES; i++)
					r = *(int*)(p+offsets[i]);
				r = 0;
				break;
			default:
				printf("unhandled app op: %d\n", tdata->optype);
				ASSERT(0);
		}
		if (r)	tdata->errors++;
		else tdata->xput_ops++;
		p += PAGE_SIZE;

		/* error if out of memory region*/
		if((uint64_t)p > (tdata->range_start + tdata->range_len))
			BUG();

#ifdef DEBUG
		break;
#endif
	}

	/*update range to where we reached for next iteration */
	tdata->range_len = (uint64_t)(p - PAGE_SIZE);
}

uint64_t do_app_work(enum app_op optype, int nthreads, struct thread_data* tdata, 
		int starting_core, uint64_t* errors, uint64_t* latencyns, int nsecs) {
	int i, r;
	uint64_t start, duration;
	double duration_secs;
	int coreidx = starting_core;

	/* spawn threads */
	pthread_t threads[MAX_THREADS];
	for(i = 0; i < nthreads; i++) {
		tdata[i].tid = i;
		ASSERTZ(rand_seed(&tdata[i].rs, time(NULL) ^ i));
        ASSERT(coreidx < MAX_CORES);
        tdata[i].core = CORELIST[coreidx++];
		tdata[i].optype = optype;
		tdata[i].xput_ops = tdata[i].errors = 0;
        pthread_create(&threads[i], NULL, app_main, (void*)&tdata[i]);
	}
	stop_button = 0;
	r = pthread_barrier_wait(&ready);	/*until all threads ready*/
    ASSERT(r != EINVAL);
	
	/* start work */
	start = rdtsc();
	start_button = 1;
	do {
		duration = rdtscp(NULL) - start;
		duration_secs = duration / (1000000.0 * cycles_per_us);
	} while(duration_secs <= nsecs);
	stop_button = 1;

	/* gather results */
	uint64_t xput = 0;
	*errors = 0;
	for (i = 0; i < nthreads; i++) {
		xput += tdata[i].xput_ops;
		*errors += tdata[i].errors;
	}
	xput /= duration_secs;
	*latencyns = tdata[0].xput_ops > 0 ? 
		duration * 1000 / (cycles_per_us * tdata[0].xput_ops) : 0;	 /*latency seen by any one core*/ 
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

	while(!start_button)	cpu_relax();
	while(!stop_button) {
		fdnow = (fdnow + 1) % hdata->nfds;
      	if (poll(&hdata->evt[fdnow], 1, 0) > 0) {
			pr_debug("handler %d found a pending event %d:%d:%d", self, 
				hdata->evt[fdnow].fd, hdata->evt[fdnow].events, hdata->evt[fdnow].revents);

			/* handle unexpected poll events */
			ASSERT((hdata->evt[fdnow].revents & POLLERR) == 0);
			ASSERT((hdata->evt[fdnow].revents & POLLHUP) == 0);

			/* read fault */
        	read_size = read(hdata->evt[fdnow].fd, &msg, sizeof(struct uffd_msg));
			pr_debug("handler %d read %ld bytes (errno %d) on fd %d", 
				self, read_size, errno, hdata->evt[fdnow].fd);
			if (read_size == -1) {
				/* only EAGAIN is fine; another handler got to this message first */
				ASSERT(errno == EAGAIN);
				continue;
			}
			ASSERT(read_size == sizeof(struct uffd_msg));

			/* do something with the fault */
			switch (msg.event) {
				case UFFD_EVENT_PAGEFAULT:
					/* plugin a zero page */
					pr_debug("handler %d resolving fault %llu", self, msg.arg.pagefault.address);
					r = uffd_zero(hdata->evt[fdnow].fd, msg.arg.pagefault.address & PAGE_MASK, PAGE_SIZE, true, &retries);
					ASSERT(r == 0);
					pr_debug("fault ip, addr: 0x%lx 0x%llx", (long) msg.ip, msg.arg.pagefault.address);
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
	ASSERTZ(nthreads & (nthreads - 1));	/*power of 2*/
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
	size = MAX_MEMORY / nregions;
	ASSERT(size % PAGE_SIZE == 0);
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
		tdata[i].range_start = (nregions == 1) ? reg[0]->addr + (i * size_per_thread) : reg[i]->addr;
		tdata[i].range_len = size_per_thread;
		pr_debug("thread %d working with region %d (%lu, %lu)", i, 
			(nregions == 1) ? 0 : i, tdata[i].range_start, tdata[i].range_len);
	}

	/* start measuring threads */
	uint64_t xput, errors, latns;
	ASSERTZ(pthread_barrier_init(&ready, NULL, nthreads + 1));
#if defined(MAP_PAGE)
	xput = do_app_work(OP_MAP_PAGE_NO_WP, nthreads, tdata, coreidx, &errors, 
		&latns, RUNTIME_SECS);
#elif defined(MAP_PAGE_NOWAKE)
	xput = do_app_work(OP_MAP_PAGE_NO_WP_NO_WAKE, nthreads, tdata, coreidx, 
		&errors, &latns, RUNTIME_SECS);
#elif defined(UNMAP_PAGE)
	/* map pages before unmapping them. currently map is faster than unmap 
	 * so we should have enough pages to unmap for a given run duration */
	do_app_work(OP_MAP_PAGE_NO_WP_NO_WAKE, nthreads, tdata, coreidx, &errors, 
		&latns, RUNTIME_SECS);
	/* access pages to clobber tlb */
	xput = do_app_work(OP_UNMAP_PAGE, nthreads, tdata, coreidx, &errors, 
		&latns, RUNTIME_SECS);
#elif defined(PROTECT_PAGE)
	/* map pages unprotected before protecting them. WRprotect is TODO */
	do_app_work(OP_MAP_PAGE_NO_WP_NO_WAKE, nthreads, tdata, coreidx, &errors, 
		&latns, RUNTIME_SECS);
	xput = do_app_work(OP_PROTECT_PAGE, nthreads, tdata, coreidx, &errors, 
		&latns, RUNTIME_SECS/2);
#elif defined(UNPROTECT_PAGE)
	/* map pages protected before unprotecting them. WRprotect is TODO */
	do_app_work(OP_MAP_PAGE_WP_NO_WAKE, nthreads, tdata, coreidx, &errors, 
		&latns, RUNTIME_SECS);
	xput = do_app_work(OP_UNPROTECT_PAGE, nthreads, tdata, coreidx, &errors, 
		&latns, RUNTIME_SECS/2);
#elif defined(UNPROTECT_PAGE_NOWAKE)
	/* map pages protected before unprotecting them. WRprotect is TODO */
	do_app_work(OP_MAP_PAGE_WP_NO_WAKE, nthreads, tdata, coreidx, &errors, 
		&latns, RUNTIME_SECS);
	xput = do_app_work(OP_UNPROTECT_PAGE_NO_WAKE, nthreads, tdata, coreidx, 
		&errors, &latns, RUNTIME_SECS/2);
#elif defined(ACCESS_PAGE) || defined(ACCESS_PAGE_WHOLE)
	op = OP_ACCESS_PAGE;
#ifdef ACCESS_PAGE_WHOLE
	op = OP_ACCESS_PAGE_WHOLE;
#endif
	int app_start_core;
	#if HT_HANDLERS
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
		&latns, RUNTIME_SECS);
#else
	printf("Unknown operation\n");
	return 1;
#endif

	printf("%d,%lu,%lu,%lu\n", nthreads, xput, errors, latns);
	return 0;
}
