#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <limits.h>
#include <time.h>
#include <sys/time.h>
#ifdef SHENANGO
#include "runtime/thread.h"
#include "runtime/sync.h"
#endif
#ifdef WITH_KONA
#include "klib.h"
#endif
#include "logging.h"

/* thread/sync primitives from various platforms */
#ifdef SHENANGO
#define THREAD_T						unsigned long
#define THREAD_CREATE(id,routine,arg)	thread_spawn(routine,arg)
#define THREAD_EXIT(ret)				thread_exit()
#define BARRIER_T		 				barrier_t
#define BARRIER_INIT(b,c)				barrier_init(b, c)
#define BARRIER_WAIT 					barrier_wait
#define BARRIER_DESTROY(b)				{}
#else 
#define THREAD_T						pthread_t
#define THREAD_CREATE(tid,routine,arg)	pthread_create(tid,NULL,routine,arg)
#define THREAD_EXIT(ret)				pthread_exit(ret)
#define BARRIER_T		 				pthread_barrier_t
#define BARRIER_INIT(b,c)				pthread_barrier_init(b, NULL, c)
#define BARRIER_WAIT 					pthread_barrier_wait
#define BARRIER_DESTROY(b) 				pthread_barrier_destroy(b)
#endif

/* remote memory primitives */
#ifdef WITH_KONA
#define RMALLOC		rmalloc
#define RFREE		rfree
#else
#define RMALLOC		malloc
#define RFREE		free
#endif


/* local macros */
#define master if (id == 0) 
#define isize sizeof(int)
#define lsize sizeof(size_t)
#define BARRIER BARRIER_WAIT(&barrier)
#define start_time struct timeval* time_start = get_time();
#define end_time end_timing(time_start);

/* global data */
size_t size; 
size_t w; 
int t;
int ro; 

/* 
 * input array (currently elements are int-sized) 
 */
int* input;
/*
 * regular_samples is an array of t*t elements where each thread writes 
 * local samples to their own parts (disjoint) of the array.
 *
 * gets generated in phase 1, and used in phase 2
 */
int* regular_samples;
/*
 * pivots is an array of t - 1 elements, and is written to only once by the master thread, 
 * and afterwards is accessed in read-only fashion by the worker threads. 
 *
 * it stores pivots in phase 2
 */
int* pivots;
/*
 * partitions is an array of size t * (t + 1). 
 * it can be considered as a 2d array where each thread writes the partition indices to its own row. 
 * there are t - 1 partition points for each chunk, 
 * and adding start and end indices makes the size t + 1. 
 *
 * gets generated in phase 3
 */
size_t* partitions;
/*
 * merged_partition_length is an array of size t which contains 
 * the length of total merged keys per thread in phase 4.
 */
size_t* merged_partition_length;

struct thread_data {
	int id;
	size_t start;
	size_t end;
};

BARRIER_T barrier;

int cmpfunc(const void* a, const void* b);
void is_sorted();
struct timeval* get_time();
long int end_timing(struct timeval* start);
int* generate_array_of_size(size_t size);
void print_array(int* array, size_t size);
void checkpoint(char* name);

/*
 * phase 1
 * does the local sorting of the array, and collects sample.
 */
void phase1(struct thread_data* data) {
	// start_time;

	size_t start = data->start;
	size_t end = data->end;
	int id = data->id;
	
	qsort((input + start), (end - start), isize, cmpfunc);
	
	/* regular sampling */
	int ix = 0;
	for (int i = 0; i < t; i++) {
		regular_samples[id * t + ix] = input[start + (i * w)];
		ix++;
	}
	
	// long int time = end_time;
	// printf("thread %d - phase 1 took %ld ms, sorted %lu items\n", id, time, (end - start));	
}

/*
 * phase 2
 * sequential part of the algorithm. determines pivots based on the regular samples provided.
 */
void phase2(struct thread_data* data) {
	int id = data->id;
	master { 
		// start_time;
	
		qsort(regular_samples, t*t, isize, cmpfunc);
		int ix = 0;
		for (int i = 1; i < t; i++) {
			int pos = t * i + ro - 1;
			pivots[ix++] = regular_samples[pos];
		}
		
		// long int time = end_time;
		// printf("thread %d - phase 2 took %ld ms\n", id, time);
	}
}

/*
 * phase 3
 * local splitting of the data based on the pivots
 */
