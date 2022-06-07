#ifndef __QSORT_H__
#define __QSORT_H__

#include <stddef.h>
typedef int qelement_t;

/*
 * Quicksort
 *
 * Sort an array of integers of length 'size' using the quicksort
 * algorithm, as proposed by Cormen et al.
 *
 */
#define quicksort(array, size) _quicksort((array), 0, ((size) - 1))
size_t _partition(qelement_t *base, size_t l, size_t r);
void _quicksort(qelement_t *base, size_t l, size_t r);

#endif /* ifndef __QSORT_H__ */
