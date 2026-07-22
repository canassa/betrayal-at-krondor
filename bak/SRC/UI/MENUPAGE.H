#ifndef BAK_MENUPAGE_H
#define BAK_MENUPAGE_H

#include "structs.h"

extern MenuPage *menupage_load(char *filename);
extern void menupage_free(MenuPage *page);
extern void menupage_begin(MenuPage *page);
extern void menupage_end(MenuPage *page);
extern void menupage_draw(MenuPage *page);
extern void menupage_draw_entries(MenuEntry *first, int count, int x, int y);
extern void menupage_cur_set_pos_clamped(int x, int y);
extern void menupage_cursor_joystick_step(void);
extern void menupage_navigate(MenuPage *page, int dx_sign, int dy_sign, int tab_mode);
extern int menupage_run(MenuPage *page, unsigned short *out_consumed);
extern int menupage_input_poll(MenuPage *page, unsigned short *out_consumed);
extern MenuEntry *menupage_state_0e84(void);
extern MenuEntry *menupage_focused_entry(void);
extern MenuEntry *menupage_state_0e80(void);
extern unsigned int menupage_highlight_color(void);
extern unsigned int menupage_state_0e7c(void);
extern unsigned int menupage_input_poll_key(void);

#endif
