/**
 * @file  ACTORREC.C
 * @brief Implements @ref actorrec_get_subrecord and @ref actorrec_payload_size,
 *        the accessors for the variable-length @ref Actor record.
 */
#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTORREC.H"

ActorSubrecord far *actorrec_get_subrecord(Actor far *actor, int which_subrecord) {
    unsigned char mask;
    ActorSubrecord far *p;

    mask = actor->flags;
    if (!(which_subrecord & mask))
        goto L_null;

    p = (ActorSubrecord far *)(ACTOR_ITEMS(actor) + actor->itemCapacity);

    if (mask & SUBREC_PARAMS) {
        if (which_subrecord & SUBREC_PARAMS)
            return p;
        *(unsigned *)&p += sizeof(ActorSubrec01_Params);
    }
    if (mask & SUBREC_INTERACT_MSG) {
        if (which_subrecord & SUBREC_INTERACT_MSG)
            return p;
        *(unsigned *)&p += sizeof(ActorSubrec02_InteractMsg);
    }
    if (mask & SUBREC_EVENT_STATE) {
        if (which_subrecord & SUBREC_EVENT_STATE)
            return p;
        *(unsigned *)&p += sizeof(ActorSubrec04_EventState);
    }
    if (mask & SUBREC_HOTSPOT) {
        if (which_subrecord & SUBREC_HOTSPOT)
            return p;
        *(unsigned *)&p += sizeof(ActorSubrec08_HotspotAction);
    }
    if (mask & SUBREC_LAST_TOUCH) {
        if (which_subrecord & SUBREC_LAST_TOUCH)
            return p;
        *(unsigned *)&p += sizeof(ActorSubrec10_LastTouch);
    }
    if (mask & SUBREC_DOOR_VARIANT) {
        if (which_subrecord & SUBREC_DOOR_VARIANT)
            return p;
    }

L_null:
    return NULL;
}

int actorrec_payload_size(Actor far *actor) {
    int size;

    size = actor->itemCapacity * sizeof(ItemSlot);
    if ((actor->flags & SUBREC_PARAMS) != 0) {
        size = size + sizeof(ActorSubrec01_Params);
    }
    if ((actor->flags & SUBREC_INTERACT_MSG) != 0) {
        size = size + sizeof(ActorSubrec02_InteractMsg);
    }
    if ((actor->flags & SUBREC_EVENT_STATE) != 0) {
        size = size + sizeof(ActorSubrec04_EventState);
    }
    if ((actor->flags & SUBREC_HOTSPOT) != 0) {
        size = size + sizeof(ActorSubrec08_HotspotAction);
    }
    if ((actor->flags & SUBREC_LAST_TOUCH) != 0) {
        size = size + sizeof(ActorSubrec10_LastTouch);
    }
    if ((actor->flags & SUBREC_DOOR_VARIANT) != 0) {
        size = size + sizeof(ActorSubrec20_DoorVariant);
    }
    return size;
}
