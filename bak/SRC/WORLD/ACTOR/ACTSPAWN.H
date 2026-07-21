#ifndef BAK_ACTSPAWN_H
#define BAK_ACTSPAWN_H

#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"

extern Actor far *actorspawn_enc_location(int kind, long world_x, long world_y);
extern Actor far *actorspawn_objfixed(int kind, long world_x, long world_y);
extern void actorspawn_destroy_and_persist(Actor far *actor);
extern void actorspawn_persist_to_temp(Actor far *actor);
extern void actorspawn_npc_prox_periodic(Actor far *actor);
extern int actorspawn_for_location_by_time(int location_id);
extern long actorspawn_location_lookup(int location_id);

#endif
