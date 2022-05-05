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

#include "hopscotch.h"
#include <stdlib.h>
#include <string.h>

#include "utils.h"
#include "asm/atomic.h"
#include "base/atomic.h"

/*
 * Jenkins Hash Function
 */
static __inline__ uint32_t
_jenkins_hash(uint8_t *key, size_t len)
{
    uint32_t hash;
    size_t i;

    hash = 0;
    for ( i = 0; i < len; i++ ) {
        hash += key[i];
        hash += (hash << 10);
        hash ^= (hash >> 6);
    }
    hash += (hash << 3);
    hash ^= (hash >> 11);
    hash += (hash << 15);

    return hash;
}

/*
 * Initialize the hash table
 */
struct hopscotch_hash_table *
hopscotch_init(struct hopscotch_hash_table *ht, size_t exponent)
{
    /* Allocate buckets first */
    int i;
    struct hopscotch_bucket *buckets;
    size_t nbuckets = (1 << exponent);
    pr_info("memory for hash table: %lu MB", 
        sizeof(struct hopscotch_bucket) * nbuckets / (1<<20));
    buckets = remoteable_alloc(sizeof(struct hopscotch_bucket) * nbuckets);
    if ( NULL == buckets ) {
        return NULL;
    }
    memset(buckets, 0, sizeof(struct hopscotch_bucket) * nbuckets);
#ifdef THREAD_SAFE
    for (i = nbuckets; i >= 0; i--) {
        mutex_init(&buckets[i].rw_lock);
        spin_lock_init(&buckets[i].kv_lock);
        buckets[i].marked = (atomic_t) ATOMIC_INIT(0);
    }
#endif

    if ( NULL == ht ) {
        ht = malloc(sizeof(struct hopscotch_hash_table));
        if ( NULL == ht ) {
            return NULL;
        }
        ht->_allocated = 1;
    } else {
        ht->_allocated = 0;
    }
    ht->exponent = exponent;
    ht->buckets = buckets;

    return ht;
}

/*
 * Release the hash table
 */
void
hopscotch_release(struct hopscotch_hash_table *ht)
{
    free(ht->buckets);
    if ( ht->_allocated ) {
        free(ht);
    }
}

#ifndef THREAD_SAFE
/*
 * Lookup
 */
void *
hopscotch_lookup(struct hopscotch_hash_table *ht, void *key)
{
    uint32_t h;
    size_t idx;
    size_t i;
    size_t sz;

    sz = 1ULL << ht->exponent;
    h = _jenkins_hash(key,KEY_LEN);
    idx = h & (sz - 1);

    if ( !ht->buckets[idx].hopinfo ) {
        return NULL;
    }
    for ( i = 0; i < HOPSCOTCH_HOPINFO_SIZE; i++ ) {
        if ( ht->buckets[idx].hopinfo & (1 << i) ) {
            if ( 0 == memcmp(key, ht->buckets[idx + i].key, KEY_LEN) ) {
                /* Found */
                return ht->buckets[idx + i].data;
            }
        }
    }
    return NULL;
}


/*
 * Insert an entry to the hash table
 */
