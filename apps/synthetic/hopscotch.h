/*_
 * Copyright (c) 2016-2017 Hirochika Asai <asai@jar.jp>
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef _HOPSCOTCH_H
#define _HOPSCOTCH_H

#include <stdint.h>
#include <stdlib.h>
#include "runtime/sync.h"

/* NOTE: only dataplane operations are thread-safe i.e., 
 * insert/lookup/remove. Anything that affects the table 
 * itself (e.g., init, resize, release) is not. */
#define THREAD_SAFE

/* Initial size of buckets.  2 to the power of this value will be allocated. */
#define HOPSCOTCH_INIT_BSIZE_EXPONENT   10
/* Bitmap size used for linear probing in hopscotch hashing */
#define HOPSCOTCH_HOPINFO_SIZE          32
#define KEY_LEN                         12
#define MAX_LOCKLESS_RETRIES            2

// #define LOCK_INSIDE_BUCKET
#ifndef BUCKETS_PER_LOCK
#define BUCKETS_PER_LOCK                10000
#endif

/*
 * Buckets
 */
struct hopscotch_bucket {
    uint8_t key[KEY_LEN];
    uint8_t taken;
    void* data;
    uint32_t hopinfo;
#ifdef THREAD_SAFE
    /* coarse-grained lock to synchronize read-write and write-writes
     * used rarely by readers. yields to other threads if not available */
    mutex_t rw_lock;    
    /* very fine-grained lock to make reading/writing kv-data atomic 
     * as they're bigger than what built-in atomics can handle */
    spinlock_t kv_lock;    
    uint64_t timestamp;
    atomic_t marked;
#endif
} __attribute__ ((aligned (8)));

/*
 * Hash table of hopscotch hashing
 */
struct hopscotch_hash_table {
    size_t exponent;
    struct hopscotch_bucket *buckets;
    int _allocated;
    spinlock_t* kv_locks;
};

#ifdef __cplusplus
extern "C" {
#endif

    /* in hopscotch.c */
    struct hopscotch_hash_table *
    hopscotch_init(struct hopscotch_hash_table *, size_t);
    void hopscotch_release(struct hopscotch_hash_table *);
    void * hopscotch_lookup(struct hopscotch_hash_table *, void *, int*);
    int hopscotch_insert(struct hopscotch_hash_table *, void *, void *);
    void * hopscotch_remove(struct hopscotch_hash_table *, void *);
    int hopscotch_resize(struct hopscotch_hash_table *, int);

#ifdef __cplusplus
}
#endif


#endif /* _HOPSCOTCH_H */

/*
 * Local variables:
 * tab-width: 4
 * c-basic-offset: 4
 * End:
 * vim600: sw=4 ts=4 fdm=marker
 * vim<600: sw=4 ts=4
 */
