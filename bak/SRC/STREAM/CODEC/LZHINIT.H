#ifndef BAK_LZHINIT_H
#define BAK_LZHINIT_H

#include "structs.h"

extern unsigned short g_wLzwCodeBits;
extern unsigned short g_wLzwMaxCode;
extern unsigned short g_wLzwNextCode;
extern unsigned short g_wLzwResetWidthPending;
extern unsigned short g_wLzwLastByte;
extern unsigned short g_wLzwPrevCode;
extern unsigned short g_wLzwNewCode;
extern unsigned char far *g_pLzwScratchTail;
extern unsigned short g_wLzwInBitPos;
extern unsigned short g_wLzwInBufBitsTotal;
extern unsigned char g_bLzwNeedSeedCode;
extern unsigned char g_bLzwOutputSuspended;

extern void near lzh_decoder_init(void);
extern void near lzh_module_unused_stub_a(void);
extern void near lzh_module_unused_stub_b(void);

#endif
