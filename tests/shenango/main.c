
#include <stdio.h>
#include <unistd.h>
#include <math.h>

#include "logging.h"
#include "runtime/thread.h"
#include "runtime/sync.h"
#include "runtime/pgfault.h"
#include "runtime/timer.h"
#include "utils.h"

#define MEM_REGION_SIZE ((1ull<<30) * 32)	//32 GB
#define RUNTIME_SECS 10
#define NUM_LAT_SAMPLES 5000
#define BATCH_SIZE 64
BUILD_ASSERT(!(BATCH_SIZE & (BATCH_SIZE-1)));	/* power of 2 */

#ifdef WITH_KONA
#define heap_alloc rmalloc
#else 
#define heap_alloc malloc
#endif

enum fault_kind {
	FK_NORMAL = 0,
	FK_APPFAULT,
	FK_MIXED
};

enum fault_op {
	FO_READ = 0,
	FO_WRITE,
	FO_READ_WRITE,
	FO_RANDOM
};

struct thread_data {
    void* addr;
    unsigned long rand_num;
    uint64_t start_tsc;
    uint64_t end_tsc;
	uint64_t pad[4];
};
typedef struct thread_data thread_data_t;
BUILD_ASSERT((sizeof(thread_data_t) % CACHE_LINE_SIZE == 0));

uint64_t cycles_per_us;
waitgroup_t workers;

int global_pre_init(void) 	{ return 0; }
int perthread_init(void)   	{ return 0; }
int global_post_init(void) 	{ return 0; }

double next_poisson_time(double rate, unsigned long randomness)
{
    return -logf(1.0f - ((double)(randomness % RAND_MAX)) / (double)(RAND_MAX)) / rate;
}

/* work for each user thread */
void thread_main(void* arg) {
	thread_data_t* args = (thread_data_t*)arg;
	enum fault_kind kind = FK_NORMAL;
	enum fault_op op = FO_READ;
	char tmp;
	if (args->start_tsc > 0)
		args->start_tsc = rdtsc();

	/* figure out fault kind and operation */
#ifdef FAULT_KIND
	kind = (enum fault_kind) FAULT_KIND;
#endif
#ifdef FAULT_OP
	op = (enum fault_op) FAULT_OP;
#endif
	if (kind == FK_MIXED)	
		kind = (args->rand_num & 1) ? FK_APPFAULT : FK_NORMAL;
	if (op == FO_RANDOM)
		op = (args->rand_num & (1<<16)) ? FO_READ : FO_WRITE;

	/* perform access/trigger fault */
	switch (op) {
		case FO_READ:
			if (kind == FK_APPFAULT)
				possible_read_fault_on(args->addr);
			tmp = *(char*)args->addr;
			break;
		case FO_WRITE:
			if (kind == FK_APPFAULT)
				possible_write_fault_on(args->addr);
			*(char*)args->addr = tmp;
			break;
		case FO_READ_WRITE:
			if (kind == FK_APPFAULT)
				possible_write_fault_on(args->addr);
			tmp = *(char*)args->addr;
			*(char*)args->addr = tmp;
			break;
		default:
			ASSERT(0);	/* bug */
	}

	pr_debug("thread %lx done", (unsigned long) args->addr);
	args->end_tsc = rdtsc();
	waitgroup_add(&workers, -1);	/* signal done */
}

