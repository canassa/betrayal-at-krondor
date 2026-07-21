#include "globals.h"
#include "structs.h"
#include "SRC/R3D/VIS/VISENTRY.H"
#include "SRC/R3D/ACTOR/ACTRENDR.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"

void far visentry_mark_dollar_flag14(VisibleEntryList *list) {
    WorldObject far *entry;
    unsigned short state;
    int i;
    int count;

    entry = list->pEntries;
    count = list->wEntry_count;
    i = 0;
    if (i < count) {
        do {
            if (ts_get_shape(entry->shapeId)->kind == 0x24) {
                state = 1;
                entry->state.stateBits = state;
            }
            i++;
            entry++;
        } while (i < count);
    }
    return;
}

void far visentry_render_actor_tmp_anim(WorldObject far *entry) {
    unsigned short savedState;
    unsigned char stateLow;

    savedState = entry->state.stateBits;
    stateLow = savedState & 0xff;
    g_render_actor_wstate_scratch[0] = 0;
    g_render_actor_wstate_scratch[1] = stateLow;
    entry->state.stateBits = (unsigned short)g_render_actor_wstate_scratch;
    actorrender_entity(entry);
    entry->state.stateBits = savedState;
    return;
}
