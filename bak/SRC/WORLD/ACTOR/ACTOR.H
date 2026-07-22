/**
 * @file  ACTOR.H
 * @brief The Actor record and its subrecord family, owned by the WORLD/ACTOR
 *        module (see ACTORREC.C for the record format, ACTSPAWN.C for the
 *        lifecycle). Owns the whole family; consumers include this header
 *        directly (structs.h no longer carries these types).
 */
#ifndef BAK_ACTOR_H
#define BAK_ACTOR_H

#include "structs.h"

enum ActorResidence {
    RES_FREE = 0,
    RES_PARTY_SLOT = 1,
    RES_ENCOUNTER = 2,
    RES_CONTAINER = 4,
    RES_BODY = 5,
    RES_FIXED_OBJECT = 6,
    RES_COMBAT = 7,
    RES_PICKLOCK_BUFFER = 8,
    RES_SELF_SPAWN = 9,
};
typedef enum ActorResidence ActorResidence;

typedef struct PartySlotCoords {
    unsigned short wSlot_id;
    unsigned char pPad[6];
} PartySlotCoords;

typedef struct CombatLocCoords {
    long nCombat_idx;
    long nCombatant_idx;
} CombatLocCoords;

typedef union ContainerLocation {
    WorldPos2 world;
    PartySlotCoords party_slot;
    CombatLocCoords combat;
} ContainerLocation;

typedef struct Actor {
    /**
     * Dirty bit: the actor was mutated in RAM and must be written back to
     * its temp-file slot; set on any change, cleared once the write
     * completes. Flushed only when @ref Actor::canFlush is also set.
     */
    unsigned char needsFlush;
    /**
     * The actor has a temp-file slot to be written back to, so it may be
     * persisted; gates the flush together with @ref Actor::needsFlush. It
     * is not a type discriminant; the record's kind is @ref Actor::kind.
     */
    unsigned char canFlush;
    unsigned char temp_file_off[4];
    unsigned char kind;
    unsigned char chap_band;
    unsigned short world_item_id;
    ContainerLocation loc;
    ActorResidence bResidence;
    /** Item slots currently filled; mutable fill count, bounds every inventory loop, and equals @ref Actor::itemCapacity when full. */
    unsigned char itemCount;
    /** Total @ref ItemSlot slots in the inventory; immutable, sizes the record and fixes where the subrecords begin. */
    unsigned char itemCapacity;
    /**
     * @brief Bitfield: which optional subrecords follow, plus mutable actor state.
     *
     * Two concerns share one byte. The low six bits (@ref SUBREC_MASK) form a
     * presence mask selecting which optional subrecords follow the item array
     * (see @ref ActorSubrecord); they fix the record's size and layout and are
     * immutable once the record is authored. The high two bits are mutable
     * runtime state: @ref ACTOR_HOLDS_WEAPON and @ref ACTOR_SELF_SPAWN.
     */
    unsigned char flags;
} Actor;

/**
 * @name Actor::flags bits
 *
 * Bit layout of @ref Actor::flags. The low six bits (@ref SUBREC_MASK) select
 * which optional subrecords follow the record's item array, in ascending bit
 * order, and so determine its size; they are fixed when the record is authored.
 * The high two bits are mutable runtime state.
 * @{
 */

/** 0x01: a 4-byte @ref ActorSubrec01_Params subrecord follows. */
#define SUBREC_PARAMS 0x01
/** 0x02: a 6-byte @ref ActorSubrec02_InteractMsg subrecord follows. */
#define SUBREC_INTERACT_MSG 0x02
/** 0x04: a 16-byte @ref ActorSubrec04_EventState subrecord follows. */
#define SUBREC_EVENT_STATE 0x04
/** 0x08: a 9-byte @ref ActorSubrec08_HotspotAction subrecord follows. */
#define SUBREC_HOTSPOT 0x08
/** 0x10: a 4-byte @ref ActorSubrec10_LastTouch subrecord follows. */
#define SUBREC_LAST_TOUCH 0x10
/** 0x20: a 2-byte @ref ActorSubrec20_DoorVariant subrecord follows. */
#define SUBREC_DOOR_VARIANT 0x20
/** 0x3f: mask of the six subrecord-presence bits, @ref SUBREC_PARAMS through @ref SUBREC_DOOR_VARIANT. */
#define SUBREC_MASK 0x3f

