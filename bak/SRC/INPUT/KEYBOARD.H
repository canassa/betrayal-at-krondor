#ifndef BAK_KEYBOARD_H
#define BAK_KEYBOARD_H

#include "structs.h"

extern int keyboard_install(int install_timer_int);
extern unsigned char keyboard_restore_handler(void);
extern void isr_keyboard(void);
extern void near input_axis_accumulate_isr(void);
extern uint kbhit_read(void);
extern int key_state_get_via_2cf8_table(int mode);
extern int key_is_down(int scancode);

#endif
