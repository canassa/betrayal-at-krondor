/**
 * @file    GSTATE.H
 * @brief   Persistent game state: event flags, timekeeping, party helpers,
 *          and the `TEMP.GAM` swap-file accessors.
 */
#ifndef BAK_GSTATE_H
#define BAK_GSTATE_H

#include "structs.h"
#include "SRC/IO/RESOURCE.H"
#include "SRC/GAME/GMAIN.H"

/**
 * @brief Save-region selector for the 1.02 write-region bounds guard in
 * @ref gstate_temp_file_write_at: a caller arms the `TEMP.GAM` region its next
 * write may touch, and a write straying outside it is dropped. @ref TWR_NONE
 * (default and post-write) leaves the write unchecked.
 */
typedef enum TempWriteRegion {
    TWR_NONE               = -1, /**< Unarmed; the write is not bounds-checked. */
    TWR_GAMESTATE          = 0,  /**< The live game-state header. */
    TWR_ENCOUNTER_STATE    = 1,  /**< Mutable encounter/world state: triggers,
                                      rosters, times, moved objects, gold. */
    TWR_COMBAT_ACTOR       = 2,  /**< Scripted combatants' persistent stat sheets. */
    TWR_COMBAT_ACTOR_INNER = 3,  /**< Each combatant's tactical/positional state. */
    TWR_ACTOR_POOL         = 4   /**< Persistent world-object records. */
} TempWriteRegion;

/**
 * @brief The live pending-region latch: the @ref TempWriteRegion the next
 * `TEMP.GAM` write is allowed to touch, or @ref TWR_NONE when disarmed.
 */
extern TempWriteRegion g_pendingTempWriteRegion;


extern char g_abChapterEventSlot[9];

/**
 * @brief Open @ref ResFile token for `TEMP.GAM`, the on-disk game-state
 *        swap image.
 *
 * NULL whenever the file is closed (outside the world loop).
 */
extern ResFile *g_tempGamFP;


extern char g_abSleepStatDelta[6];
extern char g_abRegenPerChar[6];

extern unsigned short gstate_event_read(unsigned short event_idx);
extern int gstate_event_write(unsigned int event_id, unsigned int value);

#define HOTSPOT_SCOUT_TRIED(idx) ((idx) + 5200)
#define HOTSPOT_SCOUTED(idx) ((idx) + 5210)
#define ENCOUNTER_FOUGHT(idx) ((idx) + 5220)
#define SKILL_SELECTED(idx) ((idx) + 6230)
#define SKILL_IMPROVED(idx) ((idx) + 6350)
#define ITEM_USED(idx) ((idx) + 6476)
#define TOWN_VISITED(idx) ((idx) + 6480)
#define MAP_VIEWED(idx) ((idx) + 6500)
#define CONV_TOPIC_INHIBITED(idx) ((idx) + 6700)
#define DOOR_OPEN(idx) ((idx) + 7000)
#define LOCK_PICKED_WITH(idx) ((idx) + 7260)
#define CONDITION(idx) ((idx) + 7320)
#define KEYWORD_ASKED(idx) ((idx) + 7500)
extern int gstate_temp_file_open(void);
extern void gstate_temp_file_close(void);
extern int gstate_temp_file_read_at(unsigned char far *dst_far, unsigned long offset, unsigned int bytes);
extern int gstate_temp_file_write_at(unsigned char far *src_far, unsigned long offset, unsigned int bytes);

/* TEMP.GAM layout: GameState at 0, then EncounterTable, then the keyed
   record regions below, each based at the end of the previous one (the
   objfixed directory keeps 0x28 spare bytes). Accessors yield the file
   offset of record idx. The Combatant pool base must fold in long
   (1730 * 0x5f overflows 16-bit arithmetic). */
#define GAM_ENCOUNTER_TABLE sizeof(GameState)
#define GAM_OBJFIXED_LOCATION(idx)                                                                 \
    ((idx) * sizeof(ObjFixedLocationCacheEntry) + (GAM_ENCOUNTER_TABLE + sizeof(EncounterTable)))
#define GAM_ENC_ROSTER(idx) ((idx) * (7 * sizeof(short)) + (GAM_OBJFIXED_LOCATION(20) + 0x28))
#define GAM_ENC_FOUGHT_TIME(idx) ((idx) * sizeof(unsigned long) + GAM_ENC_ROSTER(700))
#define GAM_ENC_VISITED_TIME(idx) ((idx) * sizeof(unsigned long) + GAM_ENC_FOUGHT_TIME(700))
#define GAM_ENC_OBJ_STATE(idx) ((idx) * sizeof(EncounterObjectState) + GAM_ENC_VISITED_TIME(700))
#define GAM_COMBAT_ACTOR(idx) ((idx) * sizeof(Combatant) + GAM_ENC_OBJ_STATE(40 * 5 * 7))
#define GAM_COMBAT_ACTOR_INNER(idx) ((idx) * sizeof(CombatantState) + GAM_COMBAT_ACTOR(1730L))
extern int gstate_member_consume_rations(int member_slot, int a);
extern int gstate_advance_time(long seconds, int flags, int recompute_party, int a, int b);
extern int gstate_advance_half_hours(int half_hours, int pad, int flags);
extern int gstate_is_party_member(int actor_id);
extern int gstate_actor_is_caster(Combatant *actor);
extern Combatant *gstate_party_member_record(int slot);
extern int gstate_find_party_slot(Combatant *actor);
extern void gstate_format_money(char *buf, long gold, int mode);

#endif
