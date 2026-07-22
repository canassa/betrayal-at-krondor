#ifndef BAK_JOYSTICK_H
#define BAK_JOYSTICK_H

#include "structs.h"

extern void near gameport_read_axis();
extern int near joystick_normalize_axis(void);
extern int joystick_init(void);
extern void joystick_read_position(int which, int *out_x, int *out_y);
extern unsigned char joystick_read_direction(int which);
extern int joystick_button_pressed(int button);
extern void joystick_poll_axis(int axis);

#endif
