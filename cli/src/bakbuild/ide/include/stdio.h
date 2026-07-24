/* stdio.h — IDE-indexing stub (NOT a real libc header). See clion_shim.h.
 * Declares the stdio vocabulary the sources use so `#include <stdio.h>` resolves
 * without dragging in the host glibc header (which conflicts with the
 * reconstructed DOS-width types). `size_t` / `va_list` come from the
 * force-included shim / the stdarg stub. Declarations only. */
#ifndef BAK_IDE_STDIO_H
#define BAK_IDE_STDIO_H
#include <stdarg.h> /* va_list, for the v*printf declarations (resolves to the stub) */
#ifndef EOF
#define EOF (-1)
#endif
#ifndef SEEK_SET
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#endif
/* Given a complete body (Borland's FILE is a real struct) so that arrays/sizeof
 * of FILE resolve; the members are indicative, not byte-accurate — nothing here
 * is executed (see clion_shim.h). */
typedef struct _iobuf {
    int level;
    unsigned flags;
    char fd;
    unsigned char hold;
    int bsize;
    unsigned char *buffer, *curp;
    unsigned istemp;
    short token;
} FILE;
extern FILE *stdin, *stdout, *stderr;

FILE *fopen(const char *path, const char *mode);
FILE *freopen(const char *path, const char *mode, FILE *stream);
int fclose(FILE *stream);
size_t fread(void *ptr, size_t size, size_t n, FILE *stream);
size_t fwrite(const void *ptr, size_t size, size_t n, FILE *stream);
int fseek(FILE *stream, long offset, int whence);
long ftell(FILE *stream);
void rewind(FILE *stream);
int fflush(FILE *stream);
void setbuf(FILE *stream, char *buf);
int setvbuf(FILE *stream, char *buf, int type, size_t size);
int feof(FILE *stream);
int ferror(FILE *stream);
int fgetc(FILE *stream);
int fputc(int c, FILE *stream);
int getc(FILE *stream);
int putc(int c, FILE *stream);
int getchar(void);
int putchar(int c);
char *fgets(char *s, int n, FILE *stream);
int fputs(const char *s, FILE *stream);
int puts(const char *s);
int ungetc(int c, FILE *stream);
int printf(const char *fmt, ...);
int fprintf(FILE *stream, const char *fmt, ...);
int sprintf(char *buf, const char *fmt, ...);
int scanf(const char *fmt, ...);
int fscanf(FILE *stream, const char *fmt, ...);
int sscanf(const char *s, const char *fmt, ...);
int vprintf(const char *fmt, va_list ap);
int vfprintf(FILE *stream, const char *fmt, va_list ap);
int vsprintf(char *buf, const char *fmt, va_list ap);
int remove(const char *path);
int rename(const char *from, const char *to);
void perror(const char *s);
#endif
