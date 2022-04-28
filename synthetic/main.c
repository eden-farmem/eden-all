
#include <stdio.h>
#include <unistd.h>
#include <math.h>

#include "logging.h"
#include "runtime/thread.h"
#include "runtime/sync.h"
#include "runtime/pgfault.h"
#include "runtime/timer.h"
#include "utils.h"
#include "hopscotch.h"
#include "snappy.h"

#define MEM_REGION_SIZE ((1ull<<30) * 32)	//32 GB
#define RUNTIME_SECS 10
#define NUM_LAT_SAMPLES 5000
#define MAX_BLOB_SIZE (2*PAGE_SIZE)

#ifdef WITH_KONA
#define remoteable_alloc rmalloc
#else 
#define remoteable_alloc malloc
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

struct thread_args {
    int tid;
	uint64_t pad[14];
} CACHE_ALIGN;
typedef struct thread_args thread_args_t;
BUILD_ASSERT((sizeof(thread_args_t) % CACHE_LINE_SIZE == 0));

struct main_args {
	int nworkers;
};

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
	int ret;
	thread_args_t* args = (thread_args_t*)arg;

	char* snappy_in = malloc(MAX_BLOB_SIZE);
	ASSERT(snappy_in != NULL);

	struct snappy_env env;
	snappy_init_env(&env);
	size_t out_len = snappy_max_compressed_length(MAX_BLOB_SIZE);
	char* snappy_out = malloc(out_len);
	ASSERT(snappy_out != NULL);
	ret = snappy_compress(&env, snappy_in, MAX_BLOB_SIZE, snappy_out, &out_len);
	pr_debug("snappy compression done. out len: %lu", out_len);
	
	/* app work */

	pr_debug("worker %lx done", (unsigned long) args->tid);
	waitgroup_add(&workers, -1);	/* signal done */
}

/* main thread called into by shenango runtime */
void main_handler(void* arg) {
	int j, ret;
	struct main_args* margs = (struct main_args*) arg;
	thread_args_t* targs = aligned_alloc(CACHE_LINE_SIZE, margs->nworkers * sizeof(thread_args_t));

	/* init hash table */
	struct hopscotch_hash_table *ht;
    ht = hopscotch_init(NULL, 8);
    ASSERT(ht != NULL);

	/* start workers and wait */
	waitgroup_init(&workers);
	for (j = 0; j < margs->nworkers; j++) {
		targs[j].tid = j;
		waitgroup_add(&workers, 1);
		ret = thread_spawn(thread_main, &targs[j]);
		ASSERTZ(ret);
	}
	waitgroup_wait(&workers);

    /* Release */
    hopscotch_release(ht);
}

int main(int argc, char *argv[]) {
	int ret;

	if (argc < 3) {
		pr_err("USAGE: %s <config-file> <nworkers>\n", argv[0]);
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

	struct main_args margs;
	margs.nworkers = atoi(argv[2]);
	ret = runtime_init(argv[1], main_handler, &margs);
	ASSERTZ(ret);
	return 0;
}