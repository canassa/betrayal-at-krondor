#ifndef BAK_TIMERPL_H
#define BAK_TIMERPL_H

#include "structs.h"

extern TimerEventEntry *timerpool_upsert(unsigned short kind, unsigned short sub_id, unsigned short mode, long value);
extern void timerpool_tick(int delta_ticks);
extern int timerpool_contains(unsigned short kind, unsigned short sub_id);

#endif
