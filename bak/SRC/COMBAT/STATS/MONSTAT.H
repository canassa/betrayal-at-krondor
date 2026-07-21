#ifndef BAK_MONSTAT_H
#define BAK_MONSTAT_H

#include "structs.h"

extern int monstat_roll_stat_in_range(CombatActor *actor, int max_val, int min_val, int stat_index);
extern void monstat_roll_stats_from_file(CombatActor *actor);

#endif
