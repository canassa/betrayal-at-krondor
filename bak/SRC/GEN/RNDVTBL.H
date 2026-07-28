#ifndef BAK_RNDVTBL_H
#define BAK_RNDVTBL_H

#include "structs.h"

extern RendererVtable g_renderer_vtable;
extern Slot01Fn far *g_pfn_blit_glyph_row;
extern void(far *g_pfn_blit_stretched)(void);
extern void(far *g_pfn_fill_run_a)(void);
extern void(far *g_pfn_blit_sprite_chunky_flip)(void);

#endif
