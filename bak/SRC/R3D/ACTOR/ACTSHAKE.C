#include "SRC/R3D/ACTOR/ACTOROVL.H"
#include "structs.h"
#include "SRC/R3D/ACTOR/ACTSHAKE.H"
#include "SRC/SYS/RAND.H"
#include "SRC/R3D/ACTOR/ACTRENDR.H"

void far render_actor_with_shake(WorldObject far *visible_entry) {
    unsigned short savedState;

    if (g_bShakeActorEnabled != 0) {
        savedState = visible_entry->state.stateBits;
        g_bShakeJitterX = RND2(4);
        g_bShakeJitterY = RND(5);
        visible_entry->state.stateBits = (unsigned short)((unsigned char near *)&g_bShakeJitterX);
        actorrender_entity(visible_entry);
        visible_entry->state.stateBits = savedState;
        return;
    }
    actorrender_entity(visible_entry);
    return;
}
