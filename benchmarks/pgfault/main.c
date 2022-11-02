
#include <stdio.h>
#include <unistd.h>
#include <math.h>

#include "base/time.h"
#include "runtime/thread.h"
#include "runtime/sync.h"
#include "runtime/pgfault.h"
#include "runtime/timer.h"
#include "rmem/common.h"
#include "rmem/api.h"
#include "utils.h"

#define RUNTIME_SECS        10
#define NSAMPLES_PER_THREAD 5000
#define MAX_XPUT_PER_THREAD 500000
#define MAX_MEMORY	        68719476736		// 64 GB
#define BATCH_SIZE		    128

#ifdef REMOTE_MEMORY
#define heap_alloc rmalloc
#else 
#define heap_alloc malloc
#endif

enum fault_op {
    FO_READ = 0,
    FO_WRITE,
    FO_READ_WRITE,
    FO_RANDOM
};

struct thread_data {
    int tid;
    void* start;
    size_t size;
    struct rand_state rs;
    uint64_t npages;
    uint64_t start_tsc;
    uint64_t end_tsc;
    uint64_t latencies[NSAMPLES_PER_THREAD];
    int nlatencies;
} CACHE_ALIGN;
typedef struct thread_data thread_data_t;

waitgroup_t workers;
barrier_t barrier;
volatile int stop = 0;

int global_pre_init(void) 	{ return 0; }
int perthread_init(void)   	{ return 0; }
int global_post_init(void) 	{ return 0; }

double next_poisson_time(double rate, unsigned long randomness)
{
    return -logf(1.0f - ((double)(randomness % RAND_MAX)) 
        / (double)(RAND_MAX)) 
        / rate;
}

/* save unix timestamp of a checkpoint */
void save_number_to_file(char* fname, unsigned long val)
{
    FILE* fp = fopen(fname, "w");
    fprintf(fp, "%lu", val);
    fflush(fp);
    fclose(fp);
}

/* work for each user thread */
void thread_main(void* arg)
{
    volatile char tmp;
    void *start, *addr;
    unsigned long npages;
    uint64_t now_tsc;
    int rdahead, rdahead_skip, rdahead_next, samples;
    double duration_secs, sampling_rate;
    unsigned long randomness;
    thread_data_t* targs;
    enum fault_op op, cur_op;

    targs = (thread_data_t*) arg;

    /* latency sampling rate per thread */
    sampling_rate = (NSAMPLES_PER_THREAD * 1.0 / 
        (RUNTIME_SECS * MAX_XPUT_PER_THREAD));

    /* figure out read ahead */
    rdahead = rdahead_skip = rdahead_next = 0;
#ifdef RDAHEAD
    rdahead = RDAHEAD;
#endif
    assert(rdahead >= 0);

    /* figure out fault kind and operation */
    op = FO_READ;
#ifdef FAULT_OP
    op = (enum fault_op) FAULT_OP;
#endif
    cur_op = op;

    /* wait for all threads to init */
    log_debug("thread %d inited with op %d, rdahead %d, sampling rate %f,"
        " start %p, size %lu", targs->tid, op, rdahead, sampling_rate,
        targs->start, targs->size);
    barrier_wait(&barrier);

    samples = 0;
    npages = 0;
    start = targs->start;
    while(!stop && start < (targs->start + targs->size))
    {
        now_tsc = 0;
        randomness = rand_next(&targs->rs);
    
        if (op == FO_RANDOM)
            cur_op = (randomness & (1<<16)) ? FO_READ : FO_WRITE;

        /* point to a random offset in the page */
        addr = start + (randomness & _PAGE_OFFSET_MASK);
        addr = (void*) ((unsigned long) addr & ~0x7);	/* 64-bit align */
        log_debug("faulting on %p", addr);

#ifdef LATENCY
        /* should we sample this time? */		
        if (npages >= next_sample) {
            next_sample = npages + next_poisson_time(sampling_rate, randomness);
            now_tsc = rdtsc();
        }
#endif

        /* perform access/trigger fault */
        switch (cur_op) {
            case FO_READ:
                hint_read_fault_rdahead(addr, rdahead_next);
                tmp = *(char volatile*) addr;
                break;
            case FO_WRITE:
                hint_write_fault_rdahead(addr, rdahead_next);
                *(char*) addr = tmp;
                break;
            case FO_READ_WRITE:
                hint_write_fault_rdahead(addr, rdahead_next);
                tmp = *(char*) addr;
                *(char*) addr = tmp;
                break;
            default:
                BUG();	/* bug */
        }

#ifdef LATENCY
        /* note down latency */
        if (samples < NSAMPLES_PER_THREAD && now_tsc) {
            targs->latencies[samples] = (rdtscp(NULL) - now_tsc);
            samples++;
        }
#endif

        /* params for next batch */
        start += _PAGE_SIZE;
        npages++;
        if(rdahead_skip-- <= 0)
            rdahead_skip = rdahead;
        rdahead_next = rdahead_skip ? 0 : rdahead;

        /* yield once in a while */
        if (npages % 100 == 0)
            thread_yield();

#ifdef DEBUG
        /* break sooner when debugging */
        if (npages >= 1)
            break;
#endif
    }

    targs->npages = npages;
    targs->nlatencies = samples;
    log_debug("thread %d done", targs->tid);
    waitgroup_add(&workers, -1);	/* signal done */
}

