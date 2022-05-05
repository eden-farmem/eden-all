
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
#include "zipf.h"
#include "aes.h"

#define MEM_REGION_SIZE 	((1ull<<30) * 32)	// 32 GB
#define NUM_LAT_SAMPLES 	5000
#define BLOB_SIZE 			((unsigned long)2*PAGE_SIZE)
#define AES_KEY_SIZE 		128

/* these decide how long the experiment runs and how many 
 * requests to generate. Adjust maximum expected performance 
 * per core (MAX_MOPS_PER_CORE) to limit the time spent in 
 * generating input workload  */
#define MILLION				1000000
#define MAX_MOPS_PER_CORE	(10*MILLION)			
// #define MAX_MOPS_PER_CORE	10000			
#define MIN_RUNTIME_SECS 	5	
#define MAX_RUNTIME_SECS 	20
#ifdef DEBUG
#undef MAX_MOPS_PER_CORE
#define MAX_MOPS_PER_CORE	10	
#endif

struct thread_args {
    int tid;
	unsigned long nkeys;
	unsigned long nreqs;
	unsigned long start;
	unsigned long len;
	unsigned long xput;
	uint32_t pad[4];
};
typedef struct thread_args thread_args_t;
BUILD_ASSERT((sizeof(thread_args_t) % CACHE_LINE_SIZE == 0));

struct main_args {
	int ncores;
	int nworkers;
	int nkeys;
	unsigned long nreqs;
	double zparams;
};

uint64_t cycles_per_us;
waitgroup_t workers;
barrier_t ready, go;
int stop_button = 0;
struct hopscotch_hash_table *ht;
void* blobdata;
uint64_t* zipf_sequence;
uint32_t* zipf_counts;
double zparams;
WORD aes_ksched[60];
BYTE aes_iv[16] = {
	0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
	0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f 
};
BYTE aes_key[32] = {
	0x60,0x3d,0xeb,0x10,0x15,0xca,0x71,0xbe,
	0x2b,0x73,0xae,0xf0,0x85,0x7d,0x77,0x81,
	0x1f,0x35,0x2c,0x07,0x3b,0x61,0x08,0xd7,
	0x2d,0x98,0x10,0xa3,0x09,0x14,0xdf,0xf4
};

double next_poisson_time(double rate, unsigned long randomness)
{
    return -logf(1.0f - ((double)(randomness % RAND_MAX)) / (double)(RAND_MAX)) / rate;
}

/* prepare hash table and blob-array */
void setup(void* arg) {
	int ret, i, j;
	unsigned long key, offset;
	uint64_t rand_num, repeat = 0;
	void* data;
	thread_args_t* targs = (thread_args_t*)arg;
	struct rand_state rand;
	ASSERTZ(rand_seed(&rand, time(NULL) ^ targs->tid));

	/* TODO: should I make the keys more complicated? */
    uint8_t key_template[KEY_LEN] = {
		0x00, 0x00, 0x00, 0x00,
		0xff, 0xff, 0xff, 0xff,
		0xff, 0xff, 0xff, 0xff };

	/* push keys & data */
	ASSERT(targs->start + targs->len <= targs->nkeys);
	for (i = 0; i < targs->len; i++)	{
		key = targs->start + i;
		*(uint32_t*)key_template = key;
		/* push a key */
		pr_debug("worker %d adding key %lu", targs->tid, key);
		ret = hopscotch_insert(ht, key_template, (void*) key);
		ASSERTZ(ret);
		/* add random data at corresponding index in blob array */
		BUILD_ASSERT(BLOB_SIZE % sizeof(uint64_t) == 0);
		for (j = 0; j < BLOB_SIZE / sizeof(uint64_t); j++) {
			if (repeat == 0){
				/* random patterns for varying compression */
				repeat = rand_next(&rand) % 100;
				rand_num = rand_next(&rand);
			}
			offset = i*BLOB_SIZE + j*sizeof(uint64_t);
			*(uint64_t*)(blobdata + offset) = rand_num;
			repeat--;
		}
	}
	pr_info("worker %d added %d keys", targs->tid, i);
	waitgroup_add(&workers, -1);	/* signal done */
}

/* prepare zipf workload */
void prepare_workload(void* arg) {
	int i;
	unsigned long ret;
	thread_args_t* targs = (thread_args_t*)arg;
	ZIPFIAN z = create_zipfian(zparams, targs->nkeys, time(NULL)^targs->tid);

	/* generated requests for my section */
	ASSERT(targs->start + targs->len <= targs->nreqs);
	for (i = 0; i < targs->len; i++)	{
		ret = zipfian_gen(z);
		ASSERT(0 <= ret && ret < targs->nkeys);
		*(zipf_sequence + targs->start + i) = ret;
#ifdef DEBUG
		zipf_counts[ret]++;
#endif
	}

	pr_info("worker %d generated %d requests", targs->tid, i);
	destroy_zipfian(z);
	waitgroup_add(&workers, -1);	/* signal done */
}

