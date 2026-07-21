/**
 * @file  ACTORREC.H
 * @brief Accessors for the variable-length @ref Actor record: locate an optional
 *        subrecord, and measure the record's variable payload.
 */
#ifndef BAK_ACTORREC_H
#define BAK_ACTORREC_H

#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"

/**
 * @brief Locate an actor's optional subrecord of a given kind.
 *
 * Actor records are variable-length: the item array is followed by the optional
 * subrecords selected by @ref Actor::flags. This returns the in-record address of
 * the requested one, or reports it absent.
 *
 * @param actor           Actor record to search; must be non-NULL.
 * @param which_subrecord A single presence bit from @ref SUBREC_MASK (e.g.
 *                        @ref SUBREC_EVENT_STATE) naming the desired subrecord.
 * @return Far pointer to the @ref ActorSubrecord, or NULL when @p actor does not
 *         carry it (the @p which_subrecord bit is clear in @ref Actor::flags).
 * @retval NULL The requested subrecord is not present.
 */
extern ActorSubrecord far *actorrec_get_subrecord(Actor far *actor, int which_subrecord);

/**
 * @brief Byte size of an actor record's variable payload, excluding the fixed
 *        @ref Actor header.
 *
 * Sums the item array (@ref Actor::itemCapacity slots of @ref ItemSlot) and every
 * subrecord whose bit is set in @ref Actor::flags. Callers add the header size to
 * get the whole record — allocating or persisting one takes
 * `actorrec_payload_size(actor) + sizeof(Actor)` bytes.
 *
 * @param actor Actor record to measure; must be non-NULL.
 * @return Payload size in bytes (item array + present subrecords), header excluded.
 */
extern int actorrec_payload_size(Actor far *actor);

#endif
