#ifndef BAK_VGABLIT_H
#define BAK_VGABLIT_H

#include "structs.h"

extern void vga_planar_fill_rects(void);
extern void vgablit_planar_runs(void);
extern void vgablit_span_emit_textured(void);
extern void vgablit_planar_runs_untiled();

#endif
