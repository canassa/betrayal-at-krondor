#ifndef BAK_ROTBLIT_H
#define BAK_ROTBLIT_H

#include "structs.h"

extern void far *g_pRotBlitDispatchFp;
extern short g_anRotBlitVertX[4];
extern short g_anRotBlitVertY[4];
extern unsigned short g_wRotBlitIdxTop;
extern unsigned short g_wRotBlitIdxBottom;
extern unsigned short g_wRotBlitIdxNextCW;
extern unsigned short g_wRotBlitIdxOppCW;
extern void *g_pRotBlitStep1Fp;
extern void *g_apRotBlitStep1FpTable[4];
extern void *g_pRotBlitStep2Fp;
extern void *g_apRotBlitStep2FpTable[4];
extern void *g_pRotBlitStep3Fp;
extern void *g_apRotBlitStep3FpTable[4];
extern void *g_pRotBlitStep4Fp;
extern void *g_apRotBlitStep4FpTable[4];
extern short g_aStretchYSrcTable[400];
extern short g_aStretchXSrcTable[640];

extern void near stretch_walk_x_clipped(int *out_xs, int x_start, int count, int x_step, int span);
extern void vga_reset_gc_default_thunk(void);
extern void jmp_via_2f48(unsigned char *sprite, int x, int y, int angle, int dx, int dy, int flag1,
                         int flag2);
extern void read_4words_from_2tables(unsigned short *a, unsigned short *b, unsigned short *c, unsigned short *d);

#endif