/* process requests */
void run(void* arg) {
	int ret, i, key;
	void *data, *nextin;
	unsigned long start_tsc, duration_tsc;
	thread_args_t* targs = (thread_args_t*)arg;
    uint8_t key_template[KEY_LEN] = {
		0x00, 0x00, 0x00, 0x00,
		0xff, 0xff, 0xff, 0xff,
		0xff, 0xff, 0xff, 0xff };

	/* crypto init */
	char* encbuffer = malloc(BLOB_SIZE);
	ASSERT(encbuffer);

	/* snappy init */
	struct snappy_env env;
	ASSERTZ(snappy_init_env(&env));
	size_t ziplen = snappy_max_compressed_length(BLOB_SIZE);
	pr_debug("max zip len: %lu", ziplen);
	char* zipbuffer = malloc(ziplen);
	ASSERT(zipbuffer);
	FILE* fp;
	char fname[50];

	/* wait for all threads to be ready */
	ASSERT(targs->start + targs->len <= targs->nreqs);
	pr_info("worker %d starting at request %lu len %lu", 
		targs->tid, targs->start, targs->len);

	barrier_wait(&ready);
	barrier_wait(&go);
	start_tsc = rdtsc();

	for (i = 0; i < targs->len && !stop_button; i++) {
		/* get the array index from hash table */
		/* we just save the key as value which is ok for benchmarking purposes */
		key = zipf_sequence[targs->start + i];
		*(uint32_t*)key_template = key;
		data = hopscotch_lookup(ht, key_template);
		// ASSERT((unsigned long)data == key);
		if ((unsigned long)data != key) {
			pr_err("ht corruption. expected: %u actual: %lu",
				key, (unsigned long)data);
			ASSERT(0);
		}
		nextin = blobdata + key * BLOB_SIZE;

#ifdef ENCRYPT
		/* encrypt data (emits same length as input) */
		ret = aes_encrypt_cbc(nextin, BLOB_SIZE, encbuffer, aes_ksched, AES_KEY_SIZE, aes_iv);
		ASSERT(ret);
		nextin = encbuffer;
#endif

#ifdef COMPRESS 
		/* compress the array element */
		ret = snappy_compress(&env, nextin, BLOB_SIZE, zipbuffer, &ziplen);
		ASSERTZ(ret);
		// pr_debug("snappy compression done. inlen: %ld outlen: %lu", BLOB_SIZE, ziplen);
		nextin = zipbuffer;
#endif

		targs->xput++;

		/* yield at least once every 1 sec */
		duration_tsc = rdtsc() - start_tsc;
		if (duration_tsc / (1000000.0 * cycles_per_us) >= 1) {
			thread_yield();
			start_tsc = rdtsc();
			pr_debug("worker %d at %lu ops", targs->tid, targs->xput);
		}
	}

	pr_debug("worker %d processed %ld requests", targs->tid, targs->xput);
	waitgroup_add(&workers, -1);	/* signal done */
}

/* issue stop signal on timeout */
void time_out(void* arg) {
	unsigned long sleep_us = (unsigned long) arg;
	timer_sleep(sleep_us);
	stop_button = 1;
}

