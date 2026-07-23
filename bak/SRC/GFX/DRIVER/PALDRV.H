#ifndef BAK_PALDRV_H
#define BAK_PALDRV_H

#include "structs.h"
#include "SRC/IO/IO.H"

extern short g_palette_cycle_count;
extern short g_nPaletteScaledIntensity;
extern short g_nPaletteScaledLevel;
extern int g_nCurChunkSize;
extern unsigned short g_awPaletteSizeByAdapter[16];
extern char g_szPalVgaChunkTag[9];
extern char g_szPalEgaChunkTag[9];
extern char g_szPalCgaChunkTag[9];
extern char g_szPalEmptyChunkTag[1];
extern unsigned short g_apszPalChunkTagByAdapter[16];
extern unsigned char far *g_pCurPalette;
extern short g_palette_cycle_end[10];
extern short g_palette_cycle_start[10];
extern short g_palette_cycle_target[10];

extern unsigned char far *chunk_load_into_slot(BakFileRef *file);
extern unsigned char far *palette_set_active(unsigned char far *palette);
extern void cache_release(unsigned char far *buf_farptr);
extern void palette_set_scaled(unsigned int first_color, unsigned int last_color, int target_color, int intensity);
extern int palette_cycle_add(int start, int count, int target);
extern void palette_cycle_tick(void);
extern void near memcpy_inline(unsigned char far *src, unsigned char far *dst, int count);

#endif
