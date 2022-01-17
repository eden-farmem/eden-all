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
#include "parse_vdso.h"

#ifdef USE_APP_FAULTS
#define USE_PREFETCH
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
pthread_barrier_t ready, lockstep_start, lockstep_end;
int start_button = 0, stop_button = 0;
int stop_button_seen = 0;

struct thread_data {
    int tid;
	int core;
    struct rand_state rs;
	uint64_t range_start;
	uint64_t range_len;
	int xput_ops;
	int errors;
} CACHE_ALIGN;

enum fault_kind {
	FK_NORMAL,
	FK_APPFAULT,
	FK_MIXED
};

enum fault_op {
	FO_READ = 0,
	FO_WRITE,
	FO_READ_WRITE,
	FO_RANDOM
};

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

/*post app fault and wait for response*/
static inline void post_app_fault_sync(int channel, unsigned long fault_addr, int is_write){
	int r;
	app_fault_packet_t fault;
	fault.channel = channel; 
	fault.fault_addr = fault_addr;
	fault.flags =  is_write ? APP_FAULT_FLAG_WRITE : APP_FAULT_FLAG_READ;
	fault.taginfo = (void*) fault_addr;		/*testing*/
	r = app_post_fault_async(channel, &fault);
	ASSERTZ(r);		/*can't fail as long as we send one fault at a time*/

	app_fault_packet_t resp;
	while(app_read_fault_resp_async(channel, &resp)) 
		cpu_relax();
	ASSERT(resp.taginfo == (void*) fault_addr);	/*sanity check*/
}

void* thread_main(void* args) {
    struct thread_data * tdata = (struct thread_data *)args;
    ASSERTZ(pin_thread(tdata->core));
	pr_debug("thread %d pinned to core %d", tdata->tid, tdata->core);

    int self = tdata->tid;
	int r, retries, tmp, i = 0, stop = 0;
	void *p, *page_buf = malloc(PAGE_SIZE);
	app_fault_packet_t fault;
	enum fault_kind kind = FK_NORMAL;
	enum fault_op op = FO_READ;
	bool concurrent = false;

/*fault kind*/
#ifdef USE_APP_FAULTS
	kind = FK_APPFAULT;
#endif
#ifdef MIX_FAULTS
#ifndef USE_APP_FAULTS
#error MIX_FAULTS needs USE_APP_FAULTS as well
#endif
	kind = FK_MIXED;
#endif
/*fault operation*/
#ifdef FAULT_OP
	op = (enum fault_op) FAULT_OP;
#endif
#ifdef CONCURRENT
	concurrent = true;
#endif

	r = pthread_barrier_wait(&ready);	/*signal ready*/
    ASSERT(r != EINVAL);

	while(!start_button)	cpu_relax();
	p = (void*)(tdata->range_start);
	p = (void*) page_align(p);
	printf("thread %d with memory start %lu, size %lu, kind %d, op %d\n", 
		self, tdata->range_start, tdata->range_len, kind, op);

	while(!stop) {
		if (op == FO_RANDOM)
			op = (rand_next(&tdata->rs) & 1) ? FO_READ : FO_WRITE;

		if (kind == FK_APPFAULT || (kind == FK_MIXED && (rand_next(&tdata->rs) & 1))) {
#ifdef USE_APP_FAULTS
			pr_debug("posting app fault on thread %d", tdata->tid);
			r = prefetch_page(p);	/*access before*/
			ASSERT(r == -1);		/*page not expected to exist*/

			if (concurrent) {
				/*sync with other threads before each fault*/
				r = pthread_barrier_wait(&lockstep_start);
				ASSERT(r != EINVAL);
			}

			if (op == FO_READ || op == FO_READ_WRITE)
				post_app_fault_sync(tdata->tid, (unsigned long)p, FO_READ);
			if (op == FO_WRITE || op == FO_READ_WRITE)
				post_app_fault_sync(tdata->tid, (unsigned long)p, FO_WRITE);
			
			r = prefetch_page(p);	/*access after*/
			ASSERTZ(r);				/*page expected to exist*/
			pr_debug("page fault served!");
#else
			BUG(1);	/*cannot be here without USE_APP_FAULTS*/
#endif
		}
		else {
			/*normal accesses*/
			if (concurrent) {
				/*sync with other threads before each fault*/
				r = pthread_barrier_wait(&lockstep_start);
				ASSERT(r != EINVAL);
			}
			pr_debug("posting regular fault on thread %d\n", tdata->tid);
			if (op == FO_READ || op == FO_READ_WRITE)
				tmp = *(int*)p;
			if (op == FO_WRITE || op == FO_READ_WRITE)
				*(int*)p = tmp;
		}
		ASSERT(((unsigned long) p) < (tdata->range_start + tdata->range_len)); 
		tdata->xput_ops++;
		p += PAGE_SIZE;
#ifdef DEBUG
		i++;
		if (i == 1000) 	
			break;
#endif

		/* seeing stop_button from main thread */
		if (concurrent) {
			/* we need two barriers to lockstep a set of threads which 
			 * also need to stop together based on an external signal 
			 * why? https://stackoverflow.com/questions/28843735/whats-a-good-strategy-for-clean-reliable-shutdown-of-threads-that-use-pthread-b*/
			stop_button_seen = stop_button;
			r = pthread_barrier_wait(&lockstep_end);
			ASSERT(r != EINVAL);
			stop = stop_button_seen;
		}
		else	
			stop = stop_button;
	}
	pr_debug("thread %d done with %d faults", tdata->tid, i);
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
	char env_var[200];
	size = 34359738368;
	sprintf(env_var, "MEMORY_LIMIT=%lu", size);	putenv(env_var);	/*32gb, BIG to avoid eviction*/
	putenv("EVICTION_THRESHOLD=1");			/*32gb, BIG to avoid eviction*/
	putenv("EVICTION_DONE_THRESHOLD=1");	/*32gb, BIG to avoid eviction*/
#ifdef USE_APP_FAULTS
	sprintf(env_var, "APP_FAULT_CHANNELS=%d", num_threads);	putenv(env_var);
#endif
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
	ASSERTZ(pthread_barrier_init(&lockstep_start, NULL, num_threads));
	ASSERTZ(pthread_barrier_init(&lockstep_end, NULL, num_threads));
	pin_thread(coreidx);	/*main thread on core 0*/
	
	for(i = 0; i < num_threads; i++) {
		tdata[i].tid = i;
		ASSERTZ(rand_seed(&tdata[i].rs, time(NULL) ^ i));
        ASSERT(coreidx < NUM_CORES);
		coreidx = next_available_core(coreidx);
        tdata[i].core = coreidx;
#ifndef CONCURRENT
		tdata[i].range_start = ((unsigned long) p) + i * (size / num_threads);
		tdata[i].range_len = (size / num_threads);
#else
		tdata[i].range_start = ((unsigned long) p);
		tdata[i].range_len = size;
#endif
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

	/*wait for threads to finish*/
	for(i = 0; i < num_threads; i++)
		pthread_join(threads[i], NULL);

	uint64_t xput = 0, errors = 0;
	for (i = 0; i < num_threads; i++) {
		xput += tdata[i].xput_ops;
		errors += tdata[i].errors;
	}
	
	printf("ran for %.1lf secs; total xput %lu\n", duration_secs, xput);
	printf("result:%d,%.0lf,%.1lf\n", num_threads, 
		xput / duration_secs, 								//total xput
		duration * 1.0/(cycles_per_us*tdata[0].xput_ops));	//per-op latency

	rdestroy();
	return 0;
}