int
hopscotch_insert(struct hopscotch_hash_table *ht, void *key, void *data)
{
    uint32_t h;
    size_t idx;
    size_t i;
    size_t sz;
    size_t off;
    size_t j;

    /* Ensure the key does not exist.  Duplicate keys are not allowed. */
    if ( NULL != hopscotch_lookup(ht, key) ) {
        /* The key already exists. */
        return -1;
    }

    sz = 1ULL << ht->exponent;
    h = _jenkins_hash(key,KEY_LEN);
    idx = h & (sz - 1);

    /* Linear probing to find an empty bucket */
    for ( i = idx; i < sz; i++ ) {
        if ( ! ht->buckets[i].taken ) {
            /* Found an available bucket */
            ht->buckets[i].taken = 1;       /* TODO need CAS op */
            while ( i - idx >= HOPSCOTCH_HOPINFO_SIZE ) {
                for ( j = 1; j < HOPSCOTCH_HOPINFO_SIZE; j++ ) {
                    if ( ht->buckets[i - j].hopinfo ) {
                        off = __builtin_ctz(ht->buckets[i - j].hopinfo);
                        if ( off >= j ) {
                            continue;
                        }
                        memcpy(ht->buckets[i].key, ht->buckets[i - j + off].key, KEY_LEN);
                        ht->buckets[i].data = ht->buckets[i - j + off].data;
                        memset(ht->buckets[idx + i].key, 0, KEY_LEN);
                        ht->buckets[i - j + off].data = NULL;
                        ht->buckets[i - j].hopinfo &= ~(1ULL << off);
                        ht->buckets[i - j].hopinfo |= (1ULL << j);
                        i = i - j + off;
                        break;
                    }
                }
                if ( j >= HOPSCOTCH_HOPINFO_SIZE ) {
                    /* need to resize the table (error out for now) */
                    pr_err("hash bucket full; need to resize table");
                    ASSERT(0);
                }
            }

            off = i - idx;
            memcpy(ht->buckets[i].key, key, KEY_LEN);
            ht->buckets[i].data = data;
            ht->buckets[idx].hopinfo |= (1ULL << off);
            ASSERT(ht->buckets[i].taken);
            return 0;
        }
    }

    /* need to resize the table (error out for now) */
    pr_err("hash table full");
    ASSERT(0);
}

/*
 * Remove an item
 */
void *
hopscotch_remove(struct hopscotch_hash_table *ht, void *key)
{
#ifdef THREAD_SAFE
    ASSERT(0);  /* use the _safe version */
#endif
    uint32_t h;
    size_t idx;
    size_t i;
    size_t sz;
    void *data;

    sz = 1ULL << ht->exponent;
    h = _jenkins_hash(key,KEY_LEN);
    idx = h & (sz - 1);

    if ( !ht->buckets[idx].hopinfo ) {
        return NULL;
    }
    for ( i = 0; i < HOPSCOTCH_HOPINFO_SIZE; i++ ) {
        if ( ht->buckets[idx].hopinfo & (1 << i) ) {
            if ( 0 == memcmp(key, ht->buckets[idx + i].key, KEY_LEN) ) {
                /* Found */
                data = ht->buckets[idx + i].data;
                ht->buckets[idx].hopinfo &= ~(1ULL << i);
                memset(ht->buckets[idx + i].key, 0, KEY_LEN);
                ht->buckets[idx + i].data = NULL;
                ht->buckets[i].taken = 0;
                return data;
            }
        }
    }

    return NULL;
}

#else

/*
 * Lookup Thread-safe
 */
void *
hopscotch_lookup(struct hopscotch_hash_table *ht, void *key)
{
    uint32_t h, hopinfo, retries;
    size_t idx, i, sz;
    bool lock, locked, found;
    uint64_t timestamp;
    struct hopscotch_bucket *bucket, *hop;
    void* value;

    /* find bucket */
    sz = 1ULL << ht->exponent;
    h = _jenkins_hash(key,KEY_LEN);
    idx = h & (sz - 1);
    bucket = &(ht->buckets[idx]);

    /* try without locking a few times */
    lock = locked = found = false;
    lock = true;    /* coarse-locking for readers too */
    retries = 0;
    value = NULL;
    do {
        if (lock) {
            mutex_lock(&bucket->rw_lock);
            locked = true;
        }

        timestamp = load_acquire(&(bucket->timestamp)); /* fence */
        hopinfo = bucket->hopinfo;
        if (hopinfo) {
            for ( i = 0; i < HOPSCOTCH_HOPINFO_SIZE; i++ ) {
                if (hopinfo & (1 << i)) {
                    /* read key-value atomically. TODO: how expensive is this? */
                    hop = &(ht->buckets[idx + i]);
                    spin_lock(&hop->kv_lock);
                    if(0 == memcmp(key, hop->key, KEY_LEN)) {
                        /* found */
                        value = hop->data;
                        found = true;
                    }
                    spin_unlock(&hop->kv_lock);
                    if (found)
                        goto out;
                }
            }
        }

        /* if not under lock, we could have a race with insert() which  
         * moved our hop-bucket during lookup, hence missing it */
        if (timestamp == ACCESS_ONCE(bucket->timestamp)) {
            /* we didn't miss anything, the key really wasn't there */
            value = NULL;
            goto out;
        }

        /* something changed the bucket while lookup */
        /* but this cannot happen under a lock */
        ASSERT(!locked);    

        /* keep trying without locking */
        if (retries++ < MAX_LOCKLESS_RETRIES)
            continue;

        /* try with lock as a last resort */
        lock = true;
    } while(1);

out:
    if (locked) 
        mutex_unlock(&bucket->rw_lock);
    return value;
}


