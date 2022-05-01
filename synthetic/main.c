
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

#define MEM_REGION_SIZE ((1ull<<30) * 32)	//32 GB
#define RUNTIME_SECS 10
#define NUM_LAT_SAMPLES 5000
#define BLOB_SIZE (2*PAGE_SIZE)
#define SNAPPY_HT_BUF_SIZE 64 			// based on kmax_hash_table_size

struct thread_args {
    int tid;
	int nkeys;
	int start;
	int len;
	uint32_t pad[12];
};
typedef struct thread_args thread_args_t;
BUILD_ASSERT((sizeof(thread_args_t) % CACHE_LINE_SIZE == 0));

struct main_args {
	int nworkers;
	int nkeys;
	int nreqs;
	double zparams;
};

uint64_t cycles_per_us;
waitgroup_t workers;
struct hopscotch_hash_table *ht;
void* blobdata;
uint64_t* zipf_sequence;
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
	int ret, i, j, offset;
	uint64_t rand_num;
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
	for (i = targs->start; i < targs->len; i++)	{
		*(uint32_t*)key_template = i;
		/* push a key */
		ret = hopscotch_insert(ht, key_template, (void*)(unsigned long)i);
		ASSERTZ(ret);
		/* add random data at corresponding index in blob array */
		BUILD_ASSERT(BLOB_SIZE % sizeof(uint64_t) == 0);
		for (j = 0; j < BLOB_SIZE / sizeof(uint64_t); j++) {
			rand_num = rand_next(&rand);
			offset = i*BLOB_SIZE + j*sizeof(uint64_t);
			*(uint64_t*)(blobdata + offset) = rand_num;
		}
	}
	pr_debug("worker %d added %d keys", targs->tid, i);
	waitgroup_add(&workers, -1);	/* signal done */
}

/* process requests */
void run(void* arg) {
	int ret, i, key;
	void* data;
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

	ASSERT(targs->start + targs->len <= targs->nkeys);
	for (i = targs->start; i < targs->len; i++) {
		/* get the array index from hash table */
		/* we just save the key as value which is ok for benchmarking purposes */
		key = zipf_sequence[i];
		*(uint32_t*)key_template = key;
		data = hopscotch_lookup(ht, key_template);
		ASSERT((unsigned long)data == key);

		/* encrypt data (emits same length as input) */
		aes_encrypt_cbc(blobdata + key * BLOB_SIZE, BLOB_SIZE, 
			encbuffer, aes_ksched, 256, aes_iv);

		// /* compress the array element */
		ret = snappy_compress(&env, encbuffer, BLOB_SIZE, zipbuffer, &ziplen);
		pr_debug("snappy compression done. inlen: %d outlen: %lu", BLOB_SIZE, ziplen);
	}

	pr_debug("worker %d processed %d requests", targs->tid, i);
	waitgroup_add(&workers, -1);	/* signal done */
}

/* main thread called into by shenango runtime */
void main_thread(void* arg) {
	int i, j, ret;
	struct main_args* margs = (struct main_args*) arg;
	int nkeys = margs->nkeys;
	int nreqs = margs->nreqs;
	int nworkers = margs->nworkers;
	thread_args_t* targs;
    uint8_t key_template[KEY_LEN] = {
		0x00, 0x00, 0x00, 0x00,
		0xff, 0xff, 0xff, 0xff,
		0xff, 0xff, 0xff, 0xff };

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
		targs[j].start = j * ceil(nkeys / nworkers);
		targs[j].len = min(ceil(nkeys / nworkers), nkeys - targs[j].start);
		waitgroup_add(&workers, 1);
		ret = thread_spawn(setup, &targs[j]);
		ASSERTZ(ret);
	}
	waitgroup_wait(&workers);

	/* aes init */
	aes_key_setup(aes_key, aes_ksched, 256);

	/* prepare zipf request sequence (FIXME: do this with more threads?) */
	zipf_sequence = (uint64_t*) malloc (nreqs * sizeof(uint64_t));
	ZIPFIAN z = create_zipfian(margs->zparams, nkeys, time(NULL));
#ifdef DEBUG
	uint32_t* counts = (uint32_t*)calloc(nkeys, sizeof(counts));
#endif
	int reqs_per_worker = ceil(nreqs / nworkers), wid = 0;
	uint64_t rand_req;
	for (i = 0; i < reqs_per_worker; i++) {
		for (j = 0; j < nworkers; j++) {
			ret = zipfian_gen(z);
			ASSERT(0 <= ret && ret < nkeys);
			if (j*reqs_per_worker + i >= nreqs) {
				ASSERT(j == nworkers - 1);
				continue;
			}
			*(zipf_sequence + j*reqs_per_worker + i) = ret;
#ifdef DEBUG
			counts[ret]++;
#endif
		}
	}
#ifdef DEBUG
	// printf("zipf seq: ");
	// for (j = 0; j < nreqs; j++)	printf("%lu ", zipf_sequence[j]);
	printf("\ncounts: ");
	for (j = 0; j < nkeys; j++)	printf("%u ", counts[j]);
	printf("\n");
#endif

	/* run requests */
	waitgroup_init(&workers);
	for (j = 0; j < nworkers; j++) {
		targs[j].tid = j;
		targs[j].nkeys = nreqs;
		targs[j].start = j * ceil(nreqs / nworkers);
		targs[j].len = min(ceil(nreqs / nworkers), nreqs - targs[j].start);
		waitgroup_add(&workers, 1);
		ret = thread_spawn(run, &targs[j]);
		ASSERTZ(ret);
	}
	waitgroup_wait(&workers);

    /* Release */
    hopscotch_release(ht);
	destroy_zipfian(z);
}

int main(int argc, char *argv[]) {
	int ret;

	if (argc < 3) {
		pr_err("USAGE: %s <config-file> <nworkers> [<nkeys>] [<nreqs>] [<zipfparamS>]\n", argv[0]);
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
	margs.nkeys = (argc > 3) ? atoi(argv[3]) : 1000000;
	margs.nreqs = (argc > 4) ? atoi(argv[4]) : 1000;
	margs.zparams = (argc > 5) ? atof(argv[5]) : 0.1;
	ret = runtime_init(argv[1], main_thread, &margs);
	ASSERTZ(ret);
	return 0;
}