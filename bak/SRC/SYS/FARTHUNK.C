#include <io.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "globals.h"
#include "structs.h"
#include "SRC/SYS/FARTHUNK.H"

int my_open2(char *filename, int oflag) {
    return open(filename, oflag);
}

int my_open3(char *filename, int oflag, int pmode) {
    return open(filename, oflag, pmode);
}

int my_close(int fd) {
    return close(fd);
}

int my_read(int fd, void *buf, unsigned int count) {
    return read(fd, buf, count);
}

FILE *my_fopen(char *filename, char *mode) {
    return fopen(filename, mode);
}

int my_fseek(FILE *stream, long offset, int whence) {
    return fseek(stream, offset, whence);
}

long my_ftell(FILE *stream) {
    return ftell(stream);
}

int my_fread(void *ptr, int size, int count, FILE *stream) {
    return fread(ptr, size, count, stream);
}

int my_fwrite(void *ptr, int size, int count, FILE *stream) {
    return fwrite(ptr, size, count, stream);
}

int my_fputc(int c, FILE *stream) {
    return fputc(c, stream);
}

void my_rewind(FILE *stream) {
    rewind(stream);
}

int fclose_far(FILE *stream) {
    return fclose(stream);
}

void *my_malloc(unsigned int size) {
    return malloc(size);
}

void my_free(void *ptr) {
    free(ptr);
}

char *my_strcat(char *dest, char *src) {
    return strcat(dest, src);
}

char *my_strcpy(char *dest, char *src) {
    return strcpy(dest, src);
}

char *my_strchr(char *s, int c) {
    return strchr(s, c);
}

void *my_calloc(unsigned int nitems, unsigned int size) {
    return calloc(nitems, size);
}

void my_fgetc(FILE *f) {
    fgetc(f);
}
