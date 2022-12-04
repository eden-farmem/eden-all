
#include <stdio.h>
#include <unistd.h>
#include <math.h>

#include "aes.h"
#include "common.h"
#include "logging.h"
#include "utils.h"
#include "hopscotch.h"
#include "snappy.h"
#include "zipf.h"

#define MEM_REGION_SIZE 	((1ull<<30) * 32)	// 32 GB
#define NUM_LAT_SAMPLES 	5000
#define BLOB_SIZE 			((unsigned long)2*PAGE_SIZE)
#define AES_KEY_SIZE 		128
#ifndef KEYS_PER_REQ
#define KEYS_PER_REQ 		1
#endif

/* these decide how long the experiment runs and how many 
 * requests to generate. Adjust maximum expected performance 
 * per core (MAX_OPS_PER_CORE) appropriately to generate 
 * enough requests to last for both the warmup (WARMUP_SECS) 
 * and the run (MIN_RUNTIME_SECS) but not spend too much time
 * in generating the workload */
#define MILLION				1000000
#define MAX_OPS_PER_CORE	(10*MILLION)			
// #define MAX_OPS_PER_CORE	10000			
#define WARMUP_SECS 		30	
#define MIN_RUNTIME_SECS 	5	
#define MAX_RUNTIME_SECS 	30
#ifdef DEBUG2
#undef MAX_OPS_PER_CORE
#define MAX_OPS_PER_CORE	10	
#endif

struct thread_args {
    int tid;
	unsigned long nkeys;
	unsigned long nblobs;
	unsigned long nreqs;
	unsigned long start;
	unsigned long len;
	unsigned long xput;
	uint32_t pad[2];
};
typedef struct thread_args thread_args_t;
BUILD_ASSERT((sizeof(thread_args_t) % CACHE_LINE_SIZE == 0));

struct main_args {
	int ncores;
	int nworkers;
	int nkeys;
	int nblobs;
	unsigned long nreqs;
	double zparams;
};

uint64_t CYCLES_PER_US;
WAITGROUP_T workers_wg;
BARRIER_T ready, warmup, warmedup, start;
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

/* save a number to a file */
void fwrite_number(char* name, unsigned long number) {
	FILE* fp = fopen(name, "w");
	fprintf(fp, "%lu", number);
	fflush(fp);
	fclose(fp);
}

/* save unix timestamp of a checkpoint */
void save_checkpoint(char* name) {
	fwrite_number(name, time(NULL));
}

/* prepare hash table */
#ifdef SHENANGO
void
#else 
void* 
#endif
setup_table(void* arg) {
	int ret, i;
	unsigned long key, val;
	thread_args_t* targs = (thread_args_t*)arg;
	struct syn_rand_state rand;
	ASSERTZ(syn_rand_seed(&rand, time(NULL) ^ targs->tid));

	/* TODO: should I make the keys more complicated? */
    uint8_t key_template[KEY_LEN] = {
		0x00, 0x00, 0x00, 0x00,
		0xff, 0xff, 0xff, 0xff,
		0xff, 0xff, 0xff, 0xff };

	/* push keys pointing to random blobs */
	ASSERT(targs->start + targs->len <= targs->nkeys);
	for (i = 0; i < targs->len; i++)	{
		key = targs->start + i;
		*(uint32_t*)key_template = key;
		val = syn_rand_next(&rand) % targs->nblobs;
		// val = key % targs->nblobs;		/* for easy verification */
		pr_debug("worker %d adding key %lu value %lu", targs->tid, key, val);
		ret = hopscotch_insert(ht, key_template, (void*) val);
		ASSERTZ(ret);
	}
	pr_info("worker %d added %d keys", targs->tid, i);
	WAITGROUP_ADD(workers_wg, -1);	/* signal done */
}

