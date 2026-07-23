#ifndef BAK_TIMER_H
#define BAK_TIMER_H

#include "structs.h"

extern char g_timer_installed;
extern int g_nFrameTickCountdown;
extern unsigned short g_nTimerPitDivisor;
extern unsigned short g_nTimerBiosChainReload;
extern unsigned short g_nTimerBiosChainCountdown;
extern unsigned short g_registry_slot_mask;
extern TimerCallback g_aTimerCallback[16];
extern TimerSched g_aTimerSched[16];

extern int registry_slot_alloc(FARFN callback, int interval);
extern int registry_slot_free(int slot);
extern void timer_install(unsigned int frequency);
extern int timer_restore_default(void);
extern void timer_irq0_dispatch(void);

#endif
