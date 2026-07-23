#ifndef BAK_SYSLOWIO_H
#define BAK_SYSLOWIO_H

#include "structs.h"

extern char g_cBusyCursorShown;
extern unsigned long g_timer_ticks;
extern unsigned long g_dwSysTickCount;

extern void syslowio_timer_tick_isr(void);
extern void syslowio_mouse_handler_cb_noop(void);

#endif
