/* stdlib.h — IDE-indexing stub (NOT a real libc header). See clion_shim.h.
 * Declares the general-utility vocabulary the sources use so `#include <stdlib.h>`
 * resolves without dragging in the host glibc header (which conflicts with the
 * reconstructed DOS-width types). `size_t` comes from the force-included shim.
 * Declarations only. */
#ifndef BAK_IDE_STDLIB_H
#define BAK_IDE_STDLIB_H
#define RAND_MAX 32767
#define EXIT_SUCCESS 0
#define EXIT_FAILURE 1
/* heap — identical prototypes to <alloc.h>, coexist in one TU */
void *malloc(size_t size);
void *calloc(size_t nitems, size_t size);
void *realloc(void *block, size_t size);
void free(void *block);
/* conversions */
int atoi(const char *s);
long atol(const char *s);
double atof(const char *s);
long strtol(const char *s, char **end, int base);
unsigned long strtoul(const char *s, char **end, int base);
double strtod(const char *s, char **end);
char *itoa(int value, char *buf, int radix);
char *ltoa(long value, char *buf, int radix);
/* random / process / search-sort */
int rand(void);
void srand(unsigned seed);
void exit(int status);
void abort(void);
int atexit(void (*func)(void));
int system(const char *cmd);
char *getenv(const char *name);
void qsort(void *base, size_t n, size_t size, int (*cmp)(const void *, const void *));
void *bsearch(const void *key, const void *base, size_t n, size_t size,
              int (*cmp)(const void *, const void *));
int abs(int x);
long labs(long x);
/* Borland bit-rotate intrinsics (real header: STDLIB.H) */
unsigned long _lrotl(unsigned long val, int count);
unsigned long _lrotr(unsigned long val, int count);
unsigned _rotl(unsigned val, int count);
unsigned _rotr(unsigned val, int count);
#endif
