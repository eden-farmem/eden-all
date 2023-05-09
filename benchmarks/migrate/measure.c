/*
 * Userfaultfd Page Ops Benchmarks 
 */

#define _GNU_SOURCE

#include <string.h>
#include <numa.h>
#include <numaif.h>

#include "utils.h"
#include "logging.h"
#include "ops.h"

#define GIGA 				(1ULL << 30)
#define PHY_CORES_PER_NODE 	14
#define MAX_CORES 			(2*PHY_CORES_PER_NODE) /* cores per numa node */
#define MAX_THREADS 		(MAX_CORES-1)
#define RUNTIME_SECS 		30
#define NO_TIMEOUT 			-1
#ifndef BATCH_SIZE
#define BATCH_SIZE 			1
#endif
#define NSTRIPS				BATCH_SIZE
#define MAX_MEMORY 			(64*GIGA)

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
size_t node0_used, node1_used;

enum app_op {
    OP_READ_PAGE,
    OP_WRITE_PAGE,
    OP_MOVE_PAGES_TO_NODE0,
    OP_MOVE_PAGES_TO_NODE1,
};

struct thread_data {
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

static inline size_t numa_memory_used(int nodeid)
{
    size_t total, free;
    total = numa_node_size(nodeid, &free);
    return total - free;
}

static inline bool check_numa_node_used(int nodeid)
{
    size_t used = numa_memory_used(nodeid);
    if (nodeid == 0) {
        if (used > node0_used)
            return true;
    } else if (nodeid == 1) {
        if (used > node1_used)
            return true;
    }
    return false;
}

static inline int move_numa_pages(void** pages, int* nodes,
    int* status, int npages)
{
    int i, r;
    
    r = numa_move_pages(0, npages, pages, nodes, status, MPOL_MF_MOVE);
    if (r == 0) {
        /* double-check */
        numa_move_pages(0, npages, pages, NULL, status, MPOL_MF_MOVE);
        for (i = 0; i < npages; i++) {
            if (status[i] != nodes[i]) {
                pr_err("page %d: %p not moved to node %d\n", 
                    i, pages[i], nodes[i]);
                r = -1;
                break;
            }
        }
    }
    else {
        pr_err("numa_move_pages failed. ret %d errno: %d\n", r, errno);
        for (i = 0; i < npages; i++) {
            if (status[i] != 0) {
                pr_err("page %d: %p not moved to node %d, error %d\n", 
                    i, pages[i], nodes[i], status[i]);
            }
        }
    }
    return r;
}


/* perform an operation */
int perform_app_op(enum app_op optype, void** pages, int npages, int* status)
{
    int i, x, r = 0;
    int* tonodes;
    static int tonodes0[BATCH_SIZE] CACHE_ALIGN = {[0 ... BATCH_SIZE-1] = 0};
    static int tonodes1[BATCH_SIZE] CACHE_ALIGN = {[0 ... BATCH_SIZE-1] = 1};

    /* vectored ops */
    switch(optype) {
        case OP_MOVE_PAGES_TO_NODE0:
        case OP_MOVE_PAGES_TO_NODE1:
            tonodes = (optype == OP_MOVE_PAGES_TO_NODE0) ? tonodes0 : tonodes1;
            r = move_numa_pages(pages, tonodes, status, npages);
            ASSERTZ(r);
            return r;
        default:
            break;
    }

    /* non-vectored ops */
    for (i = 0; i < npages; i++) {
        switch(optype) {
            case OP_READ_PAGE:
                x = *(int*) pages[i];
                r |= 0;
                break;
            case OP_WRITE_PAGE:
                *(int*) pages[i] = 1;
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
    void* pages[BATCH_SIZE];
    int status[BATCH_SIZE];
    ssize_t ret;
    size_t stripe_size = tdata->range_len / NSTRIPS;
    size_t strip_offset = 0, offset;
    int cur_strip = 0;
    size_t max_stripe_size = (tdata->prev_stripe_size != 0) ?
        tdata->prev_stripe_size : stripe_size;
    unsigned long start_tsc;

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
            pages[i] = (void*) (tdata->range_start + offset);
            cur_strip++;
            if (cur_strip == NSTRIPS) {
                cur_strip = 0;
                strip_offset += PAGE_SIZE;
            }
            npages++;
        }

        /* execute batch */
        r = perform_app_op(tdata->optype, pages, npages, status);

        if (r)	tdata->errors++;
        else tdata->ops++;

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

uint64_t do_app_work(enum app_op optype, int ncores, 
    struct thread_data* tdata, int starting_core, uint64_t* errors, 
    uint64_t* latencyns, size_t* memory_covered, int nsecs)
{
    int i, r;
    uint64_t start, duration, xput;
    double duration_secs, time_secs;
    int coreidx = starting_core;
    unsigned long time_tsc;
    unsigned long covered;

    /* spawn threads */
    pthread_t threads[MAX_THREADS];
    for(i = 0; i < ncores; i++) {
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
    for(i = 0; i < ncores; i++)
        pthread_join(threads[i], NULL);

    /* gather results */
    xput = 0;
    time_tsc = 0;
    *errors = 0;
    covered = 0;
    for (i = 0; i < ncores; i++) {
        xput += tdata[i].ops * BATCH_SIZE;
        *errors += tdata[i].errors;
        covered += tdata[i].prev_stripe_size * NSTRIPS;
        if (time_tsc < tdata[i].time_tsc)
            time_tsc = tdata[i].time_tsc;
    }
    time_secs = time_tsc / (1000000.0 * cycles_per_us);
    xput /= time_secs;
    pr_info("Op %d ran for %.2f secs, xput: %lu pages/sec, covered %llu gb", 
        optype, time_secs, xput, covered / GIGA);
    
    /* latency seen by any one core */
    if (latencyns)
        *latencyns = tdata[0].ops > 0 ?
            tdata[0].time_tsc * 1000 / (cycles_per_us * tdata[0].ops) : 0;
    if (memory_covered)
        *memory_covered = covered;
    return xput;
}

int main(int argc, char **argv)
{
    int ncores, i;
    size_t size, realsize, touched, migrated;
    void* region;
    uint64_t xput, errors, latns;

    /* parse & validate args */
    if (argc > 2) {
        printf("Invalid args\n");
        printf("Usage: %s [ncores]\n", argv[0]);
        printf("[ncores]\t number of measuring cores\n");
        return 1;
    }
    ncores = (argc > 1) ? atoi(argv[1]) : 1;
    ASSERT(ncores > 0);
    ASSERT(ncores <= MAX_CORES);
    pr_debug("Running %s with %d threads", argv[0], ncores);

    /*init*/
    ASSERT(sizeof(struct thread_data) % CACHE_LINE_SIZE == 0);
    cycles_per_us = time_calibrate_tsc();
    ASSERT(cycles_per_us);
    ASSERTZ(pthread_barrier_init(&ready, NULL, ncores + 1));

    /* alloc memory */
    size = MAX_MEMORY;
    size_t size_per_thread = size / ncores;
    ASSERT(MAX_MEMORY % PAGE_SIZE == 0);
    ASSERT(size <= MAX_MEMORY);
    region = aligned_alloc(PAGE_SIZE, size);

    /* split memory among threads/cores */
    struct thread_data tdata[MAX_THREADS] CACHE_ALIGN = {0};
    realsize = 0; 
    for(i = 0; i < ncores; i++) {
        tdata[i].range_start = (unsigned long) region + (i * size_per_thread);
        tdata[i].range_len = size_per_thread & ~(PAGE_SIZE - 1);
        tdata[i].prev_stripe_size = 0;
        pr_debug("thread %d working with region (%lx, %lu)", i, 
            tdata[i].range_start, tdata[i].range_len);
        realsize += tdata[i].range_len;
    }

    /* save initial memory state */
    node0_used = numa_memory_used(0);
    node1_used = numa_memory_used(1);
    pr_info("NUMA memory used: N0 - %llu gb, N1 - %llu gb",
        node0_used/GIGA, node1_used/GIGA);

    /* touch all memory */
    do_app_work(OP_WRITE_PAGE, ncores, tdata, CORELIST[0],
        &errors, NULL, &touched, -1);
    ASSERTZ(errors);
    ASSERT(touched == realsize);

    /* check all memory is allocated on node 0 */
    pr_info("NUMA memory used: N0 - %llu gb, N1 - %llu gb",
        numa_memory_used(0)/GIGA, numa_memory_used(1)/GIGA);
    // ASSERT_EQUALS_MARGIN(numa_memory_used(0), node0_used + realsize, 0.01 * realsize);
 
    /* move all memory */
    xput = do_app_work(OP_MOVE_PAGES_TO_NODE1, ncores, tdata, CORELIST[0],
        &errors, &latns, &migrated, RUNTIME_SECS);
    
    /* check that memory is indeed migrated */
    pr_info("NUMA memory used: N0 - %llu gb, N1 - %llu gb",
        numa_memory_used(0)/GIGA, numa_memory_used(1)/GIGA);
    // ASSERT_EQUALS_MARGIN(numa_memory_used(0), node0_used + realsize - migrated, 0.01 * migrated);
    // ASSERT_EQUALS_MARGIN(numa_memory_used(1), node1_used + migrated, 0.01 * migrated);

    printf("%d,%d,%lu,%lu,%lu,%.1lf\n", ncores, BATCH_SIZE, 
        xput, errors, latns, migrated * 1.0 / GIGA);
    return 0;
}
