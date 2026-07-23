#ifndef BAK_WIDGET_H
#define BAK_WIDGET_H

#include "structs.h"

extern ImageRecord **g_pButtonSpriteUp;
extern ImageRecord **g_pBtnSpriteDownSheet;
extern short g_nScrollTrackOffset;
extern unsigned char g_saved_clip_enabled;
extern unsigned short g_saved_clip_ymax;
extern unsigned short g_saved_clip_xmin;
extern unsigned short g_saved_clip_xmax;
extern unsigned short g_saved_clip_ymin;

extern void widget_load_button_sprite_pair(char *filename);
extern void widget_free_button_sprite_pair(void);
extern void widget_blit_button_sprite(unsigned int sprite_idx, int x, int y, int palette, int center,
                                      int rect_w, int rect_h);
extern int widget_hit_test(MenuEntry *widget, int x, int y, int *out_region);
extern void widget_dispatch_by_type(MenuEntry *widget, int x, int y, int hover_flag);
extern void widget_toggle_state(MenuEntry *widget);
extern void widget_list_scroll(MenuEntry *widget, int dir);
extern void widget_scrollbar_update(MenuEntry *widget);
extern void widget_menu_draw(MenuEntry *widget, int x, int y, int hover_flag);
extern void widget_button_render_full(MenuEntry *button, int x, int y, int pressed, int sprite_set);
extern void widget_draw_text_button(MenuEntry *widget, int x, int y, int pressed);
extern void widget_draw_iconbox(MenuEntry *widget, int x, int y, int pressed, int sprite_flags);
extern void widget_draw_scrollbar(MenuEntry *widget, int x, int y, int pressed_part);
extern void widget_render_button(MenuEntry *widget, int x_off, int y_off, int hover_flag);
extern void widget_push_clip_rect(short xmin, short ymin, short xmax, short ymax);
extern void widget_pop_clip_rect(void);

#endif
