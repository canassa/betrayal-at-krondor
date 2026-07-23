#ifndef BAK_FONT_H
#define BAK_FONT_H

#include "structs.h"

extern unsigned char g_abFontColorRemap[5];
extern unsigned char g_saved_text_fg_color;
extern RendererVtable g_renderer_vtable;
extern unsigned char g_font_underline_offset[20];
extern int far *g_font_glyph_offset_table[20];
extern unsigned char far *g_font_width_table[20];
extern unsigned char far *g_font_bitmap_data[20];
extern unsigned char g_font_format[20];

extern int font_activate(int slot);
extern int font_get_line_height(int slot);
extern int font_height_get(int slot);
extern int font_slot_in_use(int slot);
extern int font_text_width_ds(char *text);
extern int font_text_pixel_width(char far *str);
extern unsigned int font_draw_char(unsigned char ch, int x, int y);
extern int font_render_glyph_or_ctrl(char ch, int x, int y);
extern void font_draw_text_ds(char *text, int x, int y);
extern void font_draw_text_far(char far *text, int x, int y);
extern int font_glyph_metrics(int ch, unsigned int *out_width, unsigned int *out_height);

#endif