void phase3(struct thread_data* data) {
	// start_time;

	size_t start = data->start;
	size_t end = data->end;
	int id = data->id;

	int pi = 0; // pivot counter
	int pc = 1; // partition counter
	partitions[id*(t+1)+0] = start;
	partitions[id*(t+1)+t] = end;
	for (size_t i = start; i < end && pi != t-1; i++) {
		if (pivots[pi] < input[i]) {
			partitions[id*(t+1) + pc] = i;
			pc++;
			pi++;
		}
	}
	
	// long int time = end_time;
	// printf("thread %d - phase 3 took %ld ms\n", id, time);
}

/*
 * merges the array with a given size into the original input array
 */
void merge_into_original_array(int id, size_t* array, size_t array_size) {
	// start_time;

	// find the position that the thread needs to start from
	// in order to put values into the original array
	// start position is basically the summation of 
	// the lengths of the previous partitions
	size_t start_pos = 0;
	int x = id - 1;
	while (x >= 0) {
		start_pos += merged_partition_length[x--];
	}
	for (size_t i = start_pos; i < start_pos + array_size; i++) {
		input[i] = array[i - start_pos];
	}
	// long int time = end_time;
	// printf("thread %d - phase merge took %ld ms\n", id, time);	
	RFREE(array);
}

/*
 * phase 4
 * 
 * merges the received partitions from other threads, and performs a k way merge
 * it also saves the merged values into their appropriate place in the input array.
 */
void phase4(struct thread_data* data) {
	// start_time;
	
	// this array contains the range indicating pairs
	// [r1_start, r1_end, r2_start, r2_end, ...]
	size_t exchange_indices[t*2];
	int id = data->id;

	int ei = 0; // exchange indices counter
	for (int i = 0; i < t; i++) {
		exchange_indices[ei++] = partitions[i*(t+1) + id];
		exchange_indices[ei++] = partitions[i*(t+1) + id + 1];
	}
	// k way merge - start
	// in k-way merge step, basically we go through each valid partition, and find the minimum in each step
	// then we add that minimum to the local "merged_values" array in each step
	// a valid partition is when rn_start < rn_end
	// partition being invalid means that that partition has been merged completely already
	// array size
	size_t total_merge_length = 0;
	for (int i = 0; i < t * 2; i+=2) {
		total_merge_length += exchange_indices[i + 1] - exchange_indices[i];
	}
	
	size_t* merged_values = RMALLOC(sizeof(size_t) * total_merge_length);
	merged_partition_length[id] = total_merge_length;
	int mi = 0;
	int min, min_pos;
	while (mi < total_merge_length) {
		/* find the next min element of all sorted partitions */
		bool found = false;
		for (int i = 0; i < t * 2; i += 2) {
			if (exchange_indices[i] != exchange_indices[i+1]) {
				if (!found) {
					min = input[exchange_indices[i]];
					min_pos = i;
					found = true;
					continue;
				}
				
				if (input[exchange_indices[i]] < min) {
					min = input[exchange_indices[i]];
					min_pos = i;
				}
			}
		}

		/* nothing left */
		if(!found)
			break;

		// save the minimum to the final array
		merged_values[mi++] = min;
		// increase the counter of the range that 
		// the minimum value belongs to
		exchange_indices[min_pos]++;
	}
	// k way merge - end
	// long int time = end_time;
	// printf("thread %d - phase 4 took %ld ms, merged %lu keys\n", id, time, total_merge_length);

	BARRIER;
	master { RFREE(partitions); }
	merge_into_original_array(id, merged_values, total_merge_length);
}

