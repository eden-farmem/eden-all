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
    struct hopscotch_bucket *buckets;
    buckets = remoteable_alloc(sizeof(struct hopscotch_bucket) * (1 << exponent));
    if ( NULL == buckets ) {
        return NULL;
    }
    memset(buckets, 0, sizeof(struct hopscotch_bucket) * (1 << exponent));

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
            if ( 0 == memcmp(key, ht->buckets[idx + i].key,KEY_LEN) ) {
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
