#include "globals.h"
#include "SRC/SYS/SYSLOWIO.H"

/* DGROUP+0x15a..0x15d: a stray "\n"-shaped byte pair (0a 00) + a zero byte,
 * then the busy-cursor flag.  The flag's referencers (SCREEN.C, BOOT.C) link
 * far too late to define it at this address, so the 1993 definer is one of
 * the modules in the MEM.OBJ -> RAND.OBJ link window (SYSLOWIO is the first
 * slot); no code anywhere references the three lead bytes.  Parked here until
 * evidence names the owner. */
unsigned char _dgroup_lead_15a[3] = {0x0a, 0x00, 0x00};
char g_cBusyCursorShown = 0;

unsigned long g_timer_ticks;
unsigned long g_dwSysTickCount;

void syslowio_timer_tick_isr(void) {
    g_timer_ticks++;
    g_dwSysTickCount++;
}

void syslowio_mouse_handler_cb_noop(void) {
    return;
}
