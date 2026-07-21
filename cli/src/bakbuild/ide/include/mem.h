/* mem.h — IDE-indexing stub (NOT Borland's real mem.h). See clion_shim.h.
 * Declares the Borland block-memory vocabulary so `#include <mem.h>` sources
 * index without a missing-include error. Declarations only. */
#ifndef BAK_IDE_MEM_H
#define BAK_IDE_MEM_H
/* size_t comes from the force-included clion_shim.h. */
void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
void *memset(void *s, int c, size_t n);
int memcmp(const void *a, const void *b, size_t n);
void *memchr(const void *s, int c, size_t n);
void movedata(unsigned srcseg, unsigned srcoff, unsigned dstseg, unsigned dstoff, size_t n);
/* far-pointer variants (`far` is defined away by the shim, so these read as the
 * plain-pointer forms — fine for navigation). */
void *_fmemcpy(void *dst, const void *src, size_t n);
void *_fmemmove(void *dst, const void *src, size_t n);
void *_fmemset(void *s, int c, size_t n);
int _fmemcmp(const void *a, const void *b, size_t n);
#endif
