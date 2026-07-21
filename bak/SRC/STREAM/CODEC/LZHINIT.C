#include "globals.h"
#include "structs.h"
#include "SRC/STREAM/CODEC/LZHINIT.H"
#include "SRC/SYS/FARPTR.H"

unsigned char g_bLzwOutputSuspended;
unsigned char g_bLzwNeedSeedCode;
unsigned short g_wLzwInBufBitsTotal;
unsigned short g_wLzwInBitPos;
unsigned char far *g_pLzwScratchTail;
unsigned short g_wLzwNewCode;
unsigned short g_wLzwPrevCode;
unsigned short g_wLzwLastByte;
unsigned short g_wLzwResetWidthPending;
unsigned short g_wLzwNextCode;
unsigned short g_wLzwMaxCode;
unsigned short g_wLzwCodeBits;

void near lzh_decoder_init(void) {
    register int j;
    int i;

    memset_far(g_pCurCodecScratch, '\0', 0x3aa1L);
    g_wLzwMaxCode = (1 << (g_wLzwCodeBits = 9)) - 1;
    for (i = 0xff; i >= 0; i--) {
        ((unsigned int huge *)g_pCurCodecScratch)[i] = 0;
        *(g_pCurCodecScratch + i + 0x2720) = i & 0xff;
    }
    g_wLzwNextCode = 0x101;
    g_wLzwResetWidthPending = 0;
    g_bLzwNeedSeedCode = 1;
    g_bLzwOutputSuspended = 0;
    g_wLzwInBitPos = 0;
    g_wLzwInBufBitsTotal = 0;
    g_pLzwScratchTail = g_pCurCodecScratch + 0x3720;
}

void near lzh_module_unused_stub_a(void) {
}

void near lzh_module_unused_stub_b(void) {
}
