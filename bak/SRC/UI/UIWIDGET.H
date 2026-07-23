#ifndef BAK_UIWIDGET_H
#define BAK_UIWIDGET_H

#include "structs.h"

extern unsigned short g_nSkyHorizonRowCached;
extern unsigned short g_bTexturedPolyEnabled;
extern short g_nGlyphColorShift;
extern ImageRecord **g_tile_sprite;
extern ImageRecord **g_pCompassSpriteSheet;

extern void uiwidget_draw_text_shadowed_dflt(char *text, int shadow_color, int color, int x, int y);
extern void uiwidget_draw_text_shadowed(char *text, int shadow_color, int main_color, int x, int y);
extern int uiwidget_midpoint_int(int a, int b);
extern void uiwidget_panel_draw_3edge_bevel(int x, int y, int width, int height, int fill_color,
                                            int color1, int color2, int color3, int color4);
extern void uiwidget_panel_draw_inset(int x, int y, int width, int height, int color);
extern void uiwidget_tile_sprite_load(void);
extern void uiwidget_tile_sprite_free(void);
extern void uiwidget_panel_inset_inverted(int x, int y, int width, int height, int color_offset);
extern void uiwidget_compass_load(void);
extern void uiwidget_compass_free(void);
extern void uiwidget_compass_draw(void);
extern void uiwidget_draw_beveled_button(int x, int y, int w, int h);

#endif
