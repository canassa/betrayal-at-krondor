#include "structs.h"
#include "SRC/STREAM/CODEC/CODEC.H"
#include "SRC/STREAM/CODEC/LZHUF.H"
#include "SRC/STREAM/CODEC/LZHOPEN.H"
#include "SRC/SYS/DOSMEM.H"

int near lzss_alloc_codec_buffers(void) {
    g_wLzhEncInitialized = 0;
    g_lzhPutBuf = 0;
    g_lzhPutLen = '\0';

    g_pLzssLson = (unsigned short far *)alloc_far(0x2002UL, 0L);
    g_pLzssRson = (unsigned short far *)alloc_far(0x2202UL, 0L);
    g_pLzssDad = (unsigned short far *)alloc_far(0x2002UL, 0L);
    *(unsigned long *)&g_pLzssTextBuf = *(unsigned long *)&g_pCurStreamDesc->pScratch;
    return 0;
}

int near lzh_stream_open(void) {
    g_wLzhDecInitialized = 0;
    g_lzh_bit_buf = 0;
    g_lzh_bit_count = '\0';
    *(unsigned long *)&g_pLzssTextBuf = *(unsigned long *)&g_pCurStreamDesc->pScratch;
    return 0;
}
