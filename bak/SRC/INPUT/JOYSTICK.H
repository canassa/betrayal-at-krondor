#ifndef BAK_JOYSTICK_H
#define BAK_JOYSTICK_H

#include "structs.h"

extern unsigned char g_bJoystick0Installed;
extern unsigned char g_bJoystick1Installed;
extern unsigned char g_bJoyAxisTimeoutMask;
extern unsigned short g_nJoy0CenterX;
extern unsigned short g_nJoy0CenterY;
extern unsigned short g_nJoy1CenterX;
extern unsigned short g_nJoy1CenterY;
extern unsigned short g_nJoy0SensX;
extern unsigned short g_nJoy0SensY;
extern unsigned short g_nJoy1SensX;
extern unsigned short g_nJoy1SensY;
extern unsigned short g_nJoyReadScratchX;
extern unsigned short g_nJoyLoopDelay;
extern short g_nJoyDirScratchX;
extern short g_nJoyDirScratchY;

extern void near gameport_read_axis();
extern int near joystick_normalize_axis(void);
extern int joystick_init(void);
extern void joystick_read_position(int which, int *out_x, int *out_y);
extern unsigned char joystick_read_direction(int which);
extern int joystick_button_pressed(int button);
extern void joystick_poll_axis(int axis);

#endif
