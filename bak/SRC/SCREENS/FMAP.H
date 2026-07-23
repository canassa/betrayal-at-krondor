#ifndef BAK_FMAP_H
#define BAK_FMAP_H

#include "structs.h"

extern ImageRecord **g_pFmapIconTable;
extern unsigned short *g_pFmapTownXCoords;
extern unsigned short *g_pFmapTownYCoords;
extern unsigned short *g_pFmapTownLabels;
extern unsigned short g_wFmapMapWidth;
extern unsigned short g_wFmapMapHeight;
extern unsigned short g_wFmapHotspotW;
extern unsigned short g_wFmapHotspotH;
extern unsigned short g_wFmapTownCount;
extern unsigned short g_wFmapLabelRectW;
extern unsigned short g_wFmapLabelRectH;
extern unsigned char far *g_pFmapLabelRectBuf;

extern void fmap_screen_run(void);
extern void fmap_twn_load(void);
extern void fmap_hotspots_unload(void);
extern int fmap_hit_test_cursor(void);
extern int fmap_xy_lookup_for_chapter(int *out_x, int *out_y);
extern int fmap_farptr_normalize(unsigned int *pHeading);

#endif