/* main thread called into by shenango runtime */
void main_handler(void* arg) {
	void* region;
	region = heap_alloc(MEM_REGION_SIZE);
	ASSERT(region != NULL);
	pr_info("region start at %p, size %llu", region, MEM_REGION_SIZE);
	waitgroup_init(&workers);

	int ret, i, j, samples = 0;
	int sample_in_batch = -1;
	uint64_t start_tsc, duration_tsc, now_tsc, count = 0;
	uint64_t latencies[NUM_LAT_SAMPLES], next_tsc = 0;
	unsigned long randomness;
	struct rand_state rand;
	double duration_secs;
	double sampling_rate = (NUM_LAT_SAMPLES * 1.0 / (RUNTIME_SECS * 1e6 * cycles_per_us));
	void* start = region;
	thread_data_t* targs = aligned_alloc(CACHE_LINE_SIZE,
		BATCH_SIZE * sizeof(thread_data_t));

	ASSERTZ(rand_seed(&rand, time(NULL)));
	start_tsc = rdtsc();
	while(start < (region + MEM_REGION_SIZE)) {
		now_tsc = rdtsc();
#ifdef LATENCY
		sample_in_batch = -1;
		if (now_tsc - start_tsc >= next_tsc) {
			randomness = rand_next(&rand);
			next_tsc = (now_tsc - start_tsc) + 
				next_poisson_time(sampling_rate, randomness);
			sample_in_batch = randomness & (BATCH_SIZE-1);
		}
#endif
		for (i = 0; i < BATCH_SIZE; i++) {
			/* init batch */
			targs[i].addr = (void*) start;
			targs[i].rand_num = rand_next(&rand);
			targs[i].start_tsc = sample_in_batch == i ? now_tsc : 0;
			targs[i].end_tsc = 0;
			start += PAGE_SIZE;
			if (start >= (region + MEM_REGION_SIZE))
				break;
		}

		/* start batch */
		for (j = 0; j < i; j++) {
			waitgroup_add(&workers, 1);
			ret = thread_spawn(thread_main, &targs[j]);
			ASSERTZ(ret);
		}

		/* yield & wait until the batch is done */
		waitgroup_wait(&workers);
		count += i;

#ifdef LATENCY
		/* note down latencies of the batch */
		for (j = 0; j < i; j++) {
			if (samples < NUM_LAT_SAMPLES && targs[j].start_tsc > 0) {
				latencies[samples] = (targs[j].end_tsc - targs[j].start_tsc);
				samples++;
			}
		}
#endif

#ifdef DEBUG
		if (count >= 2 * BATCH_SIZE)
			break;	/*break sooner when debugging*/
#endif

		/* is it time to stop? */
		duration_tsc = rdtscp(NULL) - start_tsc;
		duration_secs = duration_tsc / (1000000.0 * cycles_per_us);
		if (duration_secs >= RUNTIME_SECS)
			break;
	}
	pr_info("ran for %.1lf secs with %.0lf ops /sec", 
		duration_secs, count / duration_secs);
	printf("result:%.0lf\n", count / duration_secs);

	/* dump latencies to file */
	if (samples > 0) {
		FILE* outfile = fopen("latencies", "w");
		if (outfile == NULL)
			pr_warn("could not write to latencies file");
		else {
			fprintf(outfile, "latency\n");
			for (i = 0; i < samples; i++)
				fprintf(outfile, "%.1lf\n", latencies[i] * 1.0 / cycles_per_us);
			fclose(outfile);
			pr_info("Wrote %d sampled latencies", samples);
		}
	}
}

int main(int argc, char *argv[]) {
	int ret;

	if (argc < 2) {
		pr_err("arg must be config file\n");
		return -EINVAL;
	}
	cycles_per_us = time_calibrate_tsc();
	printf("time calibration - cycles per µs: %lu\n", cycles_per_us);

#ifdef WITH_KONA
	/*shenango includes kona init with runtime; just set params */
	char env_var[200];
	sprintf(env_var, "MEMORY_LIMIT=%llu", MEM_REGION_SIZE);	
	putenv(env_var);	/*32gb, BIG to avoid eviction*/
	putenv("EVICTION_THRESHOLD=1");			/*32gb, BIG to avoid eviction*/
	putenv("EVICTION_DONE_THRESHOLD=1");	/*32gb, BIG to avoid eviction*/
#endif

    ret = runtime_set_initializers(global_pre_init, perthread_init, global_post_init);
	ASSERTZ(ret);

	ret = runtime_init(argv[1], main_handler, NULL);
	ASSERTZ(ret);
	return 0;
}