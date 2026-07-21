#include "globals.h"
#include "structs.h"
#include "SRC/STREAM/CODEC/LZW.H"
#include "SRC/STREAM/CODEC/CODEC.H"

unsigned char g_lzwEncOutBuf[12];
unsigned short g_wLzwEncCurCode;
unsigned char g_bLzwEncSeedPending;
long g_lLzwOutByteCount;
unsigned short g_wLzwOutBitPos;
unsigned short g_wLzwEncMaxCode;
unsigned short g_wLzwEncCodeBits;

unsigned short g_nLzwTableSize = 0x138b;
unsigned short g_nLzwNextFreeCode = 0x0000;
unsigned short g_nLzwMode = 0x0000;
unsigned short g_bLzwClearPending = 0x0000;
long g_lLzwBestRatio = 0x00000000UL;
long g_lLzwRatioThresh = 0x00002710UL;
long g_lLzwInputCount = 0x00000001UL;
long g_lLzwOutputCount = 0x00000000UL;
unsigned char g_lzwHiMask[9] = {0xff, 0xfe, 0xfc, 0xf8, 0xf0, 0xe0, 0xc0, 0x80, 0x00};
unsigned char g_lzwLoMask[9] = {0x00, 0x01, 0x03, 0x07, 0x0f, 0x1f, 0x3f, 0x7f, 0xff};

int near lzw_reset_state(void) {
    g_wLzwOutBitPos = 0;
    g_lLzwOutByteCount = 0;
    g_lLzwOutputCount = 0;
    g_bLzwClearPending = 0;
    g_lLzwBestRatio = 0;
    g_lLzwInputCount = 1;

    g_lLzwRatioThresh = 0x2710;
    g_wLzwEncMaxCode = (1 << (g_wLzwEncCodeBits = 9)) - 1;

    g_nLzwNextFreeCode = 0x101;
    lzw_clear_code_table((int)g_nLzwTableSize);
    g_bLzwEncSeedPending = 1;
    g_nLzwMode = 0;
    return 0;
}

int near lzw_decompressor_init(void) {
    lzw_reset_state();
    g_nLzwMode = 1;
    return 0;
}

int near lzw_compress_input(int flush) {
    long hashKey;
    int step;
    unsigned int readIdx;
    unsigned int sentinel;
    unsigned char *pRing;
    register int curByte;
    register int slot = 0;

    pRing = g_pCurStreamRingBuf;
    readIdx = g_pCurStreamDesc->bRingTail;
    sentinel = g_pCurStreamDesc->bRingHead;

    while ((readIdx &= 0x7f) != sentinel) {
        curByte = pRing[readIdx];
        readIdx++;
        if (g_bLzwEncSeedPending != 0) {
            g_wLzwEncCurCode = curByte;
            g_bLzwEncSeedPending = 0;
            continue;
        }

        g_lLzwInputCount++;
        hashKey = ((long)curByte << 12) + (long)(int)g_wLzwEncCurCode;
        slot = (curByte << 4) ^ g_wLzwEncCurCode;
        if (slot == 0)
            step = 1;
        else
            step = g_nLzwTableSize - slot;

        for (;;) {
            if (*(long huge *)(g_pCurCodecScratch + ((long)slot << 2)) == hashKey) {
                g_wLzwEncCurCode =
                    *(unsigned short huge *)(g_pCurCodecScratch + ((long)slot << 1) + 0x4e2c);
                goto next;
            }
            if (*(long huge *)(g_pCurCodecScratch + ((long)slot << 2)) < 0) {

                lzw_emit_code(g_wLzwEncCurCode);
                g_lLzwOutputCount++;
                g_wLzwEncCurCode = curByte;
                if ((int)g_nLzwNextFreeCode < 0x1000) {
                    *(unsigned short huge *)(g_pCurCodecScratch + ((long)slot << 1) + 0x4e2c) =
                        g_nLzwNextFreeCode;
                    g_nLzwNextFreeCode++;
                    *(long huge *)(g_pCurCodecScratch + ((long)slot << 2)) = hashKey;
                } else if (g_lLzwInputCount >= g_lLzwRatioThresh || g_nLzwMode != 0) {
                    lzw_check_ratio();
                }
                goto next;
            }

            if ((slot -= step) < 0)
                slot += (int)g_nLzwTableSize;
        }
    next:;
    }

    g_pCurStreamDesc->bRingTail = (unsigned char)readIdx;
    g_pCurStreamDesc->bRingHead = (unsigned char)sentinel;
    if (flush != 0) {
        lzw_emit_code(g_wLzwEncCurCode);
        g_lLzwOutputCount++;
        lzw_emit_code(-1);
    }
    return 0;
}

