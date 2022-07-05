#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>
#include <limits.h>
#include <time.h>
#include <sys/time.h>

#include "common.h"

/* local macros */
#define master if (id == 0) 
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
 * input array
 */
element_t* input;
/*
 * regular_samples is an array of t*t elements where each thread writes 
 * local samples to their own parts (disjoint) of the array.
 *
 * gets generated in phase 1, and used in phase 2
 */
element_t* regular_samples;
/*
 * pivots is an array of t - 1 elements, and is written to only once by the master thread, 
 * and afterwards is accessed in read-only fashion by the worker threads. 
 *
 * it stores pivots in phase 2
 */
element_t* pivots;
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
/* 
 * output array for merged values
 */
element_t* merged_values;

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
	size_t start = data->start;
	size_t end = data->end;
	int id = data->id;
	
	QUICKSORT((input + start), (end - start), sizeof(element_t), cmpfunc);

	/* regular sampling */
	int ix = 0;
	for (int i = 0; i < t; i++) {
		regular_samples[id * t + ix] = input[start + (i * w)];
		ix++;
	}
}

/*
 * phase 2
 * sequential part of the algorithm. determines pivots based on the regular samples provided.
 */
void phase2(struct thread_data* data) {
	int id = data->id;
	master { 	
		QUICKSORT(regular_samples, t*t, sizeof(element_t), cmpfunc);
		int ix = 0;
		for (int i = 1; i < t; i++) {
			int pos = t * i + ro - 1;
			pivots[ix++] = regular_samples[pos];
		}
	}
}

/*
 * phase 3
 * local splitting of the data based on the pivots
 */
void phase3(struct thread_data* data) {
	size_t start = data->start;
	size_t end = data->end;
	int id = data->id;

	int pi = 0; // pivot counter
	int pc = 1; // partition counter
	partitions[id*(t+1)+0] = start;
	partitions[id*(t+1)+t] = end;
	for (size_t i = start; i < end && pi != t-1; i++) {
		if (((unsigned long)&input[i] & _PAGE_OFFSET_MASK) == 0)
			POSSIBLE_READ_FAULT_AT(&input[i]);
		if (pivots[pi] < input[i]) {
			partitions[id*(t+1) + pc] = i;
			pc++;
			pi++;
		}
	}
}

/*
 * merges the array with a given size into the original input array
 */
void copyback(element_t* data, size_t start_pos, size_t len) {
	for (size_t i = start_pos; i < start_pos + len; i++) {
		if (((unsigned long)&data[i] & _PAGE_OFFSET_MASK) == 0)
			POSSIBLE_READ_FAULT_AT(&data[i]);
		if (((unsigned long)&input[i] & _PAGE_OFFSET_MASK) == 0)
			POSSIBLE_WRITE_FAULT_AT(&input[i]);
		input[i] = data[i];
	}
}

/*
 * phase 4
 * 
 * merges the received partitions from other threads, and performs a k way merge
 * it also saves the merged values into their appropriate place in the input array.
 */
void phase4(struct thread_data* data) {
	// this array contains the range indicating pairs
	// [r1_start, r1_end, r2_start, r2_end, ...]
	size_t exchange_indices[t*2];
	int id = data->id;
	int ei = 0;

	for (int i = 0; i < t; i++) {
		exchange_indices[ei++] = partitions[i*(t+1) + id];
		exchange_indices[ei++] = partitions[i*(t+1) + id + 1];
	}
	
	size_t total_merge_length = 0;
	for (int i = 0; i < t * 2; i+=2) {
		total_merge_length += exchange_indices[i + 1] - exchange_indices[i];
	}
	merged_partition_length[id] = total_merge_length;

	BARRIER;	/* for everyone to figure out their merge lengths */
	size_t start_pos = 0;
	for(int i = 0; i < id; i++)	
		start_pos += merged_partition_length[i];
	assert(start_pos + total_merge_length <= size);

	/* k way merge
	   in k-way merge step, basically we go through each valid partition, and find the minimum in each step
	   then we add that minimum to the local "merged_values" array in each step
	   a valid partition is when rn_start < rn_end
	   partition being invalid means that that partition has been merged completely already */
	int mi = 0;
	int min, min_pos;
	element_t* addr;
	while (mi < total_merge_length) {
		/* find the next min element of all sorted partitions */
		bool found = false;
		for (int i = 0; i < t * 2; i += 2) {
			if (exchange_indices[i] != exchange_indices[i+1]) {
				addr = &input[exchange_indices[i]];
				if (((unsigned long) addr & _PAGE_OFFSET_MASK) == 0)
					POSSIBLE_READ_FAULT_AT(addr);
				if (!found) {
					min = *addr;
					min_pos = i;
					found = true;
					continue;
				}
				
				if (*addr < min) {
					min = *addr;
					min_pos = i;
				}
			}
		}

		/* nothing left */
		if(!found)
			break;

		// save the minimum to the final array
		addr = &merged_values[start_pos + mi];
		if (((unsigned long) addr & _PAGE_OFFSET_MASK) == 0)
			POSSIBLE_WRITE_FAULT_AT(addr);
		*addr = min;
		// increase the counter of the range that 
		// the minimum value belongs to
		exchange_indices[min_pos]++;
		mi++;
	}
	assert(mi == total_merge_length);

	BARRIER;
	master { 
		RFREE(partitions);
		checkpoint("copyback"); 
	}
	BARRIER;

	copyback(merged_values, start_pos, total_merge_length);
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
	master { checkpoint("phase1"); }
	time_start = get_time();
	BARRIER;
	phase1(data);
	BARRIER;
	master { 
		time = end_timing(time_start);
		printf("phase 1 took %ld ms\n", time);
	}

	/* phase 2 */
	master { checkpoint("phase2"); }
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
	master { checkpoint("phase3"); }
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
	master { checkpoint("phase4"); }
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
	size_t per_thread = size / t;
	BARRIER_INIT(&barrier, t);

	/* initializing/allocating data */
	checkpoint("start");
	input = generate_array_of_size(size);
	regular_samples = RMALLOC(sizeof(element_t) *t*t); 
	pivots = RMALLOC(sizeof(element_t) * (t - 1));
	merged_partition_length = RMALLOC(sizeof(size_t) * t);
	partitions = RMALLOC(sizeof(size_t) *  t * (t+1));
	merged_values = RMALLOC(sizeof(element_t) * size);			/* output buffer */	
	// memset(merged_values, 0, sizeof(element_t) * size);			/* UNDO */
	pr_info("output buffer: start: %p size %lu", merged_values, size);

	/* start worker threads */
	start_time;	
	THREAD_T* threads = malloc(sizeof(THREAD_T) * t);
	int i = 1;
	for (; i < t - 1; i++) {
		struct thread_data* data = get_thread_data(i, per_thread);
		THREAD_CREATE(&threads[i], psrs, (void *) data);
	}

	/* the last thread gets the remaining part of the array */
	if (i < t) {
		struct thread_data* data = get_thread_data(i, per_thread); 
		data->end = size;
		THREAD_CREATE(&threads[i], psrs, (void *) data);
	}

	/* master thread */
	struct thread_data* data_master = get_thread_data(0, per_thread);
	psrs((void *) data_master);
	
	long int time = end_time;
	printf("took: %ld ms (microseconds)\n", time);
	checkpoint("end");
	
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
	int* randoms = RMALLOC(sizeof(element_t) * size);
	for (size_t i = 0; i < size; i++) {
		POSSIBLE_WRITE_FAULT_AT(&randoms[i]);
		randoms[i] = (element_t) random();
	}
	pr_info("input buffer: start: %p size %lu", randoms, size);
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
