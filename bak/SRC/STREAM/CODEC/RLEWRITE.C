#include "globals.h"
#include "structs.h"
#include "SRC/STREAM/CODEC/RLEWRITE.H"
#include "SRC/STREAM/CODEC/CODEC.H"

void near codec_rle_emit_run(int flush) {
    unsigned char tail;
    unsigned char head;
    uint remaining;
    int runLen;
    uint scanIdx;
    unsigned char isRepeat;
    unsigned char nextTail;
    register unsigned char *pRing;
    uint runByte;

    pRing = g_pCurStreamRingBuf;
    tail = g_pCurStreamDesc->bRingTail;
    head = g_pCurStreamDesc->bRingHead;

    while ((remaining = (uint)head - (uint)tail & 0x7f) != 0) {
        runByte = 0xffff;
        scanIdx = (uint)tail;
        runLen = 1;
        do {
            if (pRing[scanIdx] == runByte) {
                runLen++;
            } else {
                if (runLen >= 3)
                    break;
                runLen = 1;
            }
            runByte = (uint)pRing[scanIdx];
            ++scanIdx;
        } while ((uint)head != (scanIdx &= 0x7f));

        isRepeat = 0;
        if (runLen >= 3) {
            nextTail = (unsigned char)scanIdx - (char)runLen & 0x7f;
            if (nextTail == tail) {
                isRepeat = 0x80;
                nextTail = (unsigned char)scanIdx;
            }
        } else {
            nextTail = head;
        }
        runLen = (uint)nextTail - (uint)tail & 0x7f;
        if (runLen == (int)remaining && runLen < 0x7f && flush == 0)
            break;
        stream_putc((uint)runLen | isRepeat);
        if (isRepeat & 0x80) {
            stream_putc(runByte);
            tail = tail + (char)runLen & 0x7f;
        } else {
            while (runLen-- != 0) {
                stream_putc((uint)pRing[tail++]);
                tail &= 0x7f;
            }
        }
    }

    g_pCurStreamDesc->bRingTail = tail;
    g_pCurStreamDesc->bRingHead = head;
}
