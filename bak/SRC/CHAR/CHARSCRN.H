#ifndef BAK_CHARSCRN_H
#define BAK_CHARSCRN_H

#include "structs.h"

extern void charscreen_info_loop(CombatActor *actor);
extern void charscreen_recalc_condition_tick(void);
extern void charscreen_temple_heal_menu(int actor_filter, int mode);

#endif