/* prepare blob array */
#ifdef SHENANGO
void
#else 
void* 
#endif
setup_blobs(void* arg) {
	int i, j;
	unsigned long key, offset;
	uint64_t rand_num, repeat = 0;
	thread_args_t* targs = (thread_args_t*)arg;
	struct syn_rand_state rand;
	ASSERTZ(syn_rand_seed(&rand, time(NULL) ^ targs->tid));

	ASSERT(targs->start + targs->len <= targs->nblobs);
	for (i = 0; i < targs->len; i++)	{
		/* add random data at corresponding index in blob array */
		BUILD_ASSERT(BLOB_SIZE % sizeof(uint64_t) == 0);
		for (j = 0; j < BLOB_SIZE / sizeof(uint64_t); j++) {
			if (repeat == 0){
				/* random patterns for varying compression */
				repeat = syn_rand_next(&rand) % 100;
				rand_num = syn_rand_next(&rand);
			}
			offset = (targs->start + i) * BLOB_SIZE + j*sizeof(uint64_t);
			*(uint64_t*)(blobdata + offset) = rand_num;
			repeat--;
		}
	}
	pr_info("worker %d added %d blobs", targs->tid, i);
	WAITGROUP_ADD(workers_wg, -1);	/* signal done */
}

/* Shenango doesn't have preemptions so threads may need to yield 
 * occasionally to let other threads run, especially in indefinite
 * loops whose termination is controlled by other threads.
 * state: saves last yield time, init with 0 */
static inline void thread_yield_after(int time_us, unsigned long* state) {
#ifdef SHENANGO
	unsigned long duration_tsc = rdtsc() - *state;
	if (duration_tsc / CYCLES_PER_US >= time_us) {
		thread_yield();
		*state = rdtsc();
	}
#endif
}

/* prepare zipf workload */
#ifdef SHENANGO
void
#else 
void* 
#endif
prepare_workload(void* arg) {
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
#ifdef DEBUG2
		zipf_counts[ret]++;
#endif
	}

	pr_info("worker %d generated %d requests", targs->tid, i);
	destroy_zipfian(z);
	WAITGROUP_ADD(workers_wg, -1);	/* signal done */
}

/* the real work for each request */
static inline void process_request(int keys[], int nkeys, int nblobs,
		struct snappy_env* env,
		char* encbuffer, char* zipbuffer)
{
	int i, ret, found;
	int rdahead, prio;
	size_t ziplen;
	void *data, *nextin;
	unsigned long value;
    uint8_t key_template[KEY_LEN] = {
		0x00, 0x00, 0x00, 0x00,
		0xff, 0xff, 0xff, 0xff,
		0xff, 0xff, 0xff, 0xff };
	int ncompress = 0;

	/* lookup hash table a number of times */
	ASSERT(nkeys > 0);
	for (i = 0; i < nkeys; i++) {
		*(uint32_t*)key_template = keys[i];
		value = (unsigned long)hopscotch_lookup(ht, key_template, &found);
		ASSERT(found);
	}
	// ASSERT(value == key % nblobs);

	/* use the last value to get the blob */
	ASSERT(0 <= value && value < nblobs);
	BUILD_ASSERT(BLOB_SIZE % PAGE_SIZE == 0);
	nextin = blobdata + value * BLOB_SIZE;

	/* eden hints for two pages */
	rdahead = prio = 0;
#if defined(USE_READAHEAD)
	rdahead = 1;
#endif
#if defined(SET_PRIORITY)
	prio = 1;	/* lower prio for polluting array data */
#endif

	/* set rdahead on the first page, prio on both */
	HINT_READ_FAULT_ALL(nextin, rdahead, prio);
	HINT_READ_FAULT_ALL(nextin + PAGE_SIZE, 0, prio);

#ifdef ENCRYPT
	/* encrypt data (emits same length as input) */
	ret = aes_encrypt_cbc(nextin, BLOB_SIZE, encbuffer, aes_ksched, AES_KEY_SIZE, aes_iv);
	ASSERT(ret);
	nextin = encbuffer;
#endif

#ifdef COMPRESS 
	/* compress the array data */
	ncompress = COMPRESS;
	for (i = 0; i < ncompress; i++) {
		ret = snappy_compress(env, nextin, BLOB_SIZE, zipbuffer, &ziplen);
		ASSERTZ(ret);
	}
	pr_debug("snappy compression done. inlen: %ld outlen: %lu", BLOB_SIZE, ziplen);
	nextin = zipbuffer;
#endif
}

