
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

#if defined(VERBOSE)
#define DEBUG
#define verbose printf
#define debug printf
#elif defined(DEBUG)
#define verbose(fmt, ...) do {} while (0);
#define debug printf
#else
#define verbose(fmt, ...) do {} while (0);
#define debug(fmt, ...) do {} while (0);
#endif

#define MAX_CORES 28
#define MAX_WORKLOADS 3     /*no special reason, can go higher if needed*/
#define MAX_APP_CORES (MAX_CORES - MAX_WORKLOADS - 1)   /*one core each for workload generation, one core for kona*/
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

struct thread_result {
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

struct thread_data {
    int thread_id;
    char* name;
    int core;
    /* return values */
    uint64_t serviced;
    uint64_t runtime_ns;
    uint32_t pad[6];
} __aligned(CACHE_LINE_SIZE);

typedef struct {
    STATES state;
    uint64_t wait_start_tsc;
    uint32_t pad[12];
} req_entry __aligned(CACHE_LINE_SIZE);
req_entry reqs[MAX_WORKLOADS][MAX_APP_CORES][REQ_QUEUE_DEPTH] __aligned(CACHE_LINE_SIZE) = {0};

typedef struct {
    STATES state;
    uint64_t start_tsc;
    uint32_t pad[12];
} fault_entry __aligned(CACHE_LINE_SIZE);
fault_entry faults[MAX_APP_CORES][FAULT_QUEUE_DEPTH] __aligned(CACHE_LINE_SIZE) = {0};

typedef struct {
    double hitratio;
    int service_time_ns;
} workload_cfg;

/* read-only globals - strictly read-only within threads! */
pthread_barrier_t barrier;
pthread_t reqcores[MAX_WORKLOADS]; 
pthread_t konacore;
pthread_t appcores[MAX_APP_CORES];
int num_app_cores;
int fault_time_ns;
int kona_fault_rate;
int num_workloads;
workload_cfg workloads[MAX_WORKLOADS];
int best_workload;
int use_upcalls;
int upcall_time_ns;
int stop_app_cores = 0;
int stop_kona = 0;

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
		verbose("time: detected %lu ticks / us\n", cycles_per_us);
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

void print_array_atomic(char* prefix, uint64_t array[], int len) {
#ifdef DEBUG
    static pthread_mutex_t pmutex = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&pmutex);
    int i;
    printf("%s ", prefix);
    for (i = 0; i < len; i++) printf("%lu ", array[i]);
    printf("\n"); 
    pthread_mutex_unlock(&pmutex); 
#endif
}

void* reqcore_main(void* args) {
    int i, idx, core, self, ret;
    int req_idx[MAX_APP_CORES] = {0};
    uint64_t posted = 0, serviced = 0;
    uint64_t start, elapsed, start_tsc, elapsed_tsc;

    struct thread_data* tdata = (struct thread_data *)args;
    pthread_setname_np(pthread_self(), tdata->name);
    ASSERTZ(pin_thread(tdata->core));
    self = tdata->thread_id;

    sleep(1);   /*for all other threads to be ready*/
    ret = pthread_barrier_wait(&barrier);
    ASSERT(ret != EINVAL);   /*wait for other workload threads*/

    start = time_now_ns();
    start_tsc = rdtsc(), elapsed_tsc;
    while(1) {
        for (core = 0; core < num_app_cores; core++) {
            idx = req_idx[core];
            switch (reqs[self][core][idx].state) {
            case DONE:
                serviced++;
            case NONE:
                reqs[self][core][idx].state = POSTED;      /*send it off*/
                posted++;
                break;
            }
            idx = (idx + 1) % REQ_QUEUE_DEPTH;
            req_idx[core] = idx;
        }
        elapsed_tsc = rdtsc() - start_tsc;
        if (elapsed_tsc > cycles_per_us * RUN_DURATION_SECS * MILLION)
            break;
    }
    elapsed = time_now_ns() - start;

    tdata->serviced = serviced;
    tdata->runtime_ns = elapsed;
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
    uint64_t received[MAX_APP_CORES] = {0}, serviced[MAX_APP_CORES] = {0};
    uint64_t now_tsc, response_time_tsc;
    uint64_t fault_time_tsc = (uint64_t)((fault_time_ns * cycles_per_us) / 1000.0);
    uint64_t upcall_time_tsc = 0; // (uint64_t)((upcall_time_ns * cycles_per_us) / 1000.0);

    struct thread_data * tdata = (struct thread_data *)args;
    pthread_setname_np(pthread_self(), tdata->name);
    ASSERTZ(pin_thread(tdata->core));

    struct token_bucket kona;
    kona.MAX_TOKENS = use_upcalls ? num_app_cores : 1;    /*burst size*/
    kona.TOKEN_RATE = kona_fault_rate;
    kona.last_check_tsc = rdtsc();
    kona.tokens = kona.MAX_TOKENS;
    
    while(!stop_kona) {
        for (core = 0; core < num_app_cores; core++) {
            idx = faultq_idx[core];
            switch (faults[core][idx].state) {
            case POSTED:
                received[core]++;
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
                    serviced[core]++;
                }
            }
        }
    }