/*
 * Insert (or updates) an entry to the hash table, thread-safe
 */
int
hopscotch_insert(struct hopscotch_hash_table *ht, void *key, void *data)
{
    uint32_t h, hopinfo;
    size_t idx, i, sz, off, j;
    struct hopscotch_bucket *bucket, *hop;
    struct hopscotch_bucket *anchor, *from, *to;
    bool marked, found;
    int retval = 1;

    sz = 1ULL << ht->exponent;
    h = _jenkins_hash(key,KEY_LEN);
    idx = h & (sz - 1);
    bucket = &(ht->buckets[idx]);

    /* must lock */
    mutex_lock(&bucket->rw_lock);
    hopinfo = load_acquire(&(bucket->hopinfo)); 

    /* check if key already exists and if so, update */
    if (hopinfo) {
        found = false;
        for ( i = 0; i < HOPSCOTCH_HOPINFO_SIZE; i++ ) {
            if (hopinfo & (1 << i)) {
                /* read and update key-value atomically. TODO: how expensive is this? */
                hop = &(ht->buckets[idx + i]);
                spin_lock(&hop->kv_lock);
                if (0 == memcmp(key, hop->key, KEY_LEN)) {  
                    /* found */
                    hop->data = data; 
                    found = true;
                }
                spin_unlock(&hop->kv_lock);
                if (found) {
                    retval = 0;
                    pr_debug("replacing key %lu", (uint64_t)data);
                    goto out;
                }
            }
        }
    }

    /* key not found, need to insert */
    /* probing to find an empty bucket */
    pr_debug("inserting key %lu (hash bucket: %ld)", (uint64_t)data, idx);
    for ( i = idx; i < sz; i++ ) {
        marked = atomic_cmpxchg(&ht->buckets[i].marked, 0, 1);
        if (marked) {
            /* found an available bucket */
            pr_debug("inserting key %lu: found empty bucket %ld", (uint64_t)data, i);
            while ( i - idx >= HOPSCOTCH_HOPINFO_SIZE ) {
                /* but it is out of the hopscotch window; we need to move it up */
                pr_debug("inserting key %lu: bucket out of hop window", (uint64_t)data);
                to = &(ht->buckets[i]);
                for ( j = 1; j < HOPSCOTCH_HOPINFO_SIZE; j++ ) {
                    /* for all buckets (anchors) for which the empty item 
                     * falls within hop window... */
                    anchor = &(ht->buckets[i - j]);
                    if (!anchor->hopinfo) {
                        continue;
                    }

                    /* lock and recheck hopinfo */
                    mutex_lock(&anchor->rw_lock);
                    hopinfo = load_acquire(&(anchor->hopinfo)); 
                    if (unlikely(!hopinfo)) {
                        mutex_unlock(&anchor->rw_lock);
                        continue;
                    }

                    /* this anchor doesn't have an item that falls before 
                     * our empty item and hence is not a candidate */
                    off = __builtin_ctz(hopinfo);
                    if ( off >= j ) {
                        mutex_unlock(&anchor->rw_lock);
                        continue;
                    }

                    /* found a swappable item, move data */
                    from = &(ht->buckets[i - j + off]);

                    /* always take nested locks in top-down order */
                    /* TODO: can we do without locking _to_? */
                    spin_lock(&from->kv_lock);
                    spin_lock(&to->kv_lock);
                    memcpy(to->key, from->key, KEY_LEN);
                    to->data = from->data;
                    // clearing _from_ values is not really necessary
                    // memset(from.key, 0, KEY_LEN);
                    // from.data = NULL;
                    spin_unlock(&to->kv_lock);
                    spin_unlock(&from->kv_lock);

                    /* sanity check that _from_ was already marked */
                    ASSERT(atomic_read(&from->marked) == 1);

                    /* update hop pointers in anchor */
                    anchor->hopinfo |= (1ULL << j);
                    anchor->timestamp++;
                    anchor->hopinfo &= ~(1ULL << off);
                    mutex_unlock(&anchor->rw_lock);

                    /* jump backwards */
                    i = i - j + off;
                    break;
                }
                if ( j >= HOPSCOTCH_HOPINFO_SIZE ) {
                    /* bucket is full and we need to resize the table,
                     * error out for now */
                    ASSERT(0);
                }
            }

            /* an empty bucket in the hop window, insert */

            pr_debug("inserting key %lu: at bucket %ld", (uint64_t)data, i);
            off = i - idx;
            to = &(ht->buckets[i]);
            spin_lock(&to->kv_lock);
            memcpy(to->key, key, KEY_LEN);
            to->data = data;
            spin_unlock(&to->kv_lock);
            bucket->hopinfo |= (1ULL << off);

            /* success */
            retval = 0;
            goto out;
        }
    }
    /* need to resize the table, error out for now */
    ASSERT(0);

out:
    pr_debug("done inserting key %lu", (uint64_t)data);
    mutex_unlock(&bucket->rw_lock);
    pr_debug("done inserting key %lu", (uint64_t)data);
    return retval;
}

