#ifndef BAK_RNDVTBL_H
#define BAK_RNDVTBL_H

#include "structs.h"

extern RendererVtable g_renderer_vtable;
extern Slot01Fn far *g_pfn_blit_glyph_row;
extern void(far *g_pfn_blit_stretched)(void);

#endif
