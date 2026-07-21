#ifndef BAK_ACTMOTN_H
#define BAK_ACTMOTN_H

#include "structs.h"

extern void *actormotion_xzmalloc(uint size);
extern void actormotion_xzfree(void *ptr);
extern WorldEntity *actormotion_vec_alloc(ushort type_tag);
extern uint *actormotion_alloc_24b_bit800(uint tag);
extern void actormotion_integrate(WorldEntity *actor);
extern int actormotion_atan2_long(long y, long x);
extern int actormotion_clamp_signed_delta(int a, int b, int max_abs);

#endif