/**
 * @brief 0x40: cached flag — this actor's item array holds a weapon.
 *
 * Recomputed from inventory whenever items are dropped into a world container;
 * shields a dropped pile from world object-decay and from encounter-slot
 * recycling. Unlike the @ref SUBREC_MASK bits it is mutable at runtime.
 */
#define ACTOR_HOLDS_WEAPON 0x40

/**
 * @brief 0x80: encounter-pool member.
 *
 * Marks an actor the engine spawns into the world without a .WLD placement and
 * whose slot is recycled once emptied. Mutable runtime state, set independently
 * of the @ref SUBREC_MASK layout bits.
 */
#define ACTOR_SELF_SPAWN 0x80

/** @} */

/**
 * @brief Far pointer to the base of an actor's inventory item array.
 *
 * The @ref ItemSlot array immediately follows the @ref Actor header and holds
 * @ref Actor::itemCapacity slots; the optional subrecords selected by
 * @ref Actor::flags follow the array.
 *
 * @param a Far pointer to the @ref Actor record.
 */
#define ACTOR_ITEMS(a) ((ItemSlot far *)((char far *)(a) + sizeof(Actor)))

/**
 * @brief L-value of item slot @p i in actor @p a's inventory array.
 * @param a Far pointer to the @ref Actor record.
 * @param i Slot index, 0 .. @ref Actor::itemCapacity - 1 (not bounds-checked).
 */
#define ACTOR_ITEM(a, i) (ACTOR_ITEMS(a)[i])

typedef struct ActorSubrec01_Cipher {
    unsigned char b_pad0;
    unsigned char b_pad1;
    unsigned char bCipher_puzzle_id;
    unsigned char b_pad3;
} ActorSubrec01_Cipher;

typedef struct ActorSubrec01_DoorKey {
    unsigned char b_pad0;
    unsigned char bLookup_key;
    unsigned char b_pad2;
    unsigned char b_pad3;
} ActorSubrec01_DoorKey;

typedef struct ActorSubrec01_Proximity {
    unsigned char bFlags;
    unsigned char bIntensity;
    unsigned char bHundred_flag;
    unsigned char b_pad3;
} ActorSubrec01_Proximity;

typedef struct ActorSubrec02_InteractMsg {
    unsigned char bKind_or_id;
    unsigned char bFlags;
    unsigned long dwMessage_id;
} ActorSubrec02_InteractMsg;

typedef struct ActorSubrec04_EventState {
    unsigned char bArg0;
    unsigned char bArg1;
    unsigned char bArg2;
    unsigned char bArg3;
    unsigned char bTemple_filter;
    unsigned char bTeleport_cost_msb;
    unsigned char b_pad06;
    unsigned char bPopup_retry_counter;
    unsigned char bRest_gold_unit;
    unsigned char bRest_last_chapter_done;
    unsigned char bRest_target_hour;
    unsigned char bRest_gold_cost;
    unsigned char bInvreq_arg_x;
    unsigned char bInvreq_arg_y;
    unsigned short wShop_disposition_flags;
} ActorSubrec04_EventState;

typedef struct ActorSubrec08_HotspotAction {
    unsigned short wPad_0;
    unsigned short wGame_state_event_id;
    unsigned char bWarp_kind;
    unsigned char bWarp_dest;
    unsigned char bHas_hotspot;
    unsigned char bHotspot_x;
    unsigned char bHotspot_y;
} ActorSubrec08_HotspotAction;

typedef struct ActorSubrec10_LastTouch {
    unsigned long dwLast_touch_time;
} ActorSubrec10_LastTouch;

typedef struct ActorSubrec20_DoorVariant {
    short nDoor_variant;
} ActorSubrec20_DoorVariant;

typedef union ActorSubrec01_Params {
    ActorSubrec01_Cipher cipher;
    ActorSubrec01_DoorKey door_or_npc_key;
    ActorSubrec01_Proximity proximity;
} ActorSubrec01_Params;

typedef union ActorSubrecord {
    ActorSubrec01_Params params;
    ActorSubrec02_InteractMsg interact_msg;
    ActorSubrec04_EventState event_state;
    ActorSubrec08_HotspotAction hotspot_action;
    ActorSubrec10_LastTouch last_touch;
    ActorSubrec20_DoorVariant door_variant;
} ActorSubrecord;

#endif
