#include "common.h"
#include "qsort.h"

unsigned long counter = 0;

/*
 * Quicksort partition function
 *
 * This will give the pivot position for the next iteration.
 *
 */
size_t _partition(qelement_t *base, size_t l, size_t r)
{
    size_t i = l;             /* left approximation index */
    size_t j = r + 1;         /* right approximation index */
    qelement_t pivot = base[l];
    qelement_t* addr;

    while (i < j) {
        /* left-approx i to pivot */
        do { 
            ++i;
            addr = &base[i];
#ifndef NO_QSORT_ANNOTS
            if (((unsigned long)addr & _PAGE_OFFSET_MASK) == 0) {
                HINT_WRITE_FAULT_OPT_RDAHEAD_BLOCK(addr);
            }
#endif
        } while (*addr <= pivot && i <= r);

        /* right-approx j to pivot */
        do {
            --j;
            addr = &base[j];
#ifndef NO_QSORT_ANNOTS
            if (((unsigned long)addr & _PAGE_OFFSET_MASK) == (_PAGE_SIZE - sizeof(qelement_t))) {
                HINT_WRITE_FAULT_OPT_INVERSE_RDAHEAD_BLOCK(addr);
            }
#endif
        } while (*addr > pivot && j >= l);

        /* do swap if swap is possible */
        if (i < j) {
            qelement_t aux = base[i];
            base[i] = base[j];
            base[j] = aux;
        }
    }

    /* replace pivot */
    base[l] = base[j];
    base[j] = pivot;
    return j;
}

/*
 * Quicksort entry point function
 *
 * The sorting for base is done in-place.
 *
 */
void _quicksort(qelement_t *base, size_t l, size_t r)
{
    if (l >= r)
        return;

    size_t j = _partition(base, l, r);  /* pivot position */
    _quicksort(base, j + 1, r);         /* right chunk */
    if (j > 0)  
        _quicksort(base, l, j - 1);     /* left chunk */

}

void _qsort (void *base, size_t size, size_t s, __compar_fn_t cmp) {
    assert(s == sizeof(qelement_t));
    _quicksort(base, 0, size - 1);
}
