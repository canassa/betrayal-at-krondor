#ifndef GFX169D_H
#define GFX169D_H

extern unsigned char far g_abCursorPaletteLut[256];

extern unsigned char far g_abFogRemapTable[2560];

#ifdef V102CD
#define FOG_REMAP_TAB_OFF 0x66
#define CURSOR_REMAP_TAB_OFF 0xa66
#else
#define FOG_REMAP_TAB_OFF 0x5c
#define CURSOR_REMAP_TAB_OFF 0xa5c
#endif

#endif