#ifdef SHENANGO
void* _psrs(void* args);
void psrs(void* args) {  _psrs(args);	}
void* _psrs(void *args) {
#else
void* psrs(void *args) {
#endif
	struct thread_data* data = (struct thread_data*) args;
	int id = data->id; 
	struct timeval* time_start;
	long int time;

	/* phase 1 */
	// master { checkpoint("phase1_start"); }
	time_start = get_time();
	BARRIER;
	phase1(data);
	BARRIER;
	master { 
		time = end_timing(time_start);
		printf("phase 1 took %ld ms\n", time);
	}

	/* phase 2 */
	// master { checkpoint("phase2_start"); }
	time_start = get_time();
	BARRIER;
	phase2(data);
	BARRIER;
	master {
		time = end_timing(time_start);
		printf("phase 2 took %ld ms\n", time);
		RFREE(regular_samples); 
	}

	/* phase 3 */
	// master { checkpoint("phase3_start"); }
	time_start = get_time();
	BARRIER;
	phase3(data);
	BARRIER;
	master { 
		time = end_timing(time_start);
		printf("phase 3 took %ld ms\n", time);
		RFREE(pivots); 
	}
	
	/* phase 4 */
	// master { checkpoint("phase4_start"); }
	time_start = get_time();
	BARRIER;
	phase4(data);
	BARRIER;
	master { 
		time = end_timing(time_start);
		printf("phase 4 took %ld ms\n", time);
		RFREE(merged_partition_length); 
	}

	free(data);
	master { return NULL; }
	THREAD_EXIT(0);
}

struct thread_data* get_thread_data(int id, size_t per_thread) {
	struct thread_data* data = malloc(sizeof(struct thread_data));
	data->id = id;
	data->start = id * per_thread;
	data->end = data->start + per_thread;
	return data;
}


void main_thread(void* arg) {
	/* initializing/allocating data */
	input = generate_array_of_size(size);
	regular_samples = RMALLOC(isize *t*t); 
	pivots = RMALLOC(isize * (t - 1));
	merged_partition_length = RMALLOC(sizeof(size_t) * t);
	partitions = RMALLOC(sizeof(size_t) *  t * (t+1));
	
	// size of a chunk per thread
	size_t per_thread = size / t;
	
	BARRIER_INIT(&barrier, t);
	
	start_time;	
	
	/* start worker threads */
	THREAD_T* threads = malloc(sizeof(THREAD_T) * t);
	int i = 1;
	for (; i < t - 1; i++) {
		struct thread_data* data = get_thread_data(i, per_thread);
		THREAD_CREATE(&threads[i], psrs, (void *) data);
	}
	/* the last thread gets the remaining part of the array */
	struct thread_data* data = get_thread_data(i, per_thread); 
	data->end = size;
	THREAD_CREATE(&threads[i], psrs, (void *) data);

	/* master thread */
	struct thread_data* data_master = get_thread_data(0, per_thread);
	psrs((void *) data_master);
	
	long int time = end_time;
	printf("took: %ld ms (microseconds)\n", time);
	
 	is_sorted(); // for validation to see if the array has really been sorted

	RFREE(input);
	free(threads);
	BARRIER_DESTROY(&barrier);
}


int main(int argc, char *argv[]){
	if (argc != 3) {
		fprintf(stderr, "2 arguments required - <size> <thread_count>\n");
		exit(1);
	} 
	
	/* initializing parameters */
	size = atol(argv[1]);
	t = atoi(argv[2]);
	w = (size/(t*t));
	ro 	= t / 2;
	printf("size: %lu\n", size);

#ifdef SHENANGO
	/* initialize shenango */
	char shenangocfg[] = "shenango.config"; /* ensure this file exists  */
	int ret = runtime_init(shenangocfg, main_thread, NULL);
	assert(ret != 0);
#else
#ifdef WITH_KONA
	/* initialize kona. in case of shenango, it is taken care of. */
	rinit();
#endif
	main_thread(NULL);
#endif

	return 0;
}

// checks if the input array is sorted
// used for debugging and validation reasons
void is_sorted() {
	for (size_t i = 0; i < size - 1; i++) {
		if (input[i] > input[i+1]) {
			printf("not sorted: %d > %d\n", input[i], input[i+1]);
			return;	
		}
	}
	printf("sorted\n");
}

struct timeval* get_time() {
	struct timeval* t = malloc(sizeof(struct timeval));
	gettimeofday(t, NULL);
	return t;
}

long int end_timing(struct timeval* start) {
	struct timeval end; gettimeofday(&end, NULL);
	long int diff = (long int) ((end.tv_sec * 1000000 + end.tv_usec) - (start->tv_sec * 1000000 + start->tv_usec));
	free(start);
	return diff;
}

// used for generating random arrays of the given size
int* generate_array_of_size(size_t size) {
	srandom(15);
	int* randoms = RMALLOC(isize * size);
	for (size_t i = 0; i < size; i++) {
		randoms[i] = (int) random();
	}
	return randoms;
}

// prints the values of the given array
void print_array(int* array, size_t size) {
	for (size_t i = 0; i < size; i++) {
		printf("%d ", array[i]);
	}
	printf("\n");
}

/* save unix timestamp of a checkpoint */
void checkpoint(char* name) {
	FILE* fp = fopen(name, "w");
	fprintf(fp, "%lu", time(NULL));
	fflush(fp);
	fclose(fp);
}

// reference: https://stackoverflow.com/a/27284318/9985287
// integer compare function
int cmpfunc (const void * a, const void * b) { return ( *(int *) a - *(int*)b );}
