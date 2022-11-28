#ifndef __COMMON_H__
#define __COMMON_H__

#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <string.h>

/* for uthreads */
#ifdef SHENANGO
#include "runtime/thread.h"
#include "runtime/sync.h"
#include "runtime/pgfault.h"
#include "runtime/timer.h"
#include "base/atomic.h"
#include "asm/atomic.h"
#endif

/* thread/sync primitives from various platforms */
/* thread/sync primitives from various platforms */
#ifdef SHENANGO
#define THREAD_T						            unsigned long
#define THREAD_CREATE(id,routine,arg)	  thread_spawn(routine,arg)
#define THREAD_EXIT(ret)				        thread_exit()
#define BARRIER_T		 				            barrier_t
#define BARRIER_INIT(b,c)				        barrier_init(b, c)
#define BARRIER_WAIT 					          barrier_wait
#define BARRIER_DESTROY(b)				      {}
#define WAITGROUP_T						          waitgroup_t
#define WAITGROUP_INIT(wg)				      waitgroup_init(&wg)
#define WAITGROUP_ADD(wg,val)			      waitgroup_add(&wg,val)
#define WAITGROUP_WAIT(wg)				      waitgroup_wait(&wg)
#define MUTEX_T                         mutex_t
#define MUTEX_INIT(m)                   mutex_init(m)
#define MUTEX_LOCK(m)                   mutex_lock(m)
#define MUTEX_UNLOCK(m)                 mutex_unlock(m)
#define MUTEX_DESTROY(m)                {}
#define SPINLOCK_T                      spinlock_t
#define SPIN_LOCK_INIT(s)               spin_lock_init(s)
#define SPIN_LOCK(s)                    spin_lock(s)
#define SPIN_UNLOCK(s)                  spin_unlock(s)
#define SPIN_LOCK_DESTROY(s)            {}
#define USLEEP                          timer_sleep
#else 
#define THREAD_T						            pthread_t
#define THREAD_CREATE(tid,routine,arg)	pthread_create(tid,NULL,routine,arg)
#define THREAD_EXIT(ret)				        pthread_exit(ret)
#define BARRIER_T		 				            pthread_barrier_t
#define BARRIER_INIT(b,c)				        pthread_barrier_init(b, NULL, c)
#define BARRIER_WAIT 					          pthread_barrier_wait
#define BARRIER_DESTROY(b) 				      pthread_barrier_destroy(b)
#define WAITGROUP_T						          int
#define WAITGROUP_INIT(wg)				      { wg = 0; 	}
#define WAITGROUP_ADD(wg,val)			      { wg++; 	}
#define WAITGROUP_WAIT(wg)				      { for(int z=0; z < nworkers; z++)	pthread_join(workers[z], NULL); }
#define MUTEX_T                         pthread_mutex_t
#define MUTEX_INIT(m)                   pthread_mutex_init(m, NULL)
#define MUTEX_LOCK(m)                   pthread_mutex_lock(m)
#define MUTEX_UNLOCK(m)                 pthread_mutex_unlock(m)
#define MUTEX_DESTROY(m)                pthread_mutex_destroy(m)
#define SPINLOCK_T                      pthread_spinlock_t
#define SPIN_LOCK_INIT(s)               pthread_spin_init(s, 0)
#define SPIN_LOCK(s)                    pthread_spin_lock(s)
#define SPIN_UNLOCK(s)                  pthread_spin_unlock(s)
#define SPIN_LOCK_DESTROY(s)            pthread_spin_destroy(s)
#define USLEEP                          usleep
#endif

/* remote memory primitives */
#if defined(EDEN)
#include "rmem/api.h"
#include "rmem/common.h"
#define RMALLOC		rmalloc
#define RFREE		  rmfree
#else
#define RMALLOC		malloc
#define RFREE		  free
#endif

/* fault annotations */
#if defined(EDEN)
#define HINT_READ_FAULT             hint_read_fault
#define HINT_WRITE_FAULT            hint_write_fault
#define HINT_READ_FAULT_RDAHEAD     hint_read_fault_rdahead
#define HINT_WRITE_FAULT_RDAHEAD    hint_write_fault_rdahead
#else
#define HINT_READ_FAULT             {}
#define HINT_WRITE_FAULT            {}
#define HINT_READ_FAULT_RDAHEAD     {}
#define HINT_WRITE_FAULT_RDAHEAD    {}
#endif

/* remote memory configuration helpers */
#if defined(EDEN)
#include "rmem/common.h"
#define SET_MAX_LOCAL_MEM(limit)    { local_memory = limit; }
#define GET_CURRENT_LOCAL_MEM()     (atomic64_read(&memory_used))
#define LOCK_MEMORY(addr,len)       {}
#define UNLOCK_MEMORY(addr,len)     {}
#elif defined(FASTSWAP)
#include "fastswap.h"
#include "sys/mman.h"
#define SET_MAX_LOCAL_MEM(limit)    set_local_memory_limit(limit)
#define GET_CURRENT_LOCAL_MEM()     get_memory_usage()
#define LOCK_MEMORY(addr,len)       mlock(addr,len)
#define UNLOCK_MEMORY(addr,len)     munlock(addr,len)
#else
#define SET_MAX_LOCAL_MEM(limit)    {}
#define GET_CURRENT_LOCAL_MEM()     0
#define LOCK_MEMORY(addr,len)       {}
#define UNLOCK_MEMORY(addr,len)     {}
#endif