void near lzw_emit_code(int code) {
    register unsigned char *p;
    register int rem;
    int bitpos;
    int i;

    bitpos = g_wLzwOutBitPos;
    rem = g_wLzwEncCodeBits;
    p = g_lzwEncOutBuf;

    if (code >= 0) {
        p += bitpos >> 3;
        bitpos &= 7;
        *p = (*p & g_lzwLoMask[bitpos]) | ((unsigned char)code << bitpos & g_lzwHiMask[bitpos]);
        p++;
        rem -= 8 - bitpos;
        code >>= 8 - bitpos;
        if (rem >= 8) {
            *p++ = (unsigned char)code;
            code >>= 8;
            rem -= 8;
        }
        if (rem != 0)
            *p = (unsigned char)code;

        g_wLzwOutBitPos += g_wLzwEncCodeBits;
        if (g_wLzwEncCodeBits * 8 == g_wLzwOutBitPos) {
            p = g_lzwEncOutBuf;
            rem = g_wLzwEncCodeBits;
            g_lLzwOutByteCount += rem;
            do {
                stream_putc(*p++);
            } while (--rem != 0);
            g_wLzwOutBitPos = 0;
        }

        if ((int)g_nLzwNextFreeCode > (int)g_wLzwEncMaxCode || g_bLzwClearPending != 0) {
            if ((int)g_wLzwOutBitPos > 0) {
                for (i = 0; i < (int)g_wLzwEncCodeBits; i++)
                    stream_putc(g_lzwEncOutBuf[i]);
                g_lLzwOutByteCount += (int)g_wLzwEncCodeBits;
            }
            g_wLzwOutBitPos = 0;
            if (g_bLzwClearPending != 0) {
                g_wLzwEncMaxCode = (1 << (g_wLzwEncCodeBits = 9)) - 1;
                g_bLzwClearPending = 0;
            } else {
                g_wLzwEncCodeBits++;
                if (g_wLzwEncCodeBits == 12)
                    g_wLzwEncMaxCode = 0x1000;
                else
                    g_wLzwEncMaxCode = (1 << g_wLzwEncCodeBits) - 1;
            }
        }
    } else {
        if ((int)g_wLzwOutBitPos > 0) {
            for (i = 0; i < ((int)g_wLzwOutBitPos + 7) / 8; i++)
                stream_putc(g_lzwEncOutBuf[i]);
        }
        g_lLzwOutByteCount += ((int)g_wLzwOutBitPos + 7) / 8;
        g_wLzwOutBitPos = 0;
    }
}

long thunk_LDIV_at(long numer, long denom) {
    return numer / denom;
}

void near lzw_check_ratio(void) {
    long ratio;

    g_lLzwRatioThresh = g_lLzwInputCount + 10000;

    if (g_lLzwInputCount <= 0x7fffffL) {
        ratio = thunk_LDIV_at(g_lLzwInputCount << 8, g_lLzwOutByteCount);
    } else {
        if ((ratio = g_lLzwOutByteCount >> 8) == 0)
            ratio = 0x7fffffffL;
        else
            ratio = thunk_LDIV_at(g_lLzwInputCount, ratio);
    }

    if (ratio > g_lLzwBestRatio) {
        g_lLzwBestRatio = ratio;
    } else {
        g_lLzwBestRatio = 0;
        lzw_clear_code_table((long)(int)g_nLzwTableSize);
        g_nLzwNextFreeCode = 0x101;
        g_bLzwClearPending = 1;
        lzw_emit_code(0x100);
    }
}

void near lzw_clear_code_table(long count) {
    long huge *p;

    p = (long huge *)g_pCurCodecScratch;
    while (--count >= 0) {
        *p = -1L;
        p++;
    }
}