/* process requests */
#ifdef SHENANGO
void
#else 
void* 
#endif
run(void* arg)
{
	int ret, i, j, nkeys;
	int keys[KEYS_PER_REQ];
	void *data, *nextin;
	unsigned long ystate = 0;
	thread_args_t* targs = (thread_args_t*)arg;
    uint8_t key_template[KEY_LEN] = {
		0x00, 0x00, 0x00, 0x00,
		0xff, 0xff, 0xff, 0xff,
		0xff, 0xff, 0xff, 0xff };
	struct syn_rand_state rand;
	ASSERTZ(syn_rand_seed(&rand, time(NULL) ^ targs->tid));

	/* crypto init */
	char* encbuffer = malloc(BLOB_SIZE);
	ASSERT(encbuffer);

	/* snappy init */
	struct snappy_env env;
	ASSERTZ(snappy_init_env(&env));
	size_t ziplen = snappy_max_compressed_length(BLOB_SIZE);
	char* zipbuffer = malloc(ziplen);
	ASSERT(zipbuffer);
	FILE* fp;
	char fname[50];

	/* wait for all threads to be ready */
	ASSERT(targs->start + targs->len <= targs->nreqs);
	pr_info("worker %d starting at request %lu len %lu", 
		targs->tid, targs->start, targs->len);

	BARRIER_WAIT(&ready);

#ifdef WARMUP
	/* warm up */
	BARRIER_WAIT(&warmup);
	while(!stop_button) {
		/* pick a random key */
		BUILD_ASSERT(KEYS_PER_REQ > 0);
		keys[0] = syn_rand_next(&rand) % targs->nkeys;
		process_request(keys, 1, targs->nblobs, &env, encbuffer, zipbuffer);
		thread_yield_after(1000 /* µs */, &ystate);
	}
	pr_info("worker %d warmedup", targs->tid);
	BARRIER_WAIT(&warmedup);
#endif

	/* actual run */
	BARRIER_WAIT(&start);
	for (i = 0; i < targs->len && !stop_button; i += KEYS_PER_REQ) {
		/* pick a set of zipf-distributed keys */
		BUILD_ASSERT(KEYS_PER_REQ > 0);
		for (j = 0; j < KEYS_PER_REQ && (i + j) < targs->len; j++)
			keys[j] = zipf_sequence[targs->start + i + j];
		process_request(keys, KEYS_PER_REQ, targs->nblobs, &env,
			encbuffer, zipbuffer);
		targs->xput++;
		thread_yield_after(1000 /* µs */, &ystate);
	}

	pr_info("worker %d done at %ld ops", targs->tid, targs->xput);
	WAITGROUP_ADD(workers_wg, -1);	/* signal done */
}

/* issue stop signal on timeout */
#ifdef SHENANGO
void
#else 
void* 
#endif
timeout_thread(void* arg) {
	unsigned long sleep_us = (unsigned long) arg;
	USLEEP(sleep_us);
	stop_button = 1;
}

