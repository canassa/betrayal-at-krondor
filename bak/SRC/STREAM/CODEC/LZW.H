#ifndef BAK_LZW_H
#define BAK_LZW_H

#include "structs.h"

extern unsigned short g_nLzwTableSize;
extern unsigned short g_nLzwNextFreeCode;
extern unsigned short g_nLzwMode;
extern unsigned short g_bLzwClearPending;
extern long g_lLzwBestRatio;
extern long g_lLzwRatioThresh;
extern long g_lLzwInputCount;
extern long g_lLzwOutputCount;
extern unsigned char g_lzwHiMask[9];
extern unsigned char g_lzwLoMask[9];
extern unsigned short g_wLzwEncCodeBits;
extern unsigned short g_wLzwEncMaxCode;
extern unsigned short g_wLzwOutBitPos;
extern long g_lLzwOutByteCount;
extern unsigned char g_bLzwEncSeedPending;
extern unsigned short g_wLzwEncCurCode;
extern unsigned char g_lzwEncOutBuf[12];

extern int near lzw_reset_state(void);
extern int near lzw_decompressor_init(void);
extern int near lzw_compress_input(int flush);
extern void near lzw_emit_code(int code);
extern long thunk_LDIV_at(long numer, long denom);
extern void near lzw_check_ratio(void);
extern void near lzw_clear_code_table(long count);

#endif
