#ifndef BAK_ACTMOTN_H
#define BAK_ACTMOTN_H

#include "structs.h"

extern short g_nActorKnockbackColorIdx;
extern short g_nActorSpriteFlip;
extern unsigned short g_nActorShakeX;
extern unsigned short g_nActorShakeY;
extern unsigned short g_bForceOverlay;

extern void *actormotion_xzmalloc(unsigned int size);
extern void actormotion_xzfree(void *ptr);
extern WorldEntity *actormotion_vec_alloc(unsigned short type_tag);
extern unsigned int *actormotion_alloc_24b_bit800(unsigned int tag);
extern void actormotion_integrate(WorldEntity *actor);
extern int actormotion_atan2_long(long y, long x);
extern int actormotion_clamp_signed_delta(int a, int b, int max_abs);

#endif
