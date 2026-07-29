#ifndef BAK_WORLDDOR_H
#define BAK_WORLDDOR_H

#include "structs.h"

extern void worlddoor_pref_slots_clear_all(void);
extern void worlddoor_load_door_records(VisibleEntryList *list);
extern void worlddoor_rndr_enc_mark_actor(WorldObject far *entry);

#endif
