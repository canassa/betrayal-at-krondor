#include <dos.h>
#include "globals.h"
#include "structs.h"
#include "SRC/STREAM/BUFLOAD/CHUNKRD.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/STREAM/RESLOAD/IFFREAD.H"
#include "SRC/SYS/PANICF.H"

/**
 * @brief Chunk-read session's file-close-ownership flag.
 *
 * -1 = idle (no active session); 0 = borrowed an already-open handle (leave it
 * open); 1 = the session opened the file itself and owns the close.
 */
int g_nChunk_session_owns_close = -1;

ulong chunkread_fread_far_large(char far *dst, ulong len, BakFile *file) {
    char far *p;
    char *scratch;
    ulong remaining;
    uint chunks_per_window;
    uint window_left;
    char stackbuf[256];
    int n;
    register int size;

    remaining = len;

    size = 0x4000;
    while (size != 0 && (scratch = my_malloc(size)) == 0) {
        if (size > 0x800)
            size >>= 1;
        else
            size -= 0x100;
    }
    if (size == 0) {
        scratch = stackbuf;
        size = 0x100;
    }

    if (len & 0xffff0000L)
        chunks_per_window = (uint)(0x10000L / (long)size);
    else
        chunks_per_window = 0;

    window_left = chunks_per_window;
    p = dst;
    while (len != 0) {
        n = (long)len < (long)size ? (int)len : size;
        n = bak_fread(scratch, 1, n, file);
        if (n == 0)
            break;
        movedata(_DS, (uint)scratch, FP_SEG(p), FP_OFF(p), n);
        p += n;
        len -= n;
        if (chunks_per_window != 0 && --window_left == 0) {
            *(char huge **)&dst += 0x10000L;
            window_left = chunks_per_window;
            p = dst;
        }
    }

    if (scratch != 0)
        my_free(scratch);
    return remaining - len;
}

int far chunkread_session_close(BakFile *file) {

    g_nChunk_session_owns_close != -1 || panic(NULL);
    if (g_nChunk_session_owns_close != 0)
        cached_file_close(file);
    g_nChunk_session_owns_close = -1;
}

BakFile *far chunkread_session_open(BakFileRef *file, char *chunk_id) {
    (g_nChunk_session_owns_close == -1) || panic(NULL);
    if (is_file_cached(file) == 0) {
        if ((file = cached_file_open(file)) == 0)
            return 0;
        g_nChunk_session_owns_close = 1;
    } else {
        g_nChunk_session_owns_close = 0;
    }
    if (chunk_seek(file, chunk_id, 0) == -1L) {
        chunkread_session_close(file);
        return 0;
    }
    return file;
}

void far *chunkread_read_all_far(BakFileRef *file, char *chunk_id) {
    void far *buf;
    ulong size;

    buf = (void far *)0;
    if ((file = chunkread_session_open(file, chunk_id)) != 0) {
        size = cached_file_chunk_size(file);
        buf = alloc_far(size, 0);
        if (buf != 0) {
            (FP_OFF(buf) == 0) || panic(NULL);
            chunkread_fread_far_large(buf, size, file);
        }
        chunkread_session_close(file);
    }
    return buf;
}
