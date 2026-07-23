#ifndef BAK_CSPELL_H
#define BAK_CSPELL_H

#include "structs.h"

extern void cspell_gfx_wipe_horizontal_split(int x, int y, int w, int h);
extern int cspell_compute_effect_magnitude(CombatActor *actor, int level, int spell_id);
extern void cspell_flash_actor_status_effect(CombatActor *actor, int effect_type);
extern int cspell_check_castable(int spell_id, CombatActor *actor, int param_3);
extern void cspell_summon_monster(int monster_type, int prompt_for_tile);
extern void cspell_apply_step_tile_spell(CombatActor *mover, int spell_id, int intensity,
                                         int caster_class);
extern void cspell_status_effect_clear_actor(CombatActor *actor);
extern int cspell_status_effect_add(CombatActor *actor, int type, int source, int duration,
                                    unsigned char flag);
extern void cspell_status_effect_remove(CombatActor *actor, int slot);
extern int cspell_stat_effect_find_type(CombatActor *actor, int type);
extern void cspell_tile_trap_trigger(CombatActor *actor);
extern void cspell_invoke_effect(CombatActor *actor, CombatActor **target_slot, int spell_id,
                                 int *out_chain_flag, int extra);
extern int cspell_record_field8(int idx);
extern void cspell_subsystem_load(void);
extern void cspell_subsystem_unload(void);
extern void cspell_resolve_cast(CombatActor *caster, CombatActor *target, int spell_id,
                                int intensity);
extern int cspell_actor_stat_get_comb_dflt(CombatActor *actor, int spell_id);
extern void cspell_apply_hit_at(CombatActor *caster, CombatActor **target_ptr, int src_id,
                                int *dst_ptr, int magnitude, int spell_kind, int knockback);
extern void cspell_vfx_run_and_wait(void);
extern void cspell_tick_actor_stat_fx(void);
extern int cspell_ai_pick_castable_spell(CombatActor *caster, CombatActor *target, int school,
                                         int kind);
extern int cspell_cast_menu_loop(CombatActor *caster, int *out_result, int *preferred_caster_slot,
                                 int *preselect_spell);
extern void cspell_tick_damage_terrain(void);
extern void cspell_status_effect_pool_init(void);
extern void cspell_status_effect_pool_free(void);
extern int cspell_status_effect_alloc_slot(void);
extern void cspell_apply_damage_armor_wear(CombatActor *actor, int damage);
extern void cspell_palette_fade_to(int target_color, int target_intensity);
extern void cspell_actor_charge_to_target(CombatActor *param_1, CombatActor *param_2, int param_3);
extern void cspell_perform_ranged_hit(CombatActor *param_1, CombatActor *param_2, int param_3);
extern void cspell_select_target_tile(void);
extern void cspell_actor_walk_with_sound(CombatActor *actor, CombatActor *target);
extern void cspell_try_add_status_effect(CombatActor *actor, int stat_idx, int value);
#ifdef V102CD
extern void far combat_ai_resolve_hit(CombatActor *attacker, CombatActor *target, int damage,
                                      int dir);
#endif
extern void cspell_apply_damage_with_recoil(CombatActor *attacker, CombatActor *target,
                                            int spell_id, int damage);
extern int cspell_count_terrain7_tiles(void);
extern int cspell_collect_castable(CombatActor *caster, int category);
extern void cspell_draw_panel_text_list(MenuPage *panel, char **strings, int count,
                                        int first_visible, int row_count);
extern int cspell_paged_record_lookup_by_id(int slot);
extern void cspell_scroll_clamp_cursor(int *cursor, int *scroll, int visible_rows, int total_rows);
extern void cspell_symbol_resources_load(int chapter);

#endif
