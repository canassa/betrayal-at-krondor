/* alloc.h — IDE-indexing stub (NOT Borland's real alloc.h). See clion_shim.h.
 * Declares the Borland near/far heap vocabulary so `#include <alloc.h>` sources
 * index without a missing-include error. The near-heap prototypes match libc so
 * they coexist with a host <stdlib.h> in the same TU. Declarations only. */
#ifndef BAK_IDE_ALLOC_H
#define BAK_IDE_ALLOC_H
/* size_t comes from the force-included clion_shim.h. */
void *malloc(size_t size);
void *calloc(size_t nitems, size_t size);
void *realloc(void *block, size_t size);
void free(void *block);
/* far heap */
void *farmalloc(unsigned long size);
void *farcalloc(unsigned long nunits, unsigned long unitsz);
void *farrealloc(void *block, unsigned long size);
void farfree(void *block);
unsigned coreleft(void);
unsigned long farcoreleft(void);
#endif