/* main thread called into by shenango runtime */
void main_thread(void* arg) {
	int i, j, ret, found;
	struct main_args* margs = (struct main_args*) arg;
	unsigned long nkeys = margs->nkeys;
	unsigned long nreqs = margs->nreqs;
	unsigned long nblobs = margs->nblobs;
	int nworkers = margs->nworkers;
	unsigned long timeout_us;
	double shard_sz;
	thread_args_t* targs;
    uint8_t key_template[KEY_LEN] = {
		0x00, 0x00, 0x00, 0x00,
		0xff, 0xff, 0xff, 0xff,
		0xff, 0xff, 0xff, 0xff };
	uint64_t start_tsc, duration_tsc, now_tsc, xput = 0;
	double duration_secs;
	THREAD_T* workers;
	THREAD_T timer1, timer2;

	/* write pid and wait some time for the saved pid to be added to 
     * the cgroup to enforce fastswap limits */
	pr_info("writing out pid %d", getpid());
	fwrite_number("main_pid", getpid());
    sleep(1);

	/* core data stuctures: these go in remote memory */
    ht = hopscotch_init(NULL, next_power_of_two(nkeys) + 1);
    ASSERT(ht);
	blobdata = RMALLOC(nblobs*BLOB_SIZE);
    pr_info("memory for blob array: %lu MB", nblobs*BLOB_SIZE / (1<<20));
	ASSERT(blobdata);

	/* setup hash table */
	workers = malloc(sizeof(THREAD_T) * nworkers);
	targs = aligned_alloc(CACHE_LINE_SIZE, nworkers * sizeof(thread_args_t));
	WAITGROUP_INIT(workers_wg);
	shard_sz = ceil(nkeys * 1.0 / nworkers);
	for (j = 0; j < nworkers; j++) {
		targs[j].tid = j;
		targs[j].nkeys = nkeys;
		targs[j].nblobs = nblobs;
		targs[j].start = min(j * shard_sz, nkeys);
		targs[j].len = min(shard_sz, nkeys - targs[j].start);
		WAITGROUP_ADD(workers_wg, 1);
		ret = THREAD_CREATE(&workers[j], setup_table, &targs[j]);
		ASSERTZ(ret);
	}
	WAITGROUP_WAIT(workers_wg);
	pr_info("hash table setup done");

	/* setup blob array */
	WAITGROUP_INIT(workers_wg);
	shard_sz = ceil(nblobs * 1.0 / nworkers);
	for (j = 0; j < nworkers; j++) {
		targs[j].tid = j;
		targs[j].nkeys = nkeys;
		targs[j].nblobs = nblobs;
		targs[j].start = min(j * shard_sz, nblobs);
		targs[j].len = min(shard_sz, nblobs - targs[j].start);
		WAITGROUP_ADD(workers_wg, 1);
		ret = THREAD_CREATE(&workers[j], setup_blobs, &targs[j]);
		ASSERTZ(ret);
	}
	WAITGROUP_WAIT(workers_wg);
	pr_info("blob data setup done");

#ifdef DEBUG2
	/* print table */
	void* data;
	printf("Table: ");
	for (j = 0; j < nkeys; j++) {
		*(uint32_t*)key_template = j;
		data = hopscotch_lookup(ht, key_template, &found);
		printf("(%d: %lu) ", j, (unsigned long) data);
	}
	printf("\n");
#endif

	/* aes init */
	aes_key_setup(aes_key, aes_ksched, AES_KEY_SIZE);

	/* prepare zipf request sequence  */	
	zparams = margs->zparams;
	zipf_sequence = (uint64_t*) malloc (nreqs * sizeof(uint64_t));
	ASSERT(zipf_sequence);

	/* for fastswap, we don't have control over what goes in remote memory.
	 * so we pin this request data and count this out of local memory  */
	LOCK_MEMORY(zipf_sequence, nreqs * sizeof(uint64_t));
    pr_info("memory for req data: %lu MB", nreqs * sizeof(uint64_t) / (1<<20));

#ifdef DEBUG2
	zipf_counts = (uint32_t*)calloc(nkeys, sizeof(uint32_t));
#endif
	WAITGROUP_INIT(workers_wg);
	shard_sz = ceil(nreqs * 1.0 / nworkers);
	for (j = 0; j < nworkers; j++) {
		targs[j].tid = j;
		targs[j].nkeys = nkeys;
		targs[j].nreqs = nreqs;
		targs[j].nblobs = nblobs;
		targs[j].start = min(j * shard_sz, nreqs);
		targs[j].len = min(shard_sz, nreqs - targs[j].start);
		WAITGROUP_ADD(workers_wg, 1);
		ret = THREAD_CREATE(&workers[j], prepare_workload, &targs[j]);
		ASSERTZ(ret);
	}
	WAITGROUP_WAIT(workers_wg);
	pr_info("generated zipf sequence of length: %lu", nreqs);
#ifdef DEBUG2
	// printf("zipf seq: ");
	// for (j = 0; j < nreqs; j++)	printf("%lu ", zipf_sequence[j]);
	printf("\ncounts: ");
	for (j = 0; j < nkeys; j++)	printf("%u ", zipf_counts[j]);
	printf("\n");
#endif

	/* run requests */
	WAITGROUP_INIT(workers_wg);
	BARRIER_INIT(&ready, nworkers+1);
	BARRIER_INIT(&warmup, nworkers+1);
	BARRIER_INIT(&warmedup, nworkers+1);
	BARRIER_INIT(&start, nworkers+1);
	shard_sz = ceil(nreqs * 1.0 / nworkers);
	for (j = 0; j < nworkers; j++) {
		targs[j].tid = j;
		targs[j].nkeys = nkeys;
		targs[j].nreqs = nreqs;
		targs[j].nblobs = nblobs;
		targs[j].start = min(j * shard_sz, nreqs);
		targs[j].len = min(shard_sz, nreqs - targs[j].start);
		targs[j].xput = 0;
		WAITGROUP_ADD(workers_wg, 1);
		ret = THREAD_CREATE(&workers[j], run, &targs[j]);
		ASSERTZ(ret);
	}
	
	/* wait for threads to be ready */
	BARRIER_WAIT(&ready); 	

#ifdef WARMUP
	/* run warmup with a timeout and wait */	
	stop_button = 0;
	pr_info("starting warmup");
	timeout_us = WARMUP_SECS * MILLION;
	ret = THREAD_CREATE(&timer1, timeout_thread, (void*) timeout_us);
	ASSERTZ(ret);
	save_checkpoint("warmup_start");
	BARRIER_WAIT(&warmup);		/* kick off */
	BARRIER_WAIT(&warmedup);	/* and wait */
	save_checkpoint("warmup_end");
#endif

	/* start the run (with timeout) */
	pr_info("starting the run");
#ifdef USE_READAHEAD
	pr_info("with readahead hints");
#endif
	save_checkpoint("run_start");
	start_tsc = rdtsc();
	stop_button = 0;
	timeout_us = MAX_RUNTIME_SECS * MILLION;
	ret = THREAD_CREATE(&timer2, timeout_thread, (void*) timeout_us);
	ASSERTZ(ret);
	BARRIER_WAIT(&start);		/* kick off */
	WAITGROUP_WAIT(workers_wg);	/* and wait */
	duration_tsc = rdtscp(NULL) - start_tsc;
	save_checkpoint("run_end");

#ifdef EDEN
	/* print memory used */
	pr_info("memory used at finish: %lu", atomic64_read(&memory_used));
#endif

	/* write result */
	duration_secs = duration_tsc * 1.0 / (MILLION * CYCLES_PER_US);
	for (j = 0; j < nworkers; j++) xput += targs[j].xput;
	pr_info("ran for %.1lf secs with %.0lf ops /sec",
		duration_secs, xput/duration_secs);
	printf("result:%.0lf\n", xput / duration_secs);

	/* we must run for at least a few secs
	 * adjust MAX_OPS_PER_CORE otherwise */
	ASSERT(duration_secs >= MIN_RUNTIME_SECS);

    /* Release */
    hopscotch_release(ht);
}

int main(int argc, char *argv[]) {
	int ret;

	if (argc < 4) {
		pr_err("USAGE: %s <config-file> <ncores> <nworkers> [<nkeys>] "
			"[<nblobs>] [<zipfparamS>]\n", argv[0]);
		return -EINVAL;
	}
	CYCLES_PER_US = time_calibrate_tsc();
	printf("time calibration - cycles per µs: %lu\n", CYCLES_PER_US);

	struct main_args margs;
	margs.ncores = atoi(argv[2]);
	margs.nworkers = atoi(argv[3]);
	margs.nkeys = (argc > 4) ? atoi(argv[4]) : MILLION;
	margs.nblobs = (argc > 5) ? atof(argv[5]) : MILLION;
	margs.zparams = (argc > 6) ? atof(argv[6]) : 0.1;
	margs.nreqs = (margs.ncores * (unsigned long) MAX_OPS_PER_CORE * MIN_RUNTIME_SECS);

#ifdef SHENANGO
	/* initialize shenango */
	pr_info("running with shenango");
	ret = runtime_init(argv[1], main_thread, &margs);
	ASSERTZ(ret);
#else
	pr_info("running with pthreads");
	main_thread(&margs);
#endif

	return 0;
}