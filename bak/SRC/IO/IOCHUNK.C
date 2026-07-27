#include <mem.h>

#include "structs.h"
#include "SRC/IO/IOCHUNK.H"
#include "SRC/IO/RESOURCE.H"

long res_fread_chunked(unsigned char huge *dest, long size, long count, ResFile *fp) {
    long remaining;
    int n;
    char buf[128];

    remaining = size * count;
    while (remaining > 0) {
        n = (remaining > 0x80) ? 0x80 : (int)remaining;
        res_fread(buf, n, 1, fp);
        _fmemcpy(dest, buf, n);
        dest += n;
        remaining -= n;
    }
    return count;
}

unsigned long res_fwrite_chunked(unsigned char huge *src, unsigned long elem_size, unsigned long count, ResFile *file) {
    unsigned long remaining;
    char buf[128];
    int n;

    remaining = elem_size * count;
    while ((long)remaining > 0) {
        n = (long)remaining > 0x80 ? 0x80 : (int)remaining;
        _fmemcpy(buf, src, n);
        res_fwrite(buf, n, 1, file);
        src += n;
        remaining -= n;
    }
    return remaining;
}
