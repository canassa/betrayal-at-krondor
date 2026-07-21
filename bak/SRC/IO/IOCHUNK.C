#include <mem.h>

#include "globals.h"
#include "structs.h"
#include "SRC/IO/IOCHUNK.H"
#include "SRC/IO/IO.H"

long bak_fread_chunked(uchar huge *dest, long size, long count, BakFile *fp) {
    long remaining;
    int n;
    char buf[128];

    remaining = size * count;
    while (remaining > 0) {
        n = (remaining > 0x80) ? 0x80 : (int)remaining;
        bak_fread(buf, n, 1, fp);
        _fmemcpy(dest, buf, n);
        dest += n;
        remaining -= n;
    }
    return count;
}

ulong bak_fwrite_chunked(uchar huge *src, ulong elem_size, ulong count, BakFile *stream) {
    ulong remaining;
    char buf[128];
    int n;

    remaining = elem_size * count;
    while ((long)remaining > 0) {
        n = (long)remaining > 0x80 ? 0x80 : (int)remaining;
        _fmemcpy(buf, src, n);
        bak_fwrite(buf, n, 1, stream);
        src += n;
        remaining -= n;
    }
    return remaining;
}