/* main thread called into by shenango runtime */
void main_thread(void* arg) {
	int i, j, ret;
	struct main_args* margs = (struct main_args*) arg;
	int nkeys = margs->nkeys;
	unsigned long nreqs = margs->nreqs;
	int nworkers = margs->nworkers;
	thread_args_t* targs;
    uint8_t key_template[KEY_LEN] = {
		0x00, 0x00, 0x00, 0x00,
		0xff, 0xff, 0xff, 0xff,
		0xff, 0xff, 0xff, 0xff };
	uint64_t start_tsc, duration_tsc, now_tsc, xput = 0;
	double duration_secs;

	/* core data stuctures: these go in remote memory */
    ht = hopscotch_init(NULL, next_power_of_two(nkeys) + 1);
    ASSERT(ht);
	blobdata = remoteable_alloc(nkeys*BLOB_SIZE);
	ASSERT(blobdata);

	/* setup data */
	targs = aligned_alloc(CACHE_LINE_SIZE, nworkers * sizeof(thread_args_t));
	waitgroup_init(&workers);
	for (j = 0; j < nworkers; j++) {
		targs[j].tid = j;
		targs[j].nkeys = nkeys;
		targs[j].start = j * ceil(nkeys * 1.0 / nworkers);
		targs[j].len = min(ceil(nkeys * 1.0 / nworkers), nkeys - targs[j].start);
		waitgroup_add(&workers, 1);
		ret = thread_spawn(setup, &targs[j]);
		ASSERTZ(ret);
	}
	waitgroup_wait(&workers);
	pr_info("hash table/blob data setup done");

	/* print table */
	// void* data;
	// for (j = 0; j < nkeys; j++) {
	// 	*(uint32_t*)key_template = j;
	// 	data = hopscotch_lookup(ht, key_template);
	// 	pr_info("key %d: %lu", j, (unsigned long) data);
	// }

	/* aes init */
	aes_key_setup(aes_key, aes_ksched, AES_KEY_SIZE);

	/* prepare zipf request sequence  */	
	zparams = margs->zparams;
	zipf_sequence = (uint64_t*) malloc (nreqs * sizeof(uint64_t));
#ifdef DEBUG
	zipf_counts = (uint32_t*)calloc(nkeys, sizeof(uint32_t));
#endif
	waitgroup_init(&workers);
	for (j = 0; j < nworkers; j++) {
		targs[j].tid = j;
		targs[j].nkeys = nkeys;
		targs[j].nreqs = nreqs;
		targs[j].start = j * ceil(nreqs * 1.0 / nworkers);
		targs[j].len = min(ceil(nreqs * 1.0 / nworkers), nreqs - targs[j].start);
		waitgroup_add(&workers, 1);
		ret = thread_spawn(prepare_workload, &targs[j]);
		ASSERTZ(ret);
	}
	waitgroup_wait(&workers);
	pr_info("generated zipf sequence of length: %lu", nreqs);
#ifdef DEBUG
	// printf("zipf seq: ");
	// for (j = 0; j < nreqs; j++)	printf("%lu ", zipf_sequence[j]);
	printf("\ncounts: ");
	for (j = 0; j < nkeys; j++)	printf("%u ", zipf_counts[j]);
	printf("\n");
#endif

	/* run requests */
	waitgroup_init(&workers);
	barrier_init(&ready, nworkers+1);
	barrier_init(&go, nworkers+1);
	for (j = 0; j < nworkers; j++) {
		targs[j].tid = j;
		targs[j].nkeys = nkeys;
		targs[j].nreqs = nreqs;
		targs[j].start = j * ceil(nreqs * 1.0 / nworkers);
		targs[j].len = min(ceil(nreqs * 1.0 / nworkers), nreqs - targs[j].start);
		targs[j].xput = 0;
		waitgroup_add(&workers, 1);
		ret = thread_spawn(run, &targs[j]);
		ASSERTZ(ret);
	}
	
	/* wait for threads to be ready */
	barrier_wait(&ready); 		

	/* let go and issue time out */
	start_tsc = rdtsc();
	stop_button = 0;
	pr_info("run started");
	barrier_wait(&go);
	ret = thread_spawn(time_out, (void*) (MAX_RUNTIME_SECS * 1000000));
	ASSERTZ(ret);

	/* wait for threads to finish */
	waitgroup_wait(&workers);
	duration_tsc = rdtscp(NULL) - start_tsc;
	duration_secs = duration_tsc / (1000000.0 * cycles_per_us);

	/* write result */
	for (j = 0; j < nworkers; j++) xput += targs[j].xput;
	pr_info("ran for %.1lf secs with %.0lf ops /sec", duration_secs, xput/duration_secs);
	printf("result:%.0lf\n", xput / duration_secs);

	/* we must run for at least a few secs */
	ASSERT(duration_secs >= MIN_RUNTIME_SECS);

    /* Release */
    hopscotch_release(ht);
}

int main(int argc, char *argv[]) {
	int ret;

	if (argc < 4) {
		pr_err("USAGE: %s <config-file> <ncores> <nworkers> [<nkeys>] [<zipfparamS>]\n", argv[0]);
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
	margs.ncores = atoi(argv[2]);
	margs.nworkers = atoi(argv[3]);
	margs.nkeys = (argc > 4) ? atoi(argv[4]) : 1000000;
	margs.zparams = (argc > 5) ? atof(argv[5]) : 0.1;
	margs.nreqs = (margs.ncores * (unsigned long) MAX_MOPS_PER_CORE * MIN_RUNTIME_SECS);
	ret = runtime_init(argv[1], main_thread, &margs);
	ASSERTZ(ret);
	return 0;
}