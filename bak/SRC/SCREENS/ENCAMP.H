#ifndef BAK_ENCAMP_H
#define BAK_ENCAMP_H

#include "structs.h"

extern unsigned short *g_pEncampBmpAssetTable;
extern unsigned short *g_pEncampHotspotX;
extern unsigned short *g_pEncampHotspotY;
extern unsigned short *g_pClockHandVertsX;
extern unsigned short *g_pClockHandVertsY;
extern unsigned char *g_pEncampPaletteRemapLut;
extern char *g_apszEncampStatColHeaders[2];
extern char *g_pszHpSeparator;
extern unsigned short g_anEncampStatColX[2];
extern unsigned short g_wEncampHotspotSubW;
extern unsigned short g_wEncampHotspotSubH;
extern unsigned short g_wEncampHotspotBoxW;
extern unsigned short g_wEncampHotspotBoxH;
extern unsigned short g_wEncampHotspotCount;
extern unsigned short g_wEncampClockVertexCount;

extern void encamp_run(void);
extern void encamp_load(void);
extern void encamp_teardown(void);
extern void encamp_restore_screen_background(void);
extern void encamp_proj_trail_emit_facing(int a, int b, int c, unsigned int d, unsigned int e, unsigned int f);
extern int encamp_hotspot_at_cursor(void);
extern void encamp_build_palette_remap_lut(void);
extern void encamp_free_buffer(void);
extern unsigned int encamp_palette_nearest_color(unsigned char far *palette_ptr, int bias);
extern void encamp_draw_clock_hand(unsigned int time_in_period);
extern void encamp_draw_party_stats(void);

#endif