#ifdef DEBUG
    // printf("faults per core: ");
    // for (i = 0; i < num_app_cores; i++) printf("%lu ", serviced[i]);
    // printf("\n");
    print_array_atomic("faults per core: ", serviced, num_app_cores);
#endif
    for(i = 0; i < num_app_cores; i++)
        tdata->serviced += serviced[i];
}

void* appcore_main(void* args) {
    int i, ridx = 0, fidx = 0, self, hit, wkld;
    int usual_workload = -1;
    int faulting_on_usual_workload = 0, faulting_on_best_workload = 0;
    int req_idx[MAX_WORKLOADS] = {0};
    uint64_t received[MAX_WORKLOADS] = {0}, serviced[MAX_WORKLOADS] = {0};
    unsigned int self_seed = time(NULL) ^ getpid() ^ pthread_self();
    uint64_t fault_time_tsc = (uint64_t)((fault_time_ns * cycles_per_us) / 1000.0);
    
    struct thread_data * tdata = (struct thread_data *)args;
    pthread_setname_np(pthread_self(), tdata->name);
    ASSERTZ(pin_thread(tdata->core));
    self = tdata->thread_id;

    while(!stop_app_cores) {
        for (wkld = 0; wkld < num_workloads; wkld++) {
            ridx = req_idx[wkld];
            switch (reqs[wkld][self][ridx].state) {
            case POSTED:
                /*determine which workloads to schedule*/
#if defined(SPLIT_CORES) && defined(SWITCH_ON_FAULT)
                /*isolate cores but allow best workload on any core when 
                 *it is faulting*/
                usual_workload = self % num_workloads;
                if (faulting_on_usual_workload) {
                    if (wkld != best_workload)
                        break;
                    if (faulting_on_best_workload)
                        break;
                }
                else {
                    if (wkld != usual_workload)
                        break;
                }
#elif defined(SPLIT_CORES)
                /*in case of split cores, divide workloads b/w cores*/
                usual_workload = self % num_workloads;
                if (wkld != usual_workload)
                    break;
#elif defined(SWITCH_ON_FAULT)
                if (faulting_on_usual_workload) {
                    if (wkld != best_workload)
                        break;
                    if (faulting_on_best_workload)
                        break;
                }
#endif
                received[wkld]++; 
                hit = (rand_r(&self_seed) % 1000) < (workloads[wkld].hitratio * 1000);
                if(!hit) {
                    /* issue new fault on miss */
                    ASSERT(faults[self][fidx].state == NONE || faults[self][fidx].state == DONE);
                    faults[self][fidx].state = POSTED;      /*send it off*/
                    while(faults[self][fidx].state != DONE) /*and wait*/
                        cpu_relax();

                    if (use_upcalls) {
                        /*wait for page fault if returned with an upcall*/
                        reqs[wkld][self][ridx].wait_start_tsc = rdtsc();
                        reqs[wkld][self][ridx].state = FAULT_WAIT;
                        if (wkld != best_workload)  
                            faulting_on_usual_workload = 1;
                        else 
                            faulting_on_best_workload = 1;
                        break; 
                    }
                }
                /* intentionally skipping "break" (ironic that i had to add this 
                 * comment; is it really a feature if it reeks more of a bug?) */
            case SERVICING:
                time_delay_ns(workloads[wkld].service_time_ns); /*emulating request cpu time*/
                reqs[wkld][self][ridx].state = DONE;            /*return request*/
                serviced[wkld]++;
                break;
            case FAULT_WAIT:
                if (rdtsc() - reqs[wkld][self][ridx].wait_start_tsc > fault_time_tsc) {
                    if (wkld != best_workload)
                        faulting_on_usual_workload = 0;
                    else                        
                        faulting_on_best_workload = 0;
                    reqs[wkld][self][ridx].state = SERVICING;
                }
                break;
            }
            ridx = (ridx + 1) % REQ_QUEUE_DEPTH;
            req_idx[wkld] = ridx;
        }
    }

#ifdef DEBUG
    // printf("faults per core: ");
    // for (i = 0; i < num_app_cores; i++) printf("%lu ", serviced[i]);
    // printf("\n");
    char prefix[100];
    sprintf(prefix, "app core %d (wkld: %d): ", self, usual_workload);
    print_array_atomic(prefix, serviced, num_workloads);
#endif
    for(i = 0; i < num_workloads; i++)
        tdata->serviced += serviced[i];
}

