// Copyright © 2018-2021 VMware, Inc. All Rights Reserved.
// SPDX-License-Identifier: BSD-2-Clause

#ifndef __LOGGING_H__
#define __LOGGING_H__

#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <string.h>

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

#define BUG(c)                                             \
  do {                                                     \
    __builtin_unreachable();                               \
    pr_err("FATAL BUG on %s line %d", __func__, __LINE__); \
    dump_stack();                                          \
    abort();                                               \
  } while (0)

#define BUG_ON(c)  \
  do {             \
    if (c) BUG(0); \
  } while (0)

#endif  // __LOGGING_H__
