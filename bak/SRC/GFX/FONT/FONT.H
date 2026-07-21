#ifndef BAK_FONT_H
#define BAK_FONT_H

#include "structs.h"

extern int font_activate(int slot);
extern int font_get_line_height(int slot);
extern int font_height_get(int slot);
extern int font_slot_in_use(int slot);
extern int font_text_width_ds(char *text);
extern int font_text_pixel_width(char far *str);
extern uint font_draw_char(uchar ch, int x, int y);
extern int font_render_glyph_or_ctrl(char ch, int x, int y);
extern void font_draw_text_ds(char *text, int x, int y);
extern void font_draw_text_far(char far *text, int x, int y);
extern int font_glyph_metrics(int ch, uint *out_width, uint *out_height);

#endif
