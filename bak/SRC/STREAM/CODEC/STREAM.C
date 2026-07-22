#include <dos.h>
#include "globals.h"
#include "structs.h"
#include "SRC/STREAM/CODEC/STREAM.H"

#define fmemcpy_far fmemcpy_far__proto
#include "SRC/IO/IO.H"
#include "SRC/SYS/FARPTR.H"
#include "SRC/STREAM/CODEC/CODEC.H"
#undef fmemcpy_far
extern void fmemcpy_far();

int stream_open(int codec_kind, BakFile *file, char *mode, unsigned long size) {
    int slot;
    char buf[4];

    if ((slot = stream_alloc_slot(mode)) == -1)
        return -1;

    g_pCurStreamDesc->src.pFile = file;
    g_pCurStreamDesc->dwFileStartOff = bak_ftell(file);
    g_pCurStreamDesc->dwInPos = 5;

    if (mode_has_read(mode)) {
        if (codec_init(codec_kind = (unsigned char)(g_pCurStreamDesc->bFlags = bak_fgetc(file)),
                       mode) == -1) {
            bak_fseek(file, -1L, 1);
            goto release;
        }
        g_pCurStreamDesc->dwInSize = size;
        bak_fread(&g_pCurStreamDesc->dwUncompressedSize, 1, 4, file);
        if (g_codec_vtable[codec_kind].pOpen_read)
            (*(void(near *)(void))g_codec_vtable[codec_kind].pOpen_read)();
        g_pCurStreamDesc->bFlags |= 0x40;
    } else {
        if (codec_init(codec_kind, mode) == -1) {
        release:
            return stream_release_slot(slot);
        }
        bak_putc(codec_kind, file);
        bak_fwrite(buf, 1, 4, file);
        if (g_codec_vtable[codec_kind].pOpen_write)
            (*(void(near *)(void))g_codec_vtable[codec_kind].pOpen_write)();
    }
    g_pCurStreamDesc->bFlags |= 0x20;
    return slot;
}

int stream_open_from_memory(int codec_id, unsigned char huge *pSrc, char *mode, unsigned long size) {
    int slot;

    if ((slot = stream_alloc_slot(mode)) == -1)
        return -1;

    g_pCurStreamDesc->src.pBufBase = pSrc;
    g_pCurStreamDesc->bFlags = (unsigned char)codec_id;
    g_pCurStreamDesc->dwInPos = 5;

    if (mode_has_read(mode)) {
        if (codec_init(codec_id = (unsigned char)(g_pCurStreamDesc->bFlags = *pSrc++), mode) == -1)
            goto release;
        fmemcpy_far((unsigned char far *)&g_pCurStreamDesc->dwUncompressedSize,
                    (unsigned char far *)pSrc, 4);
        g_pCurStreamDesc->dwInSize = size;
        if (g_codec_vtable[codec_id].pOpen_read)
            (*(void(near *)(void))g_codec_vtable[codec_id].pOpen_read)();
        g_pCurStreamDesc->bFlags |= 0x40;
    } else {
        if (codec_init(codec_id, mode) == -1) {
        release:
            return stream_release_slot(slot);
        }
        *g_pCurStreamDesc->src.pBufBase = (unsigned char)codec_id;
    }
    return slot;
}

int stream_close(int stream_id) {
    if (stream_select(stream_id) == 0)
        return -1;

    g_nStreamBytesWritten = 0;
    if (!(g_bCurStreamDescFlags & 0x40)) {
        (*(void(near *)(int))g_codec_vtable[(unsigned char)g_bCurStreamCodecId].pWrite_chunk)(1);
        if (g_bCurStreamDescFlags & 0x20) {
            bak_fseek(g_pCurStreamFp, g_pCurStreamDesc->dwFileStartOff + 1, 0);
            bak_fwrite(&g_pCurStreamDesc->dwUncompressedSize, 4, 1, g_pCurStreamFp);
            bak_fseek(g_pCurStreamFp, 0L, 2);
        } else {
            fmemcpy_far((unsigned char far *)(g_pCurStreamDesc->src.pBufBase + 1),
                        (unsigned char far *)&g_pCurStreamDesc->dwUncompressedSize, 4);
        }
    }
    stream_release_slot(stream_id);
    return g_nStreamBytesWritten;
}

