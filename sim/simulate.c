
#define _GNU_SOURCE
#include <assert.h>
#include <numa.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <stdint.h>
#include <unistd.h>

#include "ops.h"

#define ASSERT(x) assert((x))
#define ASSERTZ(x) ASSERT(!(x))
#define __aligned(x) __attribute__((aligned(x)))
#define BILLION	1000000000
#define MILLION	1000000

#ifdef DEBUG
#define debug(fmt, ...)                                                     \
  do {                                                                      \
    fprintf(stderr, "[%lx][%s][%s:%d]: " fmt "\n", pthread_self(), __FILE__,\
            __func__, __LINE__, ##__VA_ARGS__);                             \
  } while (0)
#else
#define debug(fmt, ...) \
  do {                  \
  } while (0)
#endif

#define MAX_CORES 28
#define MAX_APP_CORES (MAX_CORES-2)
#define CACHE_LINE_SIZE 64
#define REQ_QUEUE_DEPTH 4
#define FAULT_QUEUE_DEPTH 1
#define RUN_DURATION_SECS 2

const int NODE0_CORES[MAX_CORES] = {
    0,  1,  2,  3,  4,  5,  6, 
    7,  8,  9,  10, 11, 12, 13, 
    28, 29, 30, 31, 32, 33, 34, 
    35, 36, 37, 38, 39, 40, 41 };
#define CORELIST NODE0_CORES

struct thread_args {
    int thread_id;
    char* name;
    int core;
};

typedef enum  {
    NONE = 0,
    POSTED,
    STARTED,
    RATELIMITED,
    SERVICING,
    FAULT_WAIT,
    DONE = 255
} STATES;

typedef struct {
    STATES state;
    double hitratio;
    uint64_t wait_start_tsc;
    uint32_t pad[10];
} req_entry __aligned(CACHE_LINE_SIZE);
req_entry reqs[MAX_APP_CORES][REQ_QUEUE_DEPTH] __aligned(CACHE_LINE_SIZE) = {0};

typedef struct {
    STATES state;
    uint64_t start_tsc;
    uint32_t pad[12];
} fault_entry __aligned(CACHE_LINE_SIZE);
fault_entry faults[MAX_APP_CORES][FAULT_QUEUE_DEPTH] __aligned(CACHE_LINE_SIZE) = {0};

typedef struct {
    uint64_t received;
    uint64_t serviced;
    uint32_t pad[12];
} stat_entry __aligned(CACHE_LINE_SIZE);
stat_entry stats[MAX_APP_CORES] __aligned(CACHE_LINE_SIZE) = {0};

/* read-only globals */
pthread_t reqcore, konacore;
pthread_t appcores[MAX_APP_CORES];
int num_app_cores;
int service_time_ns;
int fault_time_ns;
int kona_fault_rate;
double hit_ratio;
int use_upcalls;
int upcall_time_ns;


/* global variables */
uint64_t konafaults __aligned(CACHE_LINE_SIZE) = 0;

/* Time Utils */
/* derived from DPDK */
uint64_t cycles_per_us __aligned(CACHE_LINE_SIZE);
static int time_calibrate_tsc(void)
{
	/* TODO: New Intel CPUs report this value in CPUID */
	struct timespec sleeptime = {.tv_nsec = 5E8 }; /* 1/2 second */
	struct timespec t_start, t_end;

	cpu_serialize();
	if (clock_gettime(CLOCK_MONOTONIC_RAW, &t_start) == 0) {
		uint64_t ns, end, start;
		double secs;

		start = rdtsc();
		nanosleep(&sleeptime, NULL);
		clock_gettime(CLOCK_MONOTONIC_RAW, &t_end);
		end = rdtscp(NULL);
		ns = ((t_end.tv_sec - t_start.tv_sec) * 1E9);
		ns += (t_end.tv_nsec - t_start.tv_nsec);

		secs = (double)ns / 1000;
		cycles_per_us = (uint64_t)((end - start) / secs);
		debug("time: detected %lu ticks / us", cycles_per_us);
		return 0;
	}
	return -1;
}

/* spins the CPU for the specified delay */
void time_delay_ns(uint64_t ns)
{
    ASSERT(ns >= 1000);  /*dont want to trust it for durations less than a µs*/
	unsigned long start = rdtsc();
    /*compute cycles inside the waiting period to avoid overhead*/
	uint64_t cycles = (uint64_t)((double) ns * cycles_per_us / 1000.0); 
	while (rdtsc() - start < cycles)
		cpu_relax();
}

/* spins the CPU for the specified delay */
void time_delay_us(uint64_t us)
{
	uint64_t cycles = us * cycles_per_us;
	unsigned long start = rdtsc();
	while (rdtsc() - start < cycles)
		cpu_relax();
}

/* Adds 32ns overhead in the average case. People have 
 * reported tail of upto 20µs though. */
unsigned long time_now_ns() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * BILLION + ts.tv_nsec;
}

