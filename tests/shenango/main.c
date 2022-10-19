
#include <stdio.h>
#include <unistd.h>
#include <math.h>

#include "base/time.h"
#include "runtime/thread.h"
#include "runtime/sync.h"
#include "runtime/pgfault.h"
#include "runtime/timer.h"
#include "runtime/rmem.h"
#include "rmem/common.h"
#include "utils.h"

#define RUNTIME_SECS 10
#define NUM_LAT_SAMPLES 5000
#define MAX_XPUT 	1000000
#define MAX_MEMORY	68719476736		// 64 GB

#ifdef LATENCY
#define BATCH_SIZE 1
#else 
#define BATCH_SIZE 1024
#endif

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
    void* addr;
	int rdahead;
    unsigned long rand_num;
    uint64_t start_tsc;
    uint64_t end_tsc;
	uint64_t pad[3];
};
typedef struct thread_data thread_data_t;
BUILD_ASSERT((sizeof(thread_data_t) % CACHE_LINE_SIZE == 0));

waitgroup_t workers;

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
void thread_main(void* arg) {
	thread_data_t* args = (thread_data_t*)arg;
	enum fault_op op = FO_READ;
	char tmp;
	unsigned long addr;
	if (args->start_tsc > 0)
		args->start_tsc = rdtsc();

	/* figure out fault kind and operation */
#ifdef FAULT_OP
	op = (enum fault_op) FAULT_OP;
#endif
	if (op == FO_RANDOM)
		op = (args->rand_num & (1<<16)) ? FO_READ : FO_WRITE;

	/* point to a random offset in the page */
	addr = (unsigned long) args->addr + (args->rand_num & _PAGE_OFFSET_MASK);
	addr &= ~0x7;	/* 64-bit align */

	/* perform access/trigger fault */
	switch (op) {
		case FO_READ:
			hint_read_fault_rdahead((void*)addr, args->rdahead);
			tmp = *(char*)(void*)addr;
			break;
		case FO_WRITE:
			hint_write_fault_rdahead((void*)addr, args->rdahead);
			*(char*)(void*)addr = tmp;
			break;
		case FO_READ_WRITE:
			hint_write_fault_rdahead((void*)addr, args->rdahead);
			tmp = *(char*)(void*)addr;
			*(char*)(void*)addr = tmp;
			break;
		default:
			BUG();	/* bug */
	}

	log_debug("thread %lx done", (unsigned long) args->addr);
	args->end_tsc = rdtscp(NULL);
	waitgroup_add(&workers, -1);	/* signal done */
}

/* main thread called into by shenango runtime */
void main_handler(void* arg) {
	void* region;
	region = heap_alloc(MAX_MEMORY);
	ASSERT(region != NULL);
	log_info("region start at %p, size %lu", region, MAX_MEMORY);
	waitgroup_init(&workers);
	ASSERT(cycles_per_us);

	int ret, i, j, samples = 0;
	int sample_in_batch = -1;
	int rdahead, rdahead_skip;
	uint64_t start_tsc, duration_tsc, now_tsc, count = 0, batches = 0;
	uint64_t latencies[NUM_LAT_SAMPLES], next_sample = 0;
	unsigned long randomness;
	struct rand_state rand;
	double duration_secs;
	double sampling_rate = (NUM_LAT_SAMPLES * BATCH_SIZE * 1.0 / (RUNTIME_SECS * MAX_XPUT));
	void* start = region;
	thread_data_t* targs = aligned_alloc(CACHE_LINE_SIZE,
		BATCH_SIZE * sizeof(thread_data_t));

	/* figure out read ahead */
	rdahead = rdahead_skip = 0;
#ifdef RDAHEAD
	rdahead = RDAHEAD;
	log_info("setting read ahead %d", RDAHEAD);
#endif
	assert(rdahead >= 0);

	unsigned long batch_offset = (MAX_MEMORY / BATCH_SIZE);
	BUILD_ASSERT(MAX_MEMORY % BATCH_SIZE == 0);

	ASSERTZ(rand_seed(&rand, time(NULL)));
	start_tsc = rdtsc();
	while(start < (region + batch_offset)) {
		now_tsc = rdtsc();
#ifdef LATENCY
		sample_in_batch = -1;
		if (batches >= next_sample) {
			randomness = rand_next(&rand);
			next_sample = batches + next_poisson_time(sampling_rate, randomness);
			sample_in_batch = randomness % BATCH_SIZE;
		}
#endif
		for (i = 0; i < BATCH_SIZE; i++) {
			/* init batch */
			BUG_ON(start >= (region + batch_offset));
			targs[i].addr = start + i * batch_offset;
			targs[i].rdahead = !rdahead_skip ? rdahead : 0;
			targs[i].rand_num = 0;	//rand_next(&rand);
			targs[i].start_tsc = sample_in_batch == i ? now_tsc : 0;
			targs[i].end_tsc = 0;
		}

		/* params for next batch */
		start += _PAGE_SIZE;
		if(rdahead_skip-- <= 0)
			rdahead_skip = rdahead;

		/* start batch */
		for (j = 0; j < i; j++) {
			waitgroup_add(&workers, 1);
			ret = thread_spawn(thread_main, &targs[j]);
			ASSERTZ(ret);
		}

		/* yield & wait until the batch is done */
		waitgroup_wait(&workers);
		count += i;
		batches++;

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
		if (count >= 10 * BATCH_SIZE)
			break;	/*break sooner when debugging*/
#endif

		if ((start - region) % 1073741824 == 0)
			log_info("%ld gigs done", (start - region) / 1073741824);

		/* is it time to stop? */
		duration_tsc = rdtscp(NULL) - start_tsc;
		duration_secs = duration_tsc / (1000000.0 * cycles_per_us);
		if (duration_secs >= RUNTIME_SECS)
			break;
	}
	log_info("ran for %.1lf secs with %.0lf ops /sec", 
		duration_secs, count / duration_secs);
	printf("result:%.0lf\n", count / duration_secs);
	save_number_to_file("result", count / duration_secs);
	sleep(1);

	/* dump latencies to file */
	if (samples > 0) {
		FILE* outfile = fopen("latencies", "w");
		if (outfile == NULL)
			log_warn("could not write to latencies file");
		else {
			fprintf(outfile, "latency\n");
			for (i = 0; i < samples; i++)
				fprintf(outfile, "%.3lf\n", latencies[i] * 1.0);
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