/* page size parameters */
#define _PAGE_SHIFT       (12)
#define _PAGE_SIZE        (1ull << _PAGE_SHIFT)
#define _PAGE_OFFSET_MASK (_PAGE_SIZE - 1)
#define _PAGE_MASK        (~_PAGE_OFFSET_MASK)

#ifndef likely
#define likely(x) __builtin_expect(!!(x), 1)
#endif
#ifndef unlikely
#define unlikely(x) __builtin_expect(!!(x), 0)
#endif

/* assert a build-time condition */
#ifndef BUILD_ASSERT
#if !defined(__CHECKER__) && !defined(__cplusplus)
#define BUILD_ASSERT(cond) \
	_Static_assert(cond, "build-time condition failed")
#else /* __CHECKER__ */
#define BUILD_ASSERT(cond)
#endif /* __CHECKER__ */
#endif

/* other utils that we used from Shenango that we 
 * also want without Shenango */
#ifndef SHENANGO

/**
 * min - picks the minimum of two expressions
 *
 * Arguments @a and @b are evaluated exactly once
 */
#define min(a, b) \
	({__typeof__(a) _a = (a); \
	  __typeof__(b) _b = (b); \
	  _a < _b ? _a : _b;})

typedef struct {
	volatile int cnt;
} atomic_t;

#define ATOMIC_INIT(val) {.cnt = (val)}
#define	ACCESS_ONCE(x) (*(volatile __typeof__(x) *)&(x))

/**
 * load_acquire - load a native value with acquire fence semantics
 * @p: the pointer to load
 */
#define type_is_native(t) \
	(sizeof(t) == sizeof(char)  || \
	 sizeof(t) == sizeof(short) || \
	 sizeof(t) == sizeof(int)   || \
	 sizeof(t) == sizeof(long))
#define barrier() __asm__ volatile("" ::: "memory")

#define load_acquire(p)				\
({						\
	BUILD_ASSERT(type_is_native(*p));	\
	__typeof__(*p) __p = ACCESS_ONCE(*p);	\
	barrier();				\
	__p;					\
})

static inline int atomic_read(const atomic_t *a)
{
	return *((volatile int *)&a->cnt);
}

static inline void atomic_write(atomic_t *a, int val)
{
	a->cnt = val;
}

static inline bool atomic_cmpxchg(atomic_t *a, int oldv, int newv)
{
	return __sync_bool_compare_and_swap(&a->cnt, oldv, newv);
}
#endif


/********************************************
  logging
 ************************************************/

#define KNRM "\x1B[0m"
#define KRED "\x1B[31m"
#define KGRN "\x1B[32m"
#define KYEL "\x1B[33m"
#define KBLU "\x1B[34m"
#define KMAG "\x1B[35m"
#define KCYN "\x1B[36m"
#define KWHT "\x1B[37m"
#define RESET "\x1B[0m"

#define pr_error(eno, func) \
  do {                      \
    errno = eno;            \
    perror(KRED func);      \
    printf(RESET);          \
  } while (0)

#ifdef DEBUG
#define pr_debug(fmt, ...)                                                   \
  do {                                                                       \
    fprintf(stderr, "[%lx][%s][%s:%d]: " fmt "\n", pthread_self(), __FILE__, \
            __func__, __LINE__, ##__VA_ARGS__);                              \
  } while (0)
#else
#define pr_debug(fmt, ...) \
  do {                     \
  } while (0)
#endif

#ifndef DEBUG
#define pr_info(fmt, ...)                                                    \
  do {                                                                       \
    fprintf(stderr, KGRN "++[" __FILE__ "] " fmt "\n" RESET, ##__VA_ARGS__); \
    printf(RESET);                                                           \
  } while (0)
#else
// If we are in debug mode, lets use stderr for pr_info messages as well
// to get a better sense of order of logs.
#define pr_info(fmt, ...) pr_debug(fmt, ##__VA_ARGS__)
#endif

#define pr_debug_err(fmt, ...)                                  \
  do {                                                          \
    pr_debug(KRED fmt " : %s", ##__VA_ARGS__, strerror(errno)); \
    fprintf(stderr, RESET);                                     \
    fflush(stderr);                                             \
  } while (0)

#define pr_err(fmt, ...)                                                       \
  do {                                                                         \
    fprintf(stderr, KRED "++[%lx][%s][%s:%d]: " fmt " [errno:%d][%s]\n" RESET, \
            pthread_self(), __FILE__, __func__, __LINE__, ##__VA_ARGS__,       \
            errno, strerror(errno));                                           \
    fprintf(stderr, RESET);                                                    \
    fflush(stderr);                                                            \
  } while (0)

#define pr_err_syscall(fmt, ...)      \
  do {                                \
    pr_debug_err(fmt, ##__VA_ARGS__); \
    pr_err(fmt, ##__VA_ARGS__);       \
  } while (0)

#define pr_warn(fmt, ...)                             \
  do {                                                \
    printf(KYEL "++ " fmt "\n" RESET, ##__VA_ARGS__); \
    printf(RESET);                                    \
  } while (0)

#ifndef BUG
#define BUG(c)                                             \
  do {                                                     \
    __builtin_unreachable();                               \
    pr_err("FATAL BUG on %s line %d", __func__, __LINE__); \
    dump_stack();                                          \
    abort();                                               \
  } while (0)
#endif

#ifndef BUG_ON
#define BUG_ON(c)  \
  do {             \
    if (c) BUG(0); \
  } while (0)
#endif

#endif  // __COMMON_H__
