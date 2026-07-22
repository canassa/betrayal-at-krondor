#ifndef BAK_FARTHUNK_H
#define BAK_FARTHUNK_H

#include "structs.h"

extern int my_open2(char *filename, int oflag);
extern int my_open3(char *filename, int oflag, int pmode);
extern int my_close(int fd);
extern int my_read(int fd, void *buf, unsigned int count);
extern FILE *my_fopen(char *filename, char *mode);
extern int my_fseek(FILE *stream, long offset, int whence);
extern long my_ftell(FILE *stream);
extern int my_fread(void *ptr, int size, int count, FILE *stream);
extern int my_fwrite(void *ptr, int size, int count, FILE *stream);
extern int my_fputc(int c, FILE *stream);
extern void my_rewind(FILE *stream);
extern int fclose_far(FILE *stream);
extern void *my_malloc(unsigned int size);
extern void my_free(void *ptr);
extern char *my_strcat(char *dest, char *src);
extern char *my_strcpy(char *dest, char *src);
extern char *my_strchr(char *s, int c);
extern void *my_calloc(unsigned int nitems, unsigned int size);
extern void my_fgetc(FILE *f);

#endif
