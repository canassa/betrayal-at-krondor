#ifndef BAK_TIMER_H
#define BAK_TIMER_H

#include "structs.h"

extern int registry_slot_alloc(FARFN callback, int interval);
extern int registry_slot_free(int slot);
extern void timer_install(unsigned int frequency);
extern int timer_restore_default(void);
extern void timer_irq0_dispatch(void);

#endif