int main(int argc, char** argv) {
    int i, coreidx = 0;
    double upcall_fraction;

    /* init */
    ASSERT(sizeof(req_entry) == CACHE_LINE_SIZE);
    ASSERT(sizeof(fault_entry) == CACHE_LINE_SIZE);
    ASSERT(sizeof(struct thread_data) == CACHE_LINE_SIZE);
    ASSERTZ(time_calibrate_tsc());
    srand(time(0));

    /* parse & validate args */
    if (argc != 8 && argc != 9) {
        printf("Invalid args\n");
        printf("Usage: %s <cores> <kona_bw> <th(ns)> <tp(ns)> <hitr> <up> <tup> [hitr2]\n", argv[0]);
        return 1;
    }
    num_app_cores = atoi(argv[1]);
    kona_fault_rate = atoi(argv[2]);  
    num_workloads = 1;
    workloads[0].service_time_ns = atoi(argv[3]);
    best_workload = 0;
    fault_time_ns = atoi(argv[4]);
    workloads[0].hitratio = atof(argv[5]);
    use_upcalls = atoi(argv[6]);
    upcall_time_ns = atoi(argv[7]);
    if (argc == 9) {
        num_workloads = 2;
        workloads[1].service_time_ns = atoi(argv[3]);
        workloads[1].hitratio = atof(argv[8]);
        if (workloads[1].hitratio > workloads[0].hitratio)
            best_workload = 1;
    }
    ASSERT(num_app_cores > 0 || num_app_cores <= MAX_APP_CORES);
    ASSERT(workloads[0].service_time_ns >= 1000);       /*cannot support sub-µs precision*/
    ASSERT(fault_time_ns >= 1000);                      /*cannot support sub-µs precision*/
    ASSERT(kona_fault_rate > 0 || kona_fault_rate <= MILLION); 
    ASSERT(use_upcalls == 0 || use_upcalls == 1);       /*expectig boolean*/
    ASSERT(!use_upcalls || upcall_time_ns >= 1000);      /*cannot support sub-µs precision*/

    /* start kona backend */
    struct thread_data konadata __aligned(CACHE_LINE_SIZE) = {0};
    stop_kona = 0;
    konadata.name = "konacore";
    konadata.thread_id = -1;
    ASSERT(coreidx < MAX_CORES);
    konadata.core = CORELIST[coreidx++];
    pthread_create(&konacore, NULL, konacore_main, (void*)&konadata);

    /* start app cores */
    struct thread_data appdata[MAX_APP_CORES] __aligned(CACHE_LINE_SIZE) = {0};
    stop_app_cores = 0;
    for (i = 0; i < num_app_cores; i++) {
        appdata[i].name = "appcore";
        appdata[i].thread_id = i;
        ASSERT(coreidx < MAX_CORES);
        appdata[i].core = CORELIST[coreidx++];
        pthread_create(&appcores[i], NULL, appcore_main, (void*)&appdata[i]);
    }

    /* start workload cores */
    struct thread_data reqdata[MAX_WORKLOADS] __aligned(CACHE_LINE_SIZE) = {0};
    ASSERTZ(pthread_barrier_init(&barrier, NULL, num_workloads));
    for (i = 0; i < num_workloads; i++) {
        reqdata[i].name = "reqcore";
        reqdata[i].thread_id = i;
        ASSERT(coreidx < MAX_CORES);
        reqdata[i].core = CORELIST[coreidx++];
        pthread_create(&reqcores[i], NULL, reqcore_main, (void*)&reqdata[i]);
    }

    /* wait for workload cores to finish */
    for (i = 0; i < num_workloads; i++)
        pthread_join(reqcores[i], NULL);

    /* now stop and wait for all cores */
    stop_app_cores = 1;
    stop_kona = 1;
    sleep(1);   /*FIXME use join() instead?*/

    /* results */
#ifdef DEBUG
    printf("per core: ");
    for (i = 0; i < num_app_cores; i++) printf("%lu ", appdata[i].serviced * BILLION / reqdata[0].runtime_ns);
    printf("\n");
#endif
    uint64_t total = 0, konarate;
    printf("%d,%d", num_app_cores, fault_time_ns);
    for(i = 0; i < num_workloads; i++) {
        uint64_t rate = reqdata[i].serviced * BILLION / reqdata[i].runtime_ns;
        printf(",%.1lf,%d,%lu", workloads[i].hitratio, workloads[i].service_time_ns, rate);
        total += rate;
    }
    konarate = konadata.serviced * BILLION / reqdata[0].runtime_ns;
    printf(",%lu,%lu\n", total, konarate);


    /* deinit */
    pthread_barrier_destroy(&barrier);

    return 0;
}