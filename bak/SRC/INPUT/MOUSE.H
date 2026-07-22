#ifndef BAK_MOUSE_H
#define BAK_MOUSE_H

#include "structs.h"

extern int mouse_install(void);
extern void mouse_set_cursor_clip_rect(int x, int y, int w, int h);
extern void mouse_set_handler_cb(void far *cb);
extern void mouse_event_callback(void);
extern void vga_save_and_setup_gc_sc(void);
extern void vga_restore_registers(void);
extern int mouse_restore_handler(void);
extern unsigned int mouse_get_position(unsigned int *out_x, unsigned int *out_y);
extern int mouse_set_position(int x, int y);
extern int mouse_button_pressed(int button);

#endif
