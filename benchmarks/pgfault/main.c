
#include <stdio.h>
#include <unistd.h>
#include <math.h>

#include "base/time.h"
#include "runtime/thread.h"
#include "runtime/sync.h"
#include "runtime/pgfault.h"
#include "runtime/timer.h"
#include "utils.h"

/* settings */
#define RUNTIME_SECS        10
#define NSAMPLES_PER_THREAD 5000
#define MAX_XPUT_PER_THREAD 500000
#define MAX_MEMORY	        (64ULL * 1024 * 1024 * 1024)    // 64 GB
#define MIN_MEMORY	        (10ULL * 1024 * 1024)           // 10 MB
#define BATCH_SIZE		    128
#define FASTSWAP_CGROUP_APP "pfbenchmark"

#ifdef EDEN
/* eden backend */
#include "rmem/common.h"
#include "rmem/api.h"
#define heap_alloc rmalloc
void set_local_memory_limit(unsigned long limit)
{
    local_memory = limit;
}

unsigned long get_memory_usage()
{
    return atomic64_read(&memory_used);
}

#elif defined FASTSWAP
/* fastswap backend */
#define heap_alloc malloc
void set_local_memory_limit(unsigned long limit)
{
    int ret;
    char buf[256];
    sprintf(buf, "echo %lu > /cgroup2/benchmarks/%s/memory.high", 
        limit, FASTSWAP_CGROUP_APP);
    ret = system(buf);
    BUG_ON(ret);
}

unsigned long get_memory_usage()
{
    char fname[256];
    FILE *fp;
    unsigned long usage;

    sprintf(fname, "/cgroup2/benchmarks/%s/memory.current", FASTSWAP_CGROUP_APP);
    fp = fopen(fname, "r");
    if (fp == NULL) {
        log_err("Failed to get memory usage\n" );
        BUG();
    }

    fscanf(fp, "%lu", &usage);
    fclose(fp);
    return usage;
}
#else
/* no backend */
#define heap_alloc malloc
void set_local_memory_limit(unsigned long limit)
{
    return;
}

unsigned long get_memory_usage()
{
    return MIN_MEMORY;
}
#endif


enum fault_op {
    FO_READ = 0,
    FO_WRITE,
    FO_READ_WRITE,
    FO_RANDOM
};

struct thread_data {
    /* thread input */
    int tid;
    enum fault_op op;
    void* start;
    size_t size;
    struct rand_state rs;
    bool sample_lat;
    int rdahead;

    /* per-thread results */
    uint64_t npages;
    uint64_t start_tsc;
    uint64_t end_tsc;
    uint64_t latencies[NSAMPLES_PER_THREAD];
    int nlatencies;
} CACHE_ALIGN;
typedef struct thread_data thread_data_t;