/* thread to signal timeout */
void timeout_thread(void* arg) {
	unsigned long sleep_us = (unsigned long) arg;
	timer_sleep(sleep_us);
    log_info("timeout reached, stopping");
	stop = 1;
}

/* main thread called into by shenango runtime */
void main_handler(void* arg)
{
    int i, j, ret;
    void* region;
    thread_data_t* targs;
    unsigned long batch_offset, size;
    uint64_t start_tsc, time_tsc;
    uint64_t npages;
    int samples;
    double time_secs;
    int nthreads;
	unsigned long timeout_us;
    
    ASSERT(cycles_per_us);

    /* number of worker threads */
    nthreads = BATCH_SIZE;
#ifdef LATENCY
    nthreads = 1;
#endif
    log_info("running with %d worker threads", nthreads);

    /* write pid */
	save_number_to_file("main_pid", getpid());
    /* give some time for the saved pid to be added to the cgroup to enforce 
     * fastswap limits */
    sleep(1);

    /* allocate memory */
    region = heap_alloc(MAX_MEMORY);
    ASSERT(region != NULL);
    log_info("region start at %p, size %lu", region, MAX_MEMORY);
    BUILD_ASSERT(MAX_MEMORY % BATCH_SIZE == 0);
    region = (void*) align_up((unsigned long) region, BATCH_SIZE);
    size = align_down(MAX_MEMORY, CHUNK_SIZE);
    batch_offset = align_down(size / BATCH_SIZE, CHUNK_SIZE);

    /* create threads */
    targs = malloc(BATCH_SIZE * sizeof(thread_data_t));
    for (i = 0; i < BATCH_SIZE; i++) {
        targs[i].tid = i;
        targs[i].start = region + i * batch_offset;
        targs[i].size = batch_offset;
        assert((targs[i].start + targs[i].size) <= (region + size));
        ASSERTZ(rand_seed(&targs[i].rs, time(NULL) ^ i));
    }

    /* start threads */
    waitgroup_init(&workers);
    barrier_init(&barrier, BATCH_SIZE + 1);
    for (i = 0; i < BATCH_SIZE; i++) {
        waitgroup_add(&workers, 1);
        ret = thread_spawn(thread_main, &targs[i]);
        ASSERTZ(ret);
    }

    /* start timer and kick off */
	log_info("starting the run");
	start_tsc = rdtsc();
	stop = 0;
	timeout_us = RUNTIME_SECS * 1e6;
	ret = thread_spawn(timeout_thread, (void*) timeout_us);
    ASSERTZ(ret);
    barrier_wait(&barrier);

    /* yield & wait until the batch is done */
    waitgroup_wait(&workers);
	time_tsc = rdtscp(NULL) - start_tsc;

    /* collect xput */
    npages = 0;
    samples = 0;
    for (i = 0; i < BATCH_SIZE; i++) {
        npages += targs[i].npages;
        samples += targs[i].nlatencies;
    }
    time_secs = time_tsc / (1000000.0 * cycles_per_us);

    /* write xput to file */
    log_info("ran for %.1lf secs with %.0lf ops /sec", 
        time_secs, npages / time_secs);
    save_number_to_file("result", npages / time_secs);
    sleep(1);

    /* dump latencies to file */
    if (samples > 0) {
        FILE* outfile = fopen("latencies", "w");
        if (outfile == NULL)
            log_warn("could not write to latencies file");
        else {
            fprintf(outfile, "latency\n");
            for (i = 0; i < BATCH_SIZE; i++)
                for (j = 0; j < targs[i].nlatencies; j++)
                    fprintf(outfile, "%.3lf\n", targs[i].latencies[i] * 1.0);
            fclose(outfile);
            log_info("Wrote %d sampled latencies", samples);
        }
    }
}

int main(int argc, char *argv[]) {
    int ret;

    if (argc < 2) {
        log_err("arg must be config file\n");
        return -EINVAL;
    }

    ret = runtime_set_initializers(global_pre_init, perthread_init, global_post_init);
    ASSERTZ(ret);

    ret = runtime_init(argv[1], main_handler, NULL);
    ASSERTZ(ret);
    return 0;
}