/* pin this thread to a particular core */
int pin_thread(int core) {
  cpu_set_t cpuset;
  CPU_ZERO(&cpuset);
  CPU_SET(core, &cpuset);
  int retcode = pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
  if (retcode) { 
      errno = retcode;
      perror("pthread_setaffinitity_np");
  }
  return retcode;
}

void* reqcore_main(void* args) {
    int i, idx, core;
    int req_idx[MAX_APP_CORES] = {0};
    uint64_t posted = 0, serviced = 0;

    struct thread_args * targs = (struct thread_args *)args;
    pthread_setname_np(pthread_self(), targs->name);
    ASSERTZ(pin_thread(targs->core));

    sleep(1);   /*for other threads to be ready*/

    uint64_t start = time_now_ns(), elapsed;
    uint64_t start_tsc = rdtsc(), elapsed_tsc;
    while(1) {
        for (core = 0; core < num_app_cores; core++) {
            idx = req_idx[core];
            switch (reqs[core][idx].state) {
            case DONE:
                serviced++;
            case NONE:
                reqs[core][idx].hitratio = hit_ratio;
                reqs[core][idx].state = POSTED;      /*send it off*/
                posted++;
                break;
            }
            idx = (idx + 1) % REQ_QUEUE_DEPTH;
            req_idx[core] = idx;
        }
        elapsed_tsc = rdtsc() - start_tsc;
        if (elapsed_tsc / cycles_per_us > RUN_DURATION_SECS * MILLION)
            break;
    }
    elapsed = time_now_ns() - start;
    printf("%d,%.1lf,%d,%d,%lu,%lu\n", num_app_cores, hit_ratio, 
        service_time_ns, fault_time_ns,
        posted * BILLION / elapsed, 
        konafaults * BILLION / elapsed);
    // printf("per core: ");
    // for (i = 0; i < num_app_cores; i++) printf("%lu ", stats[i].serviced * BILLION / elapsed);
    // printf("\n");
}

struct token_bucket {
    int MAX_TOKENS;         /*bucket size*/
    int TOKEN_RATE;         /*token replenish rate*/
    double tokens; 
    uint64_t last_check_tsc;
};
static inline int bucket_get_token_at(struct token_bucket* bucket, uint64_t time_tsc) {
    uint64_t elapsed_tsc = time_tsc - bucket->last_check_tsc;
    bucket->last_check_tsc = time_tsc;

    bucket->tokens += elapsed_tsc * bucket->TOKEN_RATE * 1.0 / (cycles_per_us * MILLION);
    if (bucket->tokens > bucket->MAX_TOKENS)
        bucket->tokens = bucket->MAX_TOKENS;

    if (bucket->tokens < 1) return 0;
    bucket->tokens--;
    return 1;
}
static inline int bucket_get_token(struct token_bucket* bucket) {
    uint64_t now_tsc = rdtsc();
    return bucket_get_token_at(bucket, now_tsc);
}

void* konacore_main(void* args) {
    int i, idx, core;
    int faultq_idx[MAX_APP_CORES] = {0};
    uint64_t received = 0, serviced = 0, now_tsc, response_time_tsc;
    uint64_t fault_time_tsc = (uint64_t)((fault_time_ns * cycles_per_us) / 1000.0);
    uint64_t upcall_time_tsc = (uint64_t)((upcall_time_ns * cycles_per_us) / 1000.0);

    struct thread_args * targs = (struct thread_args *)args;
    pthread_setname_np(pthread_self(), targs->name);
    ASSERTZ(pin_thread(targs->core));

    struct token_bucket kona;
    kona.MAX_TOKENS = use_upcalls ? num_app_cores : 1;    /*burst size*/
    kona.TOKEN_RATE = kona_fault_rate;
    kona.last_check_tsc = rdtsc();
    kona.tokens = kona.MAX_TOKENS;
    
    while(1) {
        for (core = 0; core < num_app_cores; core++) {
            idx = faultq_idx[core];
            switch (faults[core][idx].state) {
            case POSTED:
                received++;
                faults[core][idx].state = STARTED;
            case STARTED:
                /* ratelimiting traffic to simulate kona bandwidth */
                now_tsc = rdtsc();
                if (bucket_get_token_at(&kona, now_tsc)) {
                    faults[core][idx].start_tsc = now_tsc;
                    faults[core][idx].state = RATELIMITED;
                }
                break;
            case RATELIMITED:
                /* return if finished */
                response_time_tsc = use_upcalls ? upcall_time_tsc : fault_time_tsc;
                if (rdtsc() - faults[core][idx].start_tsc > response_time_tsc) {
                    faults[core][idx].state = DONE;
                    idx = (idx + 1) % FAULT_QUEUE_DEPTH;
                    faultq_idx[core] = idx;
                    serviced++;
                    konafaults++;  /*global*/
                }
            }
        }
    }
}