unsigned int stream_read(int handle, void far *dest, unsigned int count) {
    if (stream_select(handle) == 0)
        return 0xffff;
    g_pStreamReadDst = normalize_far_ptr_thunk((unsigned char far *)dest);
    g_bCurStreamOpMode |= 0x40;
    return stream_consume(handle, count);
}

unsigned int stream_write(int stream_id, void far *pSrc, unsigned int count) {
    register unsigned char *pBuf; /* held in DI as the ring-buffer base across the copy loop */
    unsigned char huge *src;
    unsigned ring_head, ring_end;
    if (stream_select(stream_id) == 0)
        return 0xffff;
    g_nStreamBytesWritten = 0;
    g_pCurStreamDesc->dwUncompressedSize += count;
    pBuf = g_pCurStreamDesc->pBuf;
    src = (unsigned char huge *)pSrc;
    while (count != 0) {
        ring_head = g_pCurStreamDesc->bRingHead;
        ring_end = (g_pCurStreamDesc->bRingTail - 1) & 0x7f;
        do {
            pBuf[ring_head++] = *src++;
            count--;
            ring_head &= 0x7f;
        } while (ring_head != ring_end && count != 0);
        g_pCurStreamDesc->bRingHead = ring_head & 0x7f;
        (*(void(near *)(int))g_codec_vtable[(unsigned char)g_bCurStreamCodecId].pWrite_chunk)(0);
    }
    return g_nStreamBytesWritten;
}

unsigned long stream_size(int stream_id) {
    if (stream_select(stream_id) == 0) {
        return 0xffffffffUL;
    }
    return g_pCurStreamDesc->dwUncompressedSize;
}

long stream_seek(int handle, long position, int origin) {
    long pos;

    if (!stream_select(handle))
        return -1L;

    pos = 0;
    switch (origin) {
    case 1:
        pos = g_pCurStreamDesc->dwOutPos;
        break;
    case 2:
        pos = g_pCurStreamDesc->dwUncompressedSize;
        break;
    }
    pos += position;

    if (g_pCurStreamDesc->dwOutPos == pos)
        return pos;

    if ((long)g_pCurStreamDesc->dwOutPos > pos) {
        stream_rewind(handle);
        if (pos <= 0)
            return 0L;
    } else {
        if ((long)g_pCurStreamDesc->dwUncompressedSize <= pos) {
            pos = g_pCurStreamDesc->dwUncompressedSize - g_pCurStreamDesc->dwOutPos;
        } else {
            pos -= (long)g_pCurStreamDesc->dwOutPos;
        }
    }
    while ((pos -= stream_consume(handle, pos < 32000L ? (unsigned int)pos : 32000)) != 0) {
        g_pCurStreamSrcCursor = (char huge *)normalize_far_ptr_thunk(
            g_pCurStreamDesc->src.pBufBase + g_pCurStreamDesc->dwInPos);
    }
    return g_pCurStreamDesc->dwOutPos;
}

int stream_rewind(int stream_id) {
    if (!stream_select(stream_id) || !(g_bCurStreamDescFlags & 0x40))
        return -1;
    if (g_codec_vtable[(unsigned char)g_bCurStreamCodecId].pOpen_read)
        (*(void(near *)(void))g_codec_vtable[(unsigned char)g_bCurStreamCodecId].pOpen_read)();
    g_pCurStreamDesc->dwInPos = 5;
    if (g_pCurStreamDesc->bFlags & 0x20) {
        bak_fseek(g_pCurStreamFp, g_pCurStreamDesc->dwFileStartOff + 5, 0);
    } else {
        g_pCurStreamSrcCursor =
            (char huge *)normalize_far_ptr_thunk(g_pCurStreamDesc->src.pBufBase + 5);
    }
    g_pCurStreamDesc->bRingHead = g_pCurStreamDesc->bRingTail =
        (unsigned char)(g_pCurStreamDesc->dwOutPos = 0);
    return 0;
}