struct run_result {
    uint64_t npages;
    double time_secs;
    int nlatencies;
};

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
    unsigned long randomness, next_sample;
    thread_data_t* targs;
    enum fault_op op, cur_op;

    targs = (thread_data_t*) arg;

    /* latency sampling rate per thread */
    sampling_rate = (NSAMPLES_PER_THREAD * 1.0 / 
        (RUNTIME_SECS * MAX_XPUT_PER_THREAD));

    /* wait for all threads to init */
    log_debug("thread %d inited with op %d, rdahead %d, sampling rate %f,"
        " start %p, size %lu", targs->tid, op, rdahead, sampling_rate,
        targs->start, targs->size);
    barrier_wait(&barrier);

    samples = 0;
    npages = 0;
    rdahead_skip = rdahead_next = 0;
    cur_op = targs->op;
    start = targs->start;
    while(!stop && start < (targs->start + targs->size))
    {
        now_tsc = 0;
        randomness = rand_next(&targs->rs);
    
        if (targs->op == FO_RANDOM)
            cur_op = (randomness & (1<<16)) ? FO_READ : FO_WRITE;

        /* point to a random offset in the page */
        addr = start + (randomness & _PAGE_OFFSET_MASK);
        addr = (void*) ((unsigned long) addr & ~0x7);	/* 64-bit align */
        log_debug("faulting on %p", addr);

        /* should we sample this time? */		
        if (targs->sample_lat && npages >= next_sample) {
            next_sample = npages + next_poisson_time(sampling_rate, randomness);
            now_tsc = rdtsc();
        }

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

        /* note down latency */
        if (now_tsc && samples < NSAMPLES_PER_THREAD) {
            targs->latencies[samples] = (rdtscp(NULL) - now_tsc);
            samples++;
        }

        /* params for next batch */
        start += _PAGE_SIZE;
        npages++;
        if(rdahead_skip-- <= 0)
            rdahead_skip = targs->rdahead;
        rdahead_next = rdahead_skip ? 0 : targs->rdahead;

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

struct run_result do_work(thread_data_t* targs, int nthreads, enum fault_op op,
    int rdahead, int max_secs, bool sample_lat)
{
    int i, j, samples, ret;
    uint64_t start_tsc, time_tsc;
    uint64_t npages;
    double time_secs;
	unsigned long timeout_us;
    struct run_result result;

    /* start threads */
    waitgroup_init(&workers);
    barrier_init(&barrier, nthreads + 1);
    for (i = 0; i < nthreads; i++) {
        waitgroup_add(&workers, 1);
        targs[i].op = op;
        targs[i].rdahead = rdahead;
        targs[i].sample_lat = sample_lat;
        ret = thread_spawn(thread_main, &targs[i]);
        ASSERTZ(ret);
    }

    /* start timer thread and kick off */
	log_info("starting the run");
	start_tsc = rdtsc();
	stop = 0;
    if (max_secs > 0) {
	    timeout_us = max_secs * 1e6;
	    ret = thread_spawn(timeout_thread, (void*) timeout_us);
        ASSERTZ(ret);
    }
    barrier_wait(&barrier);

    /* yield & wait until the batch is done */
    waitgroup_wait(&workers);
	time_tsc = rdtscp(NULL) - start_tsc;
    time_secs = time_tsc / (1000000.0 * cycles_per_us);

    /* aggregate xput */
    npages = 0;
    for (i = 0; i < nthreads; i++)
        npages += targs[i].npages;

    /* dump latencies to file (NOTE: this will overwrite the same file 
     * if called multiple times) */
    samples = 0;
    if (sample_lat) {
        FILE* outfile = fopen("latencies", "w");
        ASSERT(outfile);
        fprintf(outfile, "latency\n");
        for (i = 0; i < BATCH_SIZE; i++)
            for (j = 0; j < targs[i].nlatencies; j++) {
                fprintf(outfile, "%.3lf\n", targs[i].latencies[j] * 1.0);
                samples++;
            }
        fclose(outfile);
        log_info("Wrote %d sampled latencies", samples);
    }

    log_info("worked on %lu pages for %.1lf secs", npages, time_secs);
    result.npages = npages;
    result.time_secs = time_secs;
    result.nlatencies = samples;
    return result;
}

/* main thread called into by shenango runtime */
void main_handler(void* arg)
{
    int i;
    void* region;
    thread_data_t* targs;
    unsigned long batch_offset, size;
    unsigned long start_tsc, end_tsc;
    double time_secs;
    int nthreads, rdahead;
    enum fault_op op;
    bool sample_lat, evict_on_path;
    struct run_result result;
    unsigned long memory_start;
    int wait_secs;
    
    ASSERT(cycles_per_us);

    /* parameters */
    nthreads = BATCH_SIZE;

    /* sample latencies */
    sample_lat = false;
#ifdef LATENCY
    nthreads = 1;
    sample_lat = true;
#endif
    
    /* read-ahead */
    rdahead = 0;
#ifdef RDAHEAD
    rdahead = RDAHEAD;
#endif
    assert(rdahead >= 0);

    /* fault operation */
    op = FO_READ;
#ifdef FAULT_OP
    op = (enum fault_op) FAULT_OP;
#endif

    /* evict on path */
    evict_on_path = false;
#ifdef EVICT_ON_PATH
    evict_on_path = true;
#endif

    log_info("running with %d worker threads, read-ahead %d op %d", 
        nthreads, rdahead, op);

    /* write pid and wait some time for the saved pid to be added to 
     * the cgroup to enforce fastswap limits */
	save_number_to_file("main_pid", getpid());
    sleep(1);

    /* allocate memory */
    start_tsc = rdtsc();
    region = heap_alloc(MAX_MEMORY);
    ASSERT(region != NULL);
    log_info("memory alloc took %lu ns", 
        (rdtscp(NULL) - start_tsc) * 1000 / cycles_per_us);

    /* alignment and offsets */
    log_info("region start at %p, size %llu", region, MAX_MEMORY);
    assert(MAX_MEMORY % nthreads == 0);
    region = (void*) align_up((unsigned long) region, nthreads);
    size = align_down(MAX_MEMORY, CHUNK_SIZE);
    batch_offset = align_down(size / nthreads, CHUNK_SIZE);

    /* init threads with segregated regions */
    targs = malloc(nthreads * sizeof(thread_data_t));
    memset(targs, 0, nthreads * sizeof(thread_data_t));
    for (i = 0; i < nthreads; i++) {
        targs[i].tid = i;
        targs[i].start = region + i * batch_offset;
        targs[i].size = batch_offset;
        assert((targs[i].start + targs[i].size) <= (region + size));
        ASSERTZ(rand_seed(&targs[i].rs, time(NULL) ^ i));
    }

    /* read in all memory once but with low memory */
    set_local_memory_limit(MIN_MEMORY);
    do_work(targs, nthreads, FO_READ, 0, 0, false);

    /* wait until eviction catches up */
    wait_secs = 0;
    log_info("waiting for eviction to catch up");
    while (get_memory_usage() > MIN_MEMORY) {
        sleep(1);
        wait_secs++;
        BUG_ON(wait_secs > 5);  /* too longer than expected */
    }
    
    /* now do the op again */
    local_memory = evict_on_path ? MIN_MEMORY * nthreads : MAX_MEMORY;
    result = do_work(targs, nthreads, op, rdahead, RUNTIME_SECS, sample_lat);

    /* write xput to file */
    log_info("ran for %.1lf secs with %.0lf ops /sec",
        result.time_secs, result.npages / result.time_secs);
    save_number_to_file("result", result.npages / result.time_secs);
    sleep(1);
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