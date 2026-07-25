#ifndef BAK_VIDVTBL_H
#define BAK_VIDVTBL_H

#include "structs.h"
#include "SRC/IO/RESOURCE.H"

typedef unsigned long(far *AllocFarFn)(unsigned long size, unsigned short unused,
                                       unsigned short flags);
typedef int(far *FreememFn)(unsigned long ptr);
typedef int(far *ReadFarThunkFn)(int fd, void *buf, unsigned int count);
typedef int(far *CloseFarThunkFn)(int fd);
typedef void *(far *MallocFarFn)(unsigned int size);
typedef void *(far *CallocFarThunkFn)(unsigned int nitems, unsigned int size);
typedef void(far *FreeThunkFn)(void *ptr);
typedef char *(far *StrcatFarFn)(char *dest, char *src);
typedef char *(far *StrcpyFarFn)(char *dest, char *src);
typedef char *(far *StrchrFarFn)(char *s, int c);
typedef void(far *GfxDefaultFn)(int arg0, int arg1, int arg2);

typedef int(far *BakFcloseFn)(ResFile *file);
typedef int(far *BakFgetcFn)(ResFile *file);
typedef ResFile *(far *BakFopenFn)(char *filename, char *mode);
typedef int(far *BakFreadFn)(void *ptr, int size, int count, ResFile *file);
typedef int(far *BakFseekFn)(ResFile *file, int offset_lo, int offset_hi, int whence);
typedef int(far *BakFtellFn)(ResFile *file);
typedef int(far *BakFwriteFn)(void *ptr, int size, int count, ResFile *file);
typedef int(far *BakPutcFn)(int c, ResFile *file);
typedef void(far *BakRewindFn)(ResFile *file);

typedef struct VideoDriverImports {
    AllocFarFn far *alloc_far;
    FreememFn far *_freemem;
    ReadFarThunkFn far *_read_far_thunk;
    BakFseekFn far *bak_fseek;
    BakFtellFn far *bak_ftell;
    BakFwriteFn far *bak_fwrite;
    BakPutcFn far *bak_putc;
    BakRewindFn far *bak_rewind;
    CloseFarThunkFn far *_close_far_thunk;
    BakFopenFn far *bak_fopen;
    BakFreadFn far *bak_fread;
    BakFcloseFn far *bak_fclose;
    MallocFarFn far *malloc_far;
    CallocFarThunkFn far *calloc_far_thunk;
    BakFgetcFn far *bak_fgetc;
    FreeThunkFn far *free_thunk;
    StrcatFarFn far *strcat_far;
    StrcpyFarFn far *strcpy_far;
    StrchrFarFn far *strchr_far;
} VideoDriverImports;

extern GfxDefaultFn far *g_gfx_default_fptr;
extern VideoDriverImports g_video_driver_imports;

#endif
