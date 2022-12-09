// Copyright © 2018-2021 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: BSD-2-Clause

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

/* for custom qsort */
#define CUSTOM_QSORT  /* default */
#ifdef CUSTOM_QSORT
#include "qsort.h"
#define QUICKSORT _qsort
typedef qelement_t element_t;
#else
#define QUICKSORT qsort
typedef int element_t;
#endif

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
#define HINT_READ_FAULT_ALL         hint_read_fault_all
#define HINT_WRITE_FAULT_ALL        hint_write_fault_all
#else
#define HINT_READ_FAULT             {}
#define HINT_WRITE_FAULT            {}
#define HINT_READ_FAULT_RDAHEAD     {}
#define HINT_WRITE_FAULT_RDAHEAD    {}
#define HINT_READ_FAULT_ALL         {}
#define HINT_WRITE_FAULT_ALL        {}
#endif

/* hints with build-time specified, optional readahead */
#ifdef RDAHEAD
#define HINT_READ_FAULT_OPT_RDAHEAD(x)                  HINT_READ_FAULT_RDAHEAD(x,RDAHEAD)
#define HINT_WRITE_FAULT_OPT_RDAHEAD(x)                 HINT_WRITE_FAULT_RDAHEAD(x,RDAHEAD)
#define HINT_READ_FAULT_OPT_INVERSE_RDAHEAD(x)          HINT_READ_FAULT_RDAHEAD(x,-RDAHEAD)
#define HINT_WRITE_FAULT_OPT_INVERSE_RDAHEAD(x)         HINT_WRITE_FAULT_RDAHEAD(x,-RDAHEAD)
#else
#define HINT_READ_FAULT_OPT_RDAHEAD                     HINT_READ_FAULT
#define HINT_WRITE_FAULT_OPT_RDAHEAD                    HINT_WRITE_FAULT
#define HINT_READ_FAULT_OPT_INVERSE_RDAHEAD             HINT_READ_FAULT
#define HINT_WRITE_FAULT_OPT_INVERSE_RDAHEAD            HINT_WRITE_FAULT
#endif

#if defined(OPTIONAL_BLOCKING) && defined(RDAHEAD)
#define HINT_READ_FAULT_OPT_RDAHEAD_BLOCK(x)            HINT_READ_FAULT_ALL(x,RDAHEAD,0,true)
#define HINT_WRITE_FAULT_OPT_RDAHEAD_BLOCK(x)           HINT_WRITE_FAULT_ALL(x,RDAHEAD,0,true)
#define HINT_READ_FAULT_OPT_INVERSE_RDAHEAD_BLOCK(x)    HINT_READ_FAULT_ALL(x,-RDAHEAD,0,true)
#define HINT_WRITE_FAULT_OPT_INVERSE_RDAHEAD_BLOCK(x)   HINT_WRITE_FAULT_ALL(x,-RDAHEAD,0,true)
#elif defined(OPTIONAL_BLOCKING)
#define HINT_READ_FAULT_OPT_RDAHEAD_BLOCK(x)            HINT_READ_FAULT_ALL(x,0,0,true)
#define HINT_WRITE_FAULT_OPT_RDAHEAD_BLOCK(x)           HINT_WRITE_FAULT_ALL(x,0,0,true)
#define HINT_READ_FAULT_OPT_INVERSE_RDAHEAD_BLOCK(x)    HINT_READ_FAULT_ALL(x,0,0,true)
#define HINT_WRITE_FAULT_OPT_INVERSE_RDAHEAD_BLOCK(x)   HINT_WRITE_FAULT_ALL(x,0,0,true)
#else
#define HINT_READ_FAULT_OPT_RDAHEAD_BLOCK               HINT_READ_FAULT_OPT_RDAHEAD
#define HINT_WRITE_FAULT_OPT_RDAHEAD_BLOCK              HINT_WRITE_FAULT_OPT_RDAHEAD
#define HINT_READ_FAULT_OPT_INVERSE_RDAHEAD_BLOCK       HINT_READ_FAULT_OPT_INVERSE_RDAHEAD
#define HINT_WRITE_FAULT_OPT_INVERSE_RDAHEAD_BLOCK      HINT_WRITE_FAULT_OPT_INVERSE_RDAHEAD
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
