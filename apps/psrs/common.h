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
#endif

/* for kona */
#ifdef WITH_KONA
#include "klib.h"
#endif

/* for custom qsort */
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
#define RFREE		  rfree
#else
#define RMALLOC		malloc
#define RFREE		  free
#endif

/* fault annotations */
#if defined(SHENANGO) && defined(ANNOTATE_FAULTS)
// #define POSSIBLE_READ_FAULT_AT   /* already defined */
// #define POSSIBLE_WRITE_FAULT_AT  /* already defined */
#define POSSIBLE_READ_FAULT_AT    possible_read_fault_on
#define POSSIBLE_WRITE_FAULT_AT   possible_write_fault_on
// #define POSSIBLE_READ_FAULT_AT    is_page_mapped
// #define POSSIBLE_WRITE_FAULT_AT   is_page_mapped_and_wrprotected
#else
#define POSSIBLE_READ_FAULT_AT(a)	  {}
#define POSSIBLE_WRITE_FAULT_AT(a)	{}
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
