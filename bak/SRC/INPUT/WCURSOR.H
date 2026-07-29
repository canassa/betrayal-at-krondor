#ifndef BAK_WCURSOR_H
#define BAK_WCURSOR_H

#include "structs.h"

extern unsigned short g_nHitTestEntryCount;
extern unsigned short g_nHitTestWriteSlot;
extern WorldHotspot *g_pWorldHitTestTable;
extern long g_anEntityKindRenderDist[43];

extern void wcursor_load_detect_dat(void);
extern void wcursor_free_detect_dat(void);
extern int wcursor_dispatch_action(void);
extern void wcursor_zone_loot_body(WorldHotspot *pHotspot);
extern void wcursor_zone_open_container(WorldHotspot *pHotspot);
extern void wcursor_click_fixedobj_full(WorldHotspot *pHotspot);
extern void wcursor_interact_container_event(WorldHotspot *pHotspot);
extern void wcursor_click_blocked_path(WorldHotspot *pHotspot);
extern void wcursor_script_summon_actor(WorldHotspot *pHotspot);
extern void wcursor_click_inn_or_lock_npc(WorldHotspot *pHotspot);
extern void wcursor_click_fixedobj_examine(WorldHotspot *hotspot);
extern void wcursor_click_locked_or_sealed(WorldHotspot *pHotspot);
extern void wcursor_click_fixedobj(WorldHotspot *pHotspot);
extern int wcursor_object_toggle_open_close(WorldHotspot *pHotspot);
extern void wcursor_click_npc_or_trap(WorldHotspot *pHotspot);
extern void wcursor_click_door_or_secret(WorldHotspot *pHotspot);
extern void wcursor_click_fixedobj_picklock(WorldHotspot *hotspot);
extern void wcursor_open_container_at_cursor(WorldHotspot *p_hotspot);
extern void wcursor_click_locked_stub(WorldHotspot *hotspot);
extern void wcursor_interact_fixedobj_variant_a(WorldHotspot *p_hotspot);
extern void wcursor_click_dig_or_use_shovel(WorldHotspot *pHotspot);
extern void wcursor_click_body(WorldHotspot *pHotspot);
extern void wcursor_interact_fixedobj_container(WorldHotspot *pHotspot);
extern void wcursor_fixedobj_examine_var_a(WorldHotspot *hotspot);
extern void wcursor_fixedobj_examine_var_b(WorldHotspot *pHotspot);
extern void wcursor_click_fixedobj_open(WorldHotspot *pHotspot);
extern void wcursor_loot_corpse(WorldHotspot *pHotspot, int nSlot);
extern void wcursor_encounter_hint(WorldHotspot *pHotspot, int nSlot);
extern void wcursor_fixedobj_examine_var_c(WorldHotspot *pHotspot);

#endif
