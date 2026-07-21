/* string.h — IDE-indexing stub (NOT a real libc header). See clion_shim.h.
 * Declares the C string vocabulary the sources use, plus the Borland-specific
 * extensions (stricmp/strlwr/…), so `#include <string.h>` resolves without
 * dragging in the host glibc header (which conflicts with the reconstructed
 * DOS-width types). `size_t` comes from the force-included shim. Declarations
 * only. */
#ifndef BAK_IDE_STRING_H
#define BAK_IDE_STRING_H
size_t strlen(const char *s);
char *strcpy(char *dst, const char *src);
char *strncpy(char *dst, const char *src, size_t n);
char *strcat(char *dst, const char *src);
char *strncat(char *dst, const char *src, size_t n);
int strcmp(const char *a, const char *b);
int strncmp(const char *a, const char *b, size_t n);
char *strchr(const char *s, int c);
char *strrchr(const char *s, int c);
char *strstr(const char *hay, const char *needle);
char *strtok(char *s, const char *delim);
size_t strspn(const char *s, const char *set);
size_t strcspn(const char *s, const char *set);
char *strpbrk(const char *s, const char *set);
char *strdup(const char *s);
char *strerror(int errnum);
/* Borland/DOS extensions */
int stricmp(const char *a, const char *b);
int strnicmp(const char *a, const char *b, size_t n);
char *strlwr(char *s);
char *strupr(char *s);
char *strrev(char *s);
char *strset(char *s, int c);
char *strnset(char *s, int c, size_t n);
/* mem* also live in <mem.h>; identical prototypes coexist in one TU */
void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
void *memset(void *s, int c, size_t n);
int memcmp(const void *a, const void *b, size_t n);
void *memchr(const void *s, int c, size_t n);
#endif