void* appcore_main(void* args) {
    int i, ridx = 0, fidx = 0, self, hit;
    unsigned int self_seed = time(NULL) ^ getpid() ^ pthread_self();
    uint64_t fault_time_tsc = (uint64_t)((fault_time_ns * cycles_per_us) / 1000.0);

    struct thread_args * targs = (struct thread_args *)args;
    pthread_setname_np(pthread_self(), targs->name);
    ASSERTZ(pin_thread(targs->core));
    self = targs->thread_id;

    while(1) {
        switch (reqs[self][ridx].state) {
        case POSTED:
            stats[self].received++; 

            hit = (rand_r(&self_seed) % 1000) < (reqs[self][ridx].hitratio * 1000);
            if(!hit) {
                /* issue new fault on miss */
                ASSERT(faults[self][fidx].state == NONE || faults[self][fidx].state == DONE);
                faults[self][fidx].state = POSTED;      /*send it off*/
                while(faults[self][fidx].state != DONE) /*and wait*/
                    cpu_relax();

                if (use_upcalls) {
                    /*wait for page fault if returned with an upcall*/
                    reqs[self][ridx].wait_start_tsc = rdtsc();
                    reqs[self][ridx].state = FAULT_WAIT;
                    break; 
                }
            }
            /* intentionally skipping break */
        case SERVICING:
            time_delay_ns(service_time_ns);     /*emulating request cpu time*/
            reqs[self][ridx].state = DONE;              /*return request*/
            stats[self].serviced++;
            break;
        case FAULT_WAIT:
            if (rdtsc() - reqs[self][ridx].wait_start_tsc > fault_time_tsc) {
                reqs[self][ridx].state = SERVICING;
            }
            break;
        }
        ridx = (ridx + 1) % REQ_QUEUE_DEPTH;
    }
}

int main(int argc, char** argv) {
    int i, coreidx = 0;
    double upcall_fraction;

    /* Init */
    ASSERT(sizeof(req_entry) == CACHE_LINE_SIZE);
    ASSERT(sizeof(fault_entry) == CACHE_LINE_SIZE);
    ASSERT(sizeof(stat_entry) == CACHE_LINE_SIZE);
    ASSERTZ(time_calibrate_tsc());
    srand(time(0));

    /* Parse & validate args */
    if (argc != 8) {
        printf("Invalid args\n");
        printf("Usage: %s <cores> <kona_bw> <th(ns)> <tp(ns)> <hitr> <up> <tup>\n", argv[0]);
        return 1;
    }
    num_app_cores = atoi(argv[1]);
    kona_fault_rate = atoi(argv[2]);  
    service_time_ns = atoi(argv[3]);
    fault_time_ns = atoi(argv[4]);
    hit_ratio = atof(argv[5]);
    use_upcalls = atoi(argv[6]);
    upcall_time_ns = atoi(argv[7]);
    ASSERT(num_app_cores > 0 || num_app_cores <= MAX_APP_CORES);
    ASSERT(service_time_ns >= 1000);    /*cannot support sub-µs precision*/
    ASSERT(fault_time_ns >= 1000);      /*cannot support sub-µs precision*/
    ASSERT(kona_fault_rate > 0 || kona_fault_rate <= MILLION); 
    ASSERT(use_upcalls == 0 || use_upcalls == 1);   /*expectig boolean*/
    ASSERT(!use_upcalls || upcall_time_ns >= 1000);      /*cannot support sub-µs precision*/

    /* Start request generator */
    struct thread_args gargs;
    gargs.name = "reqcore";
    gargs.thread_id = -1;
    ASSERT(coreidx < MAX_CORES);
    gargs.core = CORELIST[coreidx++];
    pthread_create(&reqcore, NULL, reqcore_main, (void*)&gargs);

    /* Start kona backend */
    struct thread_args kargs;
    kargs.name = "konacore";
    kargs.thread_id = -1;
    ASSERT(coreidx < MAX_CORES);
    kargs.core = CORELIST[coreidx++];
    pthread_create(&konacore, NULL, konacore_main, (void*)&kargs);

    /* Start app cores */
    struct thread_args appargs[MAX_APP_CORES];
    for (i = 0; i < num_app_cores; i++) {
        appargs[i].name = "appcore";
        appargs[i].thread_id = i;
        ASSERT(coreidx < MAX_CORES);
        appargs[i].core = CORELIST[coreidx++];
        pthread_create(&appcores[i], NULL, appcore_main, (void*)&appargs[i]);
    }

    pthread_join(reqcore, NULL);

    return 0;
}