#ifndef BAK_TIMERPL_H
#define BAK_TIMERPL_H

#include "structs.h"

extern TimerEventEntry *timerpool_upsert(ushort kind, ushort sub_id, ushort mode, long value);
extern void timerpool_tick(int delta_ticks);
extern int timerpool_contains(ushort kind, ushort sub_id);

#endif
