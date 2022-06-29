#ifndef __QSORT_H__
#define __QSORT_H__

#include <stddef.h>
#include <stdlib.h>

typedef int qelement_t;
void _qsort (void *b, size_t n, size_t s, __compar_fn_t cmp);

#endif /* ifndef __QSORT_H__ */