/*
 * Remove an item - thread-safe
 */
void *
hopscotch_remove(struct hopscotch_hash_table *ht, void *key)
{
    uint32_t h, hopinfo;
    size_t idx, i, sz, off, j;
    struct hopscotch_bucket *bucket, *hop;
    bool unmarked, found;
    int retval = 1;
    void* value;

    sz = 1ULL << ht->exponent;
    h = _jenkins_hash(key,KEY_LEN);
    idx = h & (sz - 1);
    bucket = &(ht->buckets[idx]);

    /* must lock */
    mutex_lock(&bucket->rw_lock);
    hopinfo = load_acquire(&(bucket->hopinfo)); 

    /* check if key exists and if so, clear the bucket */
    value = NULL;
    if (hopinfo) {
        found = false;
        for ( i = 0; i < HOPSCOTCH_HOPINFO_SIZE; i++ ) {
            if (hopinfo & (1 << i)) {
                /* read and update key-value atomically. TODO: how expensive is this? */
                hop = &(ht->buckets[idx + i]);
                spin_lock(&hop->kv_lock);
                if (0 == memcmp(key, hop->key, KEY_LEN)) {  
                    /* found */
                    value = hop->data;
                    found = true;
                }
                spin_unlock(&hop->kv_lock);
                if (found) {
                    hop->hopinfo &= ~(1ULL << i);       /* unlink the bucket */
                    ASSERT(atomic_read(&hop->marked));
                    atomic_write(&hop->marked, 0);      /* mark it available */
                    goto out;
                }
            }
        }
    }

out:
    mutex_unlock(&bucket->rw_lock);
    return value;
}

#endif

/*
 * Resize the bucket size of the hash table
 */
int
hopscotch_resize(struct hopscotch_hash_table *ht, int delta)
{
    size_t sz;
    size_t oexp;
    size_t nexp;
    ssize_t i;
    struct hopscotch_bucket *nbuckets;
    struct hopscotch_bucket *obuckets;
    int ret;

    oexp = ht->exponent;
    nexp = ht->exponent + delta;
    sz = 1ULL << nexp;

    nbuckets = malloc(sizeof(struct hopscotch_bucket) * sz);
    if ( NULL == nbuckets ) {
        return -1;
    }
    memset(nbuckets, 0, sizeof(struct hopscotch_bucket) * sz);
    obuckets = ht->buckets;

    ht->buckets = nbuckets;
    ht->exponent = nexp;

    for ( i = 0; i < (1LL << oexp); i++ ) {
        if ( obuckets[i].key ) {
            ret = hopscotch_insert(ht, obuckets[i].key, obuckets[i].data);
            if ( ret < 0 ) {
                ht->buckets = obuckets;
                ht->exponent = oexp;
                free(nbuckets);
                return -1;
            }
        }
    }
    free(obuckets);

    return 0;
}

/*
 * Local variables:
 * tab-width: 4
 * c-basic-offset: 4
 * End:
 * vim600: sw=4 ts=4 fdm=marker
 * vim<600: sw=4 ts=4
 */
