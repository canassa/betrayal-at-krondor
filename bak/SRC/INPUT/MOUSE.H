#ifndef BAK_MOUSE_H
#define BAK_MOUSE_H

#include "structs.h"

extern unsigned short g_mouse_x_mickeys;
extern unsigned short g_mouse_y_mickeys;
extern void far *g_pMouseHandlerCb;
extern unsigned char g_abMouseCbStack[400];
extern unsigned short g_wSavedVgaGcReg0AndIdx;
extern unsigned short g_wSavedVgaGcReg1And4;
extern unsigned short g_wSavedVgaGcReg5And8;
extern unsigned short g_wSavedVgaScReg2AndIdx;
extern unsigned char g_bSavedVgaGcReg3;
extern unsigned char g_bVgaGcReg5ModeA;
extern unsigned char g_bVgaGcReg5Mode8AltA;
extern unsigned char g_bVgaGcReg5ModeB;
extern unsigned char g_bVgaGcReg5Mode8AltB;
extern unsigned char g_mouse_installed;
extern unsigned char g_mouse_buttons;

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
