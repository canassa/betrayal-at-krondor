#include <dos.h>
#include <stdio.h>
#include <stdlib.h>

#include "gtypes.h"
#include "globals.h"
#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"
extern void combat_arena_mode_enter(void);
extern void combat_arena_mode_exit(void);
extern void combat_arena_tick_status_timers(void);
extern void combat_arena_actor_turn_loop(int encounter_id, int *p_status, int b_has_fired);
extern void combat_arena_suspend_char_screen(CombatActor *actor, int *p_spell_result,
                                             int *p_spell_out);
extern void combat_arena_splash_dmg_near(CombatActor *source_actor, int damage);
extern void combat_arena_actor_set_anim_pose(CombatActor *actor, uchar frame);
extern void combat_arena_swap_tgt_state(void);
extern int combat_arena_wait_confirm_cancel(void);
extern void combat_arena_resolve_melee_swing(CombatActor *attacker, CombatActor *defender,
                                             int damage);
extern void combat_arena_melee_attack(CombatActor *attacker, CombatActor *defender, int damage);
extern void combat_arena_apply_damage(CombatActor *actor, int damage, int apply_magic_defense,
                                      int knockback, uint flags, int source_type);
extern void combat_arena_actor_poison_tick(CombatActor *actor);
extern void combat_arena_actor_die(CombatActor *actor, int play_anim);
extern void combat_arena_load_remap_pals(void);
extern void combat_arena_remove_flagd_actors(void);
extern int combat_arena_all_targets_immune(void);
extern ushort combat_arena_anim_tbl_lookup_2d(int row, int col);
extern void combat_arena_round_trans_show(int param_1);
extern void combat_arena_draw_tgt_info_hud(CombatActor *param_1, int param_2, int param_3,
                                           int param_4);
extern void combat_arena_draw_tgt_info_panel(void);
extern void combat_arena_hud_melee_panel(void);
extern int combat_arena_cnt_actors_combat(void);
extern int combat_arena_cnt_actors_flag_10(void);
extern void combat_arena_resume_dispatch(int command_id, int *p_spell_result,
                                         int *out_spell_result);
extern int combat_arena_dist_actors_by_id(int actor_id_a, int actor_id_b);
extern void combat_arena_show_message_by_id(int message_id, unsigned short *p_menu, int *p_param3,
                                            int *p_param4, int *p_param5, int *p_spell_result,
                                            int *p_spell_out, int *p_param8, MenuPage **p_menu_slot,
                                            int *p_param10, int *p_param11);
extern CombatActor *combat_arena_disp_spell_action(int *param_1, int *param_2, int *param_3,
                                                   int param_4, int *param_5, int *param_6);
extern void combat_arena_turn_actor_inact(uint *p_far_offset, int *p_turn_done, int *p_hud_state,
                                          int *p_ai_flag);
extern void combat_arena_resolve_menu_action(int *p_state_a, int *p_move_cost, int *p_state_b,
                                             int b_input_locked, int b_input_gate, int *p_dirty_hud,
                                             CombatActor **pp_cursor_target, int arg8,
                                             int spell_record_id, int arg10,
                                             MenuPage **pp_menu_slot);
#include "SRC/SYS/RAND.H"
#include "SRC/IO/IO.H"
#include "SRC/IO/IOCHUNK.H"
#include "SRC/SYS/MEM.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/GFX/RASTER/DRAWLINE.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/R3D/SPRITE/WORLDRND.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/R3D/FX/WORLDFX.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/CHAR/CHARSCRN.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "SRC/COMBAT/AI/CBTAITRN.H"
#include "SRC/COMBAT/SPELL/CSPELL.H"
#include "SRC/COMBAT/STATS/CBSTAT.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/WORLD/ENC/HOTSPOT.H"
#include "SRC/WORLD/ENC/RGNENC.H"
#include "defines.h"
#include "gfx169d.h"

CombatActor *g_current_actor;
CombatActor *g_picked_actor;
unsigned short g_acting_actor_speed;
int g_grid_tile_size;
short g_cursor_tile_x;
short g_cursor_tile_y;
unsigned short g_wInCombatMode;
MenuPage *g_combat_menu;
MenuPage *g_shoot_menu;
unsigned short g_combat_menu_selected_item;
unsigned short g_combat_menu_current_page;
short g_nCurrentQuarrelKindIdx;
unsigned short g_combat_cancelled;
unsigned short g_combat_music_handle;
CombatActor *g_acting_actor;
unsigned short g_traps_loaded_flag;
unsigned short g_encounter_id;
CombatActor *g_pCombatActiveActors;
AnimSlot *g_pCombatActiveAnimPool;
int g_nCombatActiveCount;
CombatActor *g_pCombatOtherActors;
AnimSlot *g_pCombatOtherAnimPool;
int g_nCombatOtherCount;
ImageRecord **g_combat_sprites;
ImageRecord **g_parch_bmx;
ImageRecord **g_combat_render_table_prev;

unsigned short g_bCombatGridTerrainFeaturesEnabled = 0x0001;
unsigned short g_bCombatGridLinesEnabled = 0x0000;

unsigned short g_dgroup_12c4 = 0x0001;
unsigned short g_bShowActorRosterIndex = 0x0000;
unsigned short g_bStormAmplify = 0x0000;
unsigned short **g_pTerrainBackupGrid = {0};
unsigned short g_awQuarrelKindItemIdTable[8] = {0x0002, 0x0003, 0x0004, 0x0005,
                                                0x0006, 0x0008, 0x0009, 0x0007};
unsigned short g_quarrel_kind_field19_table[8] = {0x0045, 0x0037, 0x0039, 0x003d,
                                                  0x003f, 0x0041, 0x0043, 0x003b};

void far combat_arena_mode_enter(void) {
    int i;
    int rem;

    zone_teardown(1);
    itemtbl_load();
    rem = (int)RND(3);

    switch (rem) {
    case 0:
        rem = 0x40a;
        break;
    case 1:
        rem = 0x3ed;
        break;
    default:
        rem = 0x413;
    }
    if ((g_engine_prefs != (EnginePrefs *)0x0) && ((g_engine_prefs->flags & 4) != 0)) {
        g_combat_music_handle = audio_music_play(rem);
    } else {
        g_combat_music_handle = audio_music_play(-1);
    }
    audio_sfx_register_combat_bank();
    g_parch_bmx = resblit_load_asset_table("parch.bmx", 0);
    worldrender_swap_record_table(0, 1);
    g_combat_sprites = resblit_load_asset_table("figs.bmx", 0);
    g_combat_render_table_prev = worldrender_table_swap(0, g_combat_sprites);
    g_combat_menu = menupage_load("combat.dat");
    g_shoot_menu = menupage_load("shoot.dat");
    combat_actor_init_pool();
    combatenc_pty_load_chap_state();
    cspell_status_effect_pool_init();
    cspell_subsystem_load();
    cbstat_spell_tables_load();
    g_pCombatActiveActors = g_combat_actors_A;
    g_pCombatActiveAnimPool = g_anim_pool_A;
    g_nCombatActiveCount = g_combat_count_A;
    g_pCombatOtherActors = g_combat_actors_B;
    g_pCombatOtherAnimPool = g_anim_pool_B;
    g_nCombatOtherCount = g_combat_count_B;
    i = 0;
    if (i < g_nCombatActiveCount) {
        do {

            combat_actor_anim0_if_not_dead(&g_pCombatActiveActors[i], R3D_DEG(90));
            combat_actor_anim_rand_phase(&g_pCombatActiveActors[i]);
            i = i + 1;
        } while (i < g_nCombatActiveCount);
    }
    i = 0;
    if (i < g_nCombatOtherCount) {
        do {
            if ((g_pCombatOtherActors[i].inner)->flags & CAF_DEAD) {
                combat_actor_anim_spr1_alt(&g_pCombatOtherActors[i], 0);
            } else {
                combat_actor_anim0_if_not_dead(&g_pCombatOtherActors[i], 0);
                combat_actor_anim_rand_phase(&g_pCombatOtherActors[i]);
            }
            i = i + 1;
        } while (i < g_nCombatOtherCount);
    }
    screen_cursor_restore_shape();
    screen_cursor_hide();
}

void far combat_arena_mode_exit(void) {
    cbstat_spell_tables_free();
    cspell_subsystem_unload();
    cspell_status_effect_pool_free();
    combatenc_release_actors();
    combat_actor_pool_teardown();
    menupage_free(g_shoot_menu);
    menupage_free(g_combat_menu);
    worldrender_table_swap(0, g_combat_render_table_prev);
    free_image_record(g_combat_sprites);
    worldrender_swap_record_table(0, 1);
    free_image_record(g_parch_bmx);
    audio_sfx_stop_combat_bank();
    audio_music_play(g_combat_music_handle);
    itemtbl_free();
    zone_refresh_visible(1);
}

void far combat_arena_load_remap_pals(void) {
    BakFile *fp;

    fp = bak_fopen("red.rmp", "rb");
    bak_fread_chunked(g_abCursorPaletteLut + 0x100, (long)0x100, (long)1, fp);
    bak_fclose(fp);
    fp = bak_fopen("green.rmp", "rb");
    bak_fread_chunked(g_abCursorPaletteLut + 0x200, (long)0x100, (long)1, fp);
    bak_fclose(fp);
    fp = bak_fopen("white.rmp", "rb");
    bak_fread_chunked(g_abCursorPaletteLut + 0x300, (long)0x100, (long)1, fp);
    bak_fclose(fp);
    fp = bak_fopen("blue.rmp", "rb");
    bak_fread_chunked(g_abCursorPaletteLut + 0x400, (long)0x100, (long)1, fp);
    bak_fclose(fp);
}

int far combat_arena_wait_confirm_cancel(void) {
    int result;
    int code;

    result = 0;
    code = screen_input_poll_confirm_cancel();
    if (code == 1) {
        result = 1;
    } else if (code == 2) {
        result = 2;
    }
    return result;
}

void far combat_arena_actor_poison_tick(CombatActor *actor) {
    int flags;
    if ((actor->inner->flags & CAF_POISON) != 0 &&
        ((flags = (int)(signed char)actor->inner->flags) & CAF_DEAD) == 0) {
        combat_arena_apply_damage(actor, RND2(2) + 1, 0, 2, 1, 0);
    }
}

void far combat_arena_actor_die(CombatActor *actor, int play_anim) {
    int slot;
    uint type;
    int timer;
    int i;
    int removed;

    cspell_status_effect_clear_actor(actor);
    if (play_anim != 0) {
        type = combatgrid_tile_terrain_field(actor->inner->grid_x, actor->inner->grid_y);
        timer = combatgrid_tile_field4(actor->inner->grid_x, actor->inner->grid_y);
        combatgrid_set_tile_effect(actor->inner->grid_x, actor->inner->grid_y, 0, -1);
        removed = 0;
        combat_actor_play_anim_sprite1(actor, -1);
        combat_actor_register(actor);
        switch (actor->inner->class_id) {
        case 15:
        case 16:
        case 17:
        case 45:
        case 51:

            g_acting_actor = actor;
            goto LAB_600f_0468;
        case 56:
        case 57:

            combat_actor_grid_remove(actor);
            slot = cspell_status_effect_add(actor, 0x20, 0, 0, '\0');
            cspell_vfx_run_and_wait();
            cspell_status_effect_remove(actor, slot);
            combatgrid_tile_set_word(actor->inner->grid_x, actor->inner->grid_y, 0);
            if ((actor->inner->flags & CAF_AI_SUMMON) != 0) {
                combat_actor_remove(actor);
                goto LAB_600f_0468;
            }
            removed = 1;
            goto LAB_600f_0468;
        case 49:

            combat_actor_grid_remove(actor);
            combatgrid_tile_set_word(actor->inner->grid_x, actor->inner->grid_y, 0);
            removed = 1;
            goto LAB_600f_0468;
        case 22:
        case 23:

            actor->inner->dmg_value = '\0';
            actor->inner->dmg_frames_left = (uchar)RND(7) + 4;
        }
    LAB_600f_0468:
        combatgrid_set_tile_effect(actor->inner->grid_x, actor->inner->grid_y, type, timer);
        goto LAB_600f_0486;
    }
    removed = 1;
LAB_600f_0486:
    actor->stats[0].base = '\0';
    stat_actor_get(actor, 0, 0);
    actor->stats[1].base = '\0';
    stat_actor_get(actor, 1, 0);
    actor->inner->flags |= CAF_DEAD;
    stat_combatant_apply_delta(actor, 6, 100);
    if (removed) {
        for (i = 0; i < g_combat_count_B; i++) {
            if (&g_combat_actors_B[i] == actor) {
                rgnenc_persist_actor_removed((short)g_encounter_id, i);
                return;
            }
        }
    }
}

void far combat_arena_remove_flagd_actors(void) {
    int i;

    i = 0;
    if (i < g_combat_count_A) {
        do {
            if ((g_combat_actors_A[i].inner->flags & CAF_AI_SUMMON) != 0) {
                combat_actor_remove(&g_combat_actors_A[i]);
            }
            i = i + 1;
        } while (i < g_combat_count_A);
    }
}

#pragma option -O-l
int far combat_arena_all_targets_immune(void) {
    int immune;
    int i;

    immune = 1;
    for (i = 0; i < g_combat_count_B; i = i + 1) {
        switch (g_combat_actors_B[i].inner->class_id) {
        case 0x31:
        case 0x38:
        case 0x39:
            break;
        default:
            immune = 0;
        }
    }
    return immune;
}
#pragma option -Ol

void far combat_arena_apply_damage(CombatActor *actor, int damage, int apply_magic_defense,
                                   int knockback, uint flags, int source_type) {
    int iBonus;
    int savedDamage;
    int effectSlot;

    if ((((actor->inner->class_id != 0x36) && (cspell_stat_effect_find_type(actor, 1) == -1)) &&
         (actor->inner->class_id != -1)) &&
        (((actor->inner->flags & CAF_DEAD) == 0 && (damage >= 1)))) {
        if (apply_magic_defense != 0) {
            iBonus = cbstat_magic_defense_bonus(actor);
            damage = (damage * (100 - iBonus)) / 100;
            if (damage == 0) {
                damage = RND2(2) + 1;
            }
        }
        effectSlot = cspell_stat_effect_find_type(actor, 6);
        if ((source_type == 0) && (effectSlot != -1)) {
            g_pStatusEffectPool[effectSlot].nDuration_or_hp -= damage;
            damage = 0;
            if (g_pStatusEffectPool[effectSlot].nDuration_or_hp < 0) {
                damage = (g_pStatusEffectPool[effectSlot].nDuration_or_hp < 0)
                             ? ((g_pStatusEffectPool[effectSlot].nDuration_or_hp == -0x8000)
                                    ? 0x7fff
                                    : -g_pStatusEffectPool[effectSlot].nDuration_or_hp)
                             : g_pStatusEffectPool[effectSlot].nDuration_or_hp;
                cspell_status_effect_remove(actor, effectSlot);
            }
            if (damage == 0) {
                return;
            }
        }
        if ((source_type == 0) && ((cspell_stat_effect_find_type(actor, 0x17) != -1 ||
                                    cspell_stat_effect_find_type(actor, 1) != -1))) {
            damage = 0;
        }
        damage = cbstat_apply_proficiency_bonus(actor, damage, flags);
        damage = cbstat_apply_weakness_penalty(actor, damage, flags);
        if ((damage != 0) && ((flags & 1) != 0)) {
            cbstat_apply_drain_tick(actor);
        }
        if ((int)(uint)actor->stats[1].base < damage) {
            savedDamage = damage;
            damage -= actor->stats[1].base;
            actor->stats[1].base = '\0';
            if ((int)(uint)actor->stats[0].base < damage) {
                actor->stats[0].base = '\0';
            } else {
                actor->stats[0].base = actor->stats[0].base - (char)damage;
            }
            damage = savedDamage;
        } else {
            actor->stats[1].base = actor->stats[1].base - (char)damage;
        }
        if (damage != 0 && knockback != 0) {
            actor->inner->flags |= CAF_KNOCKBACK;
            actor->inner->knockback_value = (uchar)knockback;
            actor->inner->knockback_timer = '\x02';

            if (damage < 1000) {
                actor->inner->dmg_value = (char)damage;
                actor->inner->dmg_frames_left = '\b';
            }
        } else {
            if (knockback != 0) {
                actor->inner->dmg_value = '\x01';
                actor->inner->dmg_frames_left = 0xf8;
            }
        }
        if ((flags & 4) != 0) {
            g_nVfxParticleColor = 0x6f;
            effectSlot = cspell_status_effect_add(actor, 4, 0, 0, '\0');
            worldfx_combat_damage_ptcl_burst(actor, 0xf);
            cspell_status_effect_remove(actor, effectSlot);
        }
        if ((flags & CAF_DEAD) != 0) {
            cspell_flash_actor_status_effect(actor, 0x17);
        }
        if ((flags & 0x10) != 0) {
            cspell_flash_actor_status_effect(actor, 2);
        }
        if ((flags & 0x20) != 0) {
            cspell_flash_actor_status_effect(actor, 0xd);
        }
        if ((uchar)actor->stats[0].base <= 0) {
            combat_arena_actor_die(actor, 1);
            actor->inner->flags &= ~CAF_FLEE;
        }
        stat_actor_get(actor, 1, 0);
        stat_actor_get(actor, 0, 0);
    }
    return;
}

void far combat_arena_splash_dmg_near(CombatActor *source_actor, int damage) {
    int nMaxDist;
    int dist;
    int i;

    nMaxDist = 2;
    damage = damage >> 2;
    i = 0;
    if (i < g_combat_count_A) {
        do {
            if (&g_combat_actors_A[i] != source_actor) {
                dist = combatgrid_chebyshev_distance(
                    source_actor->inner->grid_x, source_actor->inner->grid_y,
                    (g_combat_actors_A[i].inner)->grid_x, (g_combat_actors_A[i].inner)->grid_y);
                if (dist <= nMaxDist) {
                    if (cbstat_char_bitmap_3w_test((g_combat_actors_A[i].inner)->class_id, 4) ==
                        0) {
                        combat_arena_apply_damage(&g_combat_actors_A[i], damage - dist, 0, 1, 0x200,
                                                  0);
                    }
                }
            }
            i = i + 1;
        } while (i < g_combat_count_A);
    }
    i = 0;
    if (i < g_combat_count_B) {
        do {
            if (&g_combat_actors_B[i] != source_actor) {
                dist = combatgrid_chebyshev_distance(
                    source_actor->inner->grid_x, source_actor->inner->grid_y,
                    (g_combat_actors_B[i].inner)->grid_x, (g_combat_actors_B[i].inner)->grid_y);
                if (dist <= nMaxDist) {
                    if (cbstat_char_bitmap_3w_test((g_combat_actors_B[i].inner)->class_id, 4) ==
                        0) {
                        combat_arena_apply_damage(&g_combat_actors_B[i], damage - dist, 0, 1, 0x200,
                                                  0);
                    }
                }
            }
            i = i + 1;
        } while (i < g_combat_count_B);
    }
    return;
}

void far combat_arena_melee_attack(CombatActor *attacker, CombatActor *defender, int damage) {
    int hit;
    uint armorMask;
    ItemRecord far *weapon_item;

    if ((defender->inner->flags & CAF_DEAD) == 0) {
        stat_combatant_modify(defender, 4, 1, 3);
        stat_combatant_modify(attacker, 6, 1, 3);
        attacker->inner->target = defender;
        if (1 < (int)stat_actor_get(attacker, 0x10, 4)) {
            combat_arena_apply_damage(attacker, 1, 0, 0, 0, 1);
            attacker->inner->flags &= ~CAF_KNOCKBACK;
            weapon_item = cbstat_find_intact_equip_cat(attacker, 1);
            hit = cbstat_to_hit_roll(attacker, defender, weapon_item->nDefense_or_range_close,
                                     weapon_item);

            if ((defender->inner->flags & CAF_PARRY) != 0 &&
                combatenc_actor_can_act(defender, 0) != 0) {

                combat_actor_play_anim_sprite6(defender,
                                               combat_actor_heading_from_to(defender, attacker));
            } else {

                combat_actor_anim0_if_not_dead(defender,
                                               combat_actor_heading_from_to(defender, attacker));
            }
            combat_actor_play_anim_sprite3(attacker,
                                           combat_actor_heading_from_to(attacker, defender));
            if (hit) {

                stat_combatant_modify(attacker, 6, 1, 3);
                stat_combatant_modify(attacker, 3, 1, 3);
                if (weapon_item != (ItemRecord far *)0) {
                    cbstat_damage_equipped_items(attacker, 1, 0x100);
                }

                {
                    int sound_id;
                    switch (attacker->inner->class_id) {
                    case 0x13:
                    case 0x1c:
                    case 0x29:
                    case 0x2a:
                    case 0x2b:
                    case 0x2e:
                    case 0x30:
                        sound_id = 0x4a;
                        goto do_audio;
                    case 0x27:
                    case 0x2c:
                    case 0x31:
                    case 0x3a:
                        sound_id = 0x1a;
                        goto do_audio;
                    }
                    if (!cbstat_find_intact_equip_cat(attacker, 3)) {
                        sound_id = 0x41;
                    } else {
                        sound_id = 0x42;
                    }
                do_audio:
                    audio_play(sound_id);
                }
                if (damage == 0) {
                    damage = cbstat_compute_attack_damage(weapon_item, attacker, defender, 0);
                }
                armorMask = cbstat_armor_coverage_mask(attacker);
                combat_arena_apply_damage(defender, damage, 1, 1, armorMask, 0);
            } else {

                stat_combatant_modify(defender, 4, 1, 3);

                defender->inner->dmg_value = '\x01';
                defender->inner->dmg_frames_left = 0xf8;

                {
                    int cf;
                    if (((cf = (int)(signed char)defender->inner->flags) & CAF_PARRY) == 0 ||
                        combatenc_actor_can_act(defender, 0) == 0) {
                        stat_combatant_modify(defender, 4, 1, 3);
                        if (weapon_item != (ItemRecord far *)0) {
                            cbstat_damage_equipped_items(attacker, 1, 0x100);
                        }
                        audio_play(0x13);
                    } else {

                        if (cbstat_find_intact_equip_cat(defender, 3) != (ItemRecord far *)0 &&
                            cbstat_find_intact_equip_cat(attacker, 3) != (ItemRecord far *)0) {
                            audio_play(0x43);
                        } else {
                            if (cbstat_find_intact_equip_cat(defender, 3) == (ItemRecord far *)0 &&
                                cbstat_find_intact_equip_cat(attacker, 3) == (ItemRecord far *)0) {
                                audio_play(7);
                            } else {
                                audio_play(0x42);
                            }
                        }
                    }
                }
            }
            if ((combat_actor_enc_lookup_field2(defender) != 0) &&
                (cspell_stat_effect_find_type(defender, 0xd) == -1)) {
                combat_actor_anim0_if_not_dead(defender, -1);
            }
        }
    }
}

void far combat_arena_resolve_melee_swing(CombatActor *attacker, CombatActor *defender,
                                          int damage) {
    int hit;
    int sound_id;
    uint flags;
    ItemRecord far *weapon_item;

    if ((defender->inner->flags & CAF_DEAD) == 0) {
        stat_combatant_modify(attacker, 6, 1, 3);
        stat_combatant_modify(defender, 4, 1, 3);
        attacker->inner->target = defender;
        weapon_item = cbstat_find_intact_equip_cat(attacker, 1);
        hit =
            cbstat_to_hit_roll(attacker, defender, weapon_item->nAttack_or_range_long, weapon_item);
        if ((defender->inner->flags & CAF_PARRY) && combatenc_actor_can_act(defender, 0)) {
            combat_actor_play_anim_sprite5(defender,
                                           combat_actor_heading_from_to(defender, attacker));
        } else {
            combat_actor_anim0_if_not_dead(defender,
                                           combat_actor_heading_from_to(defender, attacker));
        }
        combat_actor_play_anim_sprite4(attacker, combat_actor_heading_from_to(attacker, defender));
        if (hit != 0) {
            stat_combatant_modify(attacker, 6, 1, 3);
            stat_combatant_modify(attacker, 3, 1, 3);
            if (weapon_item != (ItemRecord far *)0x0) {
                cbstat_damage_equipped_items(attacker, 1, 0x80);
            }
            switch (attacker->inner->class_id) {
            case 0x13:
            case 0x1c:
            case 0x29:
            case 0x2a:
            case 0x2b:
            case 0x2e:
            case 0x30:
                sound_id = 0x4a;
                break;
            case 0x27:
            case 0x2c:
            case 0x31:
            case 0x3a:
                sound_id = 0x1a;
                break;
            default:
                if (cbstat_find_intact_equip_cat(attacker, 3) == (ItemRecord far *)0x0) {
                    sound_id = 0x41;
                } else {
                    sound_id = 0x42;
                }
                break;
            }
            audio_play(sound_id);
            if (damage == 0) {
                damage = cbstat_compute_attack_damage(weapon_item, attacker, defender, 1);
            }
            flags = cbstat_armor_coverage_mask(attacker);
            combat_arena_apply_damage(defender, damage, 1, 1, flags, 0);
        } else {
            stat_combatant_modify(defender, 4, 1, 3);
            defender->inner->dmg_value = '\x01';
            defender->inner->dmg_frames_left = 0xf8;
            combat_actor_anim0_if_not_dead(defender, -1);
            if (!((int)(char)(defender->inner->flags) & CAF_PARRY) ||
                combatenc_actor_can_act(defender, 0) == 0) {
                stat_combatant_modify(defender, 4, 1, 3);
                if (weapon_item != (ItemRecord far *)0x0) {
                    cbstat_damage_equipped_items(attacker, 1, 0x80);
                }
                audio_play(0x13);
            } else {
                if (cbstat_find_intact_equip_cat(defender, 3) != (ItemRecord far *)0x0 &&
                    cbstat_find_intact_equip_cat(attacker, 3) != (ItemRecord far *)0x0) {
                    audio_play(0x43);
                } else {
                    if (cbstat_find_intact_equip_cat(defender, 3) == (ItemRecord far *)0x0 &&
                        cbstat_find_intact_equip_cat(attacker, 3) == (ItemRecord far *)0x0) {
                        audio_play(7);
                    } else {
                        audio_play(0x42);
                    }
                }
            }
        }
        if (combat_actor_enc_lookup_field2(defender) != 0 &&
            cspell_stat_effect_find_type(defender, 0xd) == -1) {
            combat_actor_anim0_if_not_dead(defender, -1);
        }
    }
    return;
}

ushort combat_arena_anim_tbl_lookup_2d(int row, int col) {
    return g_pTerrainBackupGrid[row][col];
}

static void far combat_arena_burn_terr_cutsc(void) {
    int bDone;
    int y, x;
    ushort duration;
    int i;
    GridCombatant *pGcmbt;

    bDone = 0;

    g_pTerrainBackupGrid = galloc_safe_zcalloc(0x10);
    for (y = 0; y < 8; y++) {
        g_pTerrainBackupGrid[y] = galloc_safe_zcalloc(0x1a);
    }

    for (y = 0; y < 8; y++) {
        for (x = 0; x < 13; x++) {
            g_pTerrainBackupGrid[y][x] = combatgrid_tile_terrain_field(y, x);
            pGcmbt = combatgrid_find_cmbt_at_tile(y, x);
            if (pGcmbt != 0) {
                if (combatgrid_is_combatant_type(pGcmbt->paged_id) != 0) {

                    duration = RNDR(0x190, 0x2bb);
                    combatgrid_set_tile_effect(y, x, 9, duration);
                }
            }
        }
    }

    world_render_with_overlay(MK_FP(0, 0xffff));
    screen_frame_present();
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
    gfx_present_dispatch(0, 0, 0x140, 200);
    palette_fade_in(0, 0x100, -1, 0);
    audio_play(0x47);

    while (!bDone) {
        for (i = 0; i < 15; i++) {
            cspell_tick_damage_terrain();
        }

        y = 0;
        do {
            x = 0;
            do {
                if (combatgrid_tile_terrain_field(y, x) != 9) {
                    pGcmbt = combatgrid_find_cmbt_at_tile(y, x);
                    if (pGcmbt != 0) {
                        if (combatgrid_is_combatant_type(pGcmbt->paged_id) != 0) {
                            combatgrid_set_tile_effect(y, x, g_pTerrainBackupGrid[y][x], -1);
                        }
                    }
                }
                x++;
            } while (x < 13);
            y++;
        } while (y < 8);

        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
        bDone = 1;

        y = 0;
        do {
            x = 0;
            do {
                if (combatgrid_tile_terrain_field(y, x) == 9) {
                    bDone = 0;
                }
                x++;
            } while (x < 13);
            y++;
        } while (y < 8);
    }

    y = 0;
    do {
        x = 0;
        do {
            pGcmbt = combatgrid_find_cmbt_at_tile(y, x);
            if (pGcmbt != 0) {
                if (combatgrid_is_combatant_type(pGcmbt->paged_id) != 0) {
                    combatgrid_set_tile_effect(y, x, g_pTerrainBackupGrid[y][x], -1);
                }
            }
            x++;
        } while (x < 13);
        y++;
    } while (y < 8);

    y = 0;
    do {
        galloc_zfree(g_pTerrainBackupGrid[y]);
        y++;
    } while (y < 8);
    galloc_zfree(g_pTerrainBackupGrid);
    g_pTerrainBackupGrid = 0;
}

static void far combat_arena_burn_type31_cutsc(void) {
    int bDone;
    int y, x, i;
    uint tile;
    CombatActor *saved_actor;

    bDone = 0;
    saved_actor = g_current_actor;
    g_current_actor = g_combat_actors_B;

    for (y = 0; y < 8; y++) {
        for (x = 0; x < 13; x++) {
            tile = combatgrid_tile_terrain((char)y, (char)x);
            if (tile != 0 && ((CombatActor *)tile)->inner->class_id == 0x31) {
                combatgrid_set_tile_effect((char)y, (char)x, 9, 500);
            }
        }
    }

    world_render_with_overlay(MK_FP(0, 0xffff));
    screen_frame_present();
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
    gfx_present_dispatch(0, 0, 0x140, 200);
    palette_fade_in(0, 0x100, -1, 0);

    while (!bDone) {
        for (i = 0; i < 15; i++) {
            cspell_tick_damage_terrain();
        }
        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
        bDone = 1;
        for (y = 0; y < 8; y++) {
            for (x = 0; x < 13; x++) {
                if (combatgrid_tile_terrain_field((char)y, (char)x) == 9) {
                    bDone = 0;
                }
            }
        }
    }

    for (y = 0; y < 8; y++) {
        for (x = 0; x < 13; x++) {
            tile = combatgrid_tile_terrain((char)y, (char)x);
            if (tile != 0 && ((CombatActor *)tile)->inner->class_id == 0x31) {
                combatgrid_set_tile_effect((char)y, (char)x, 0, -1);
            }
        }
    }

    g_current_actor = saved_actor;
}

void far combat_arena_round_trans_show(int param_1) {
    screen_cursor_hide();
    palette_fade_out(0, 0x100, -1, 0);
    palette_screen_clear_black();
    screen_frame_present();
    palette_set_scaled(0, 0x100, 0, 0);
    screen_cursor_show_busy();
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage =
        g_graphics_context.wVgaPage2Base;
    resblit_load_pal_or_stream("cframe.scx");
    if (param_1 != 0) {
        if (combatgrid_any_terrain_6() != 0) {
            combat_arena_burn_terr_cutsc();
            goto LAB_13a1;
        }
    }

    if ((g_encounter_id == 0x221) && (param_1 != 0)) {
        combat_arena_burn_type31_cutsc();
    } else {
        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
        gfx_present_dispatch(0, 0, 0x140, 200);
        palette_fade_in(0, 0x100, -1, 0);
    }
LAB_13a1:
    screen_cursor_restore_shape();
    return;
}

static void combat_arena_shootmenu_ent_avail(int kind, int page, MenuEntry *entry) {
    int n_quarrels;

    n_quarrels = combat_actor_cnt_qrls_kind(g_current_actor, kind);
    if ((g_combat_menu_current_page == page) && (n_quarrels != 0)) {
        entry->bActive_flag = 1;
    } else {
        entry->bActive_flag = 0;
    }
    entry->wEnable_gate = !entry->bActive_flag;
    return;
}

static void far combat_arena_shootmenu_init(void) {
    MenuEntry *entry;
    int i;

    for (i = 0; i < (int)g_shoot_menu->wEntry_count; i = i + 1) {
        entry = g_shoot_menu->pEntries + i;
        switch (entry->wAction_id) {
        case 2:
        case 3:
        case 4:
        case 5:
            entry->bActive_flag = 1;
            entry->wEnable_gate = 1;
            break;
        case 6:
        case 7:
        case 8:
        case 9:
            entry->bActive_flag = 0;
            break;
        }
    }
    menupage_draw_entries(g_shoot_menu->pEntries, g_shoot_menu->wEntry_count, g_shoot_menu->rect.x,
                          g_shoot_menu->rect.y);
    return;
}

static int far combat_arena_menu_find_item_page(ushort item_id) {
    int i;

    for (i = 0; i < (int)g_shoot_menu->wEntry_count; i++) {
        if (g_shoot_menu->pEntries[i].wAction_id == item_id)
            break;
    }
    return (i >> 2) + 1;
}

static void far combat_arena_menu_sync_sel_actor(CombatActor *actor) {
    if (actor->inner->pad_e[4] != 0xff) {
        g_combat_menu_selected_item = (int)(char)actor->inner->pad_e[4];
    } else {
        g_combat_menu_selected_item = 0;
    }
    if (combataiturn_sel_consum_qrl(actor, g_combat_menu_selected_item, 0) == -1) {
        g_combat_menu_selected_item = combataiturn_sel_consum_qrl(actor, -1, 0);
    }
    g_combat_menu_current_page =
        combat_arena_menu_find_item_page(g_awQuarrelKindItemIdTable[g_combat_menu_selected_item]);
    return;
}

static void far combat_arena_shootmenu_rebuild(void) {
    int n_quarrels;
    int page;
    MenuEntry *entry;
    int claim_idx;
    int i;

    claim_idx = 0;
    i = 0;
    do {
        if (combat_actor_cnt_qrls_kind(g_current_actor, i) != 0) {
            g_shoot_menu->pEntries[claim_idx].wAction_id = g_awQuarrelKindItemIdTable[i];
            g_shoot_menu->pEntries[claim_idx].wSprite_base = g_quarrel_kind_field19_table[i];
            claim_idx++;
        }
        i = i + 1;
    } while (i < 8);

    for (i = claim_idx; i < (int)g_shoot_menu->wEntry_count; i++) {
        if (g_shoot_menu->pEntries[i].wAction_id != 0x32 &&
            g_shoot_menu->pEntries[i].wAction_id != 0x21 &&
            g_shoot_menu->pEntries[i].wAction_id != 0x16) {
            if (i < 4) {
                g_shoot_menu->pEntries[i].wAction_id = 0xffff;
            } else {
                g_shoot_menu->pEntries[i].wAction_id = 0xfffe;
            }
        }
    }

    for (i = 0; i < (int)g_shoot_menu->wEntry_count; i = i + 1) {
        entry = g_shoot_menu->pEntries + i;
        page = combat_arena_menu_find_item_page(entry->wAction_id);
        switch (entry->wAction_id) {
        case 2:
            combat_arena_shootmenu_ent_avail(0, page, entry);
            break;
        case 3:
            combat_arena_shootmenu_ent_avail(1, page, entry);
            break;
        case 4:
            combat_arena_shootmenu_ent_avail(2, page, entry);
            break;
        case 5:
            combat_arena_shootmenu_ent_avail(3, page, entry);
            break;
        case 6:
            combat_arena_shootmenu_ent_avail(4, page, entry);
            break;
        case 8:
            combat_arena_shootmenu_ent_avail(5, page, entry);
            break;
        case 9:
            combat_arena_shootmenu_ent_avail(6, page, entry);
            break;
        case 7:
            combat_arena_shootmenu_ent_avail(7, page, entry);
            break;
        case 0xfffe:
        case 0xffff:
            if (-g_combat_menu_current_page == entry->wAction_id) {
                entry->wEnable_gate = 1;
                entry->bActive_flag = 1;
            } else {
                entry->wEnable_gate = 0;
                entry->bActive_flag = 0;
            }
            break;
        }
    }
}

static void far combat_arena_shootmenu_qrl_cur(void) {
    MenuEntry *pE;
    int i;
    unsigned short action_id;
    int x;
    int y;

    action_id = 0xffff;
    screen_cursor_get_position(&x, &y);
    for (i = 0; i < (int)g_shoot_menu->wEntry_count; i++) {
        pE = &g_shoot_menu->pEntries[i];
        if (pE->bActive_flag != 0 && pE->rect.x < x && x < pE->rect.x + pE->rect.width &&
            pE->rect.y < y && y < pE->rect.y + pE->rect.height) {
            action_id = pE->wAction_id;
            break;
        }
    }

    switch (action_id - 2) {
    case 0:
        g_nCurrentQuarrelKindIdx = 0;
        break;
    case 1:
        g_nCurrentQuarrelKindIdx = 1;
        break;
    case 2:
        g_nCurrentQuarrelKindIdx = 2;
        break;
    case 3:
        g_nCurrentQuarrelKindIdx = 3;
        break;
    case 4:
        g_nCurrentQuarrelKindIdx = 4;
        break;
    case 6:
        g_nCurrentQuarrelKindIdx = 5;
        break;
    case 7:
        g_nCurrentQuarrelKindIdx = 6;
        break;
    case 5:
        g_nCurrentQuarrelKindIdx = 7;
        break;
    default:
        g_nCurrentQuarrelKindIdx = -1;
    }

    if (g_nCurrentQuarrelKindIdx != -1) {
        if (combat_actor_cnt_qrls_kind(g_current_actor, g_nCurrentQuarrelKindIdx) == 0) {
            g_nCurrentQuarrelKindIdx = -1;
        }
    }
}

void far combat_arena_draw_tgt_info_hud(CombatActor *param_1, int param_2, int param_3,
                                        int param_4) {
    SpellDef *spellDef;
    int val;
    int accuracy;
    char *pStr;
    char buf[30];

    if (param_2 > -1) {
        spellDef = &g_pSpellDefs[param_2];
    } else {
        spellDef = (SpellDef *)0x0;
    }
    if ((param_4 != 4) || ((param_1 != (CombatActor *)0x0 &&
                            (((param_1->inner->flags & CAF_DEAD) != 0 ||
                              ((val = combatenc_is_encounter_actor(param_1)) == 0)))))) {
        param_1 = (CombatActor *)0x0;
    }
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    blit_sprite_indirect((unsigned short)*g_parch_bmx, 0x49, 0x81, 0);
    g_graphics_context.bText_fg_color = 0;
    {
        register int x;
        int y;

        pStr = "Choose a target";
        x = 0x82 - (font_text_width_ds(pStr) >> 1);
        y = 0x84;
        font_draw_text_ds(pStr, x, y);
        if (spellDef != (SpellDef *)0x0) {
            x = 0x82 - (font_text_width_ds(spellDef->pName) >> 1);
            y += 0xa;
            font_draw_text_ds(spellDef->pName, x, y);
        }
        x = 0x4e;
        y += 0xc;
        if ((((param_1 != (CombatActor *)0x0) && (spellDef != (SpellDef *)0x0)) &&
             (spellDef->nSpell_kind == 0)) &&
            (param_2 != 0x2c)) {
            pStr = "Accuracy:";
            font_draw_text_ds(pStr, x, y);
            accuracy = combatenc_compute_hit_chance(g_current_actor, param_1,
                                                    stat_actor_get(g_current_actor, 7, 0), -1);
            itoa(accuracy, buf, 10);
            x = 0x99;
            font_draw_text_ds(buf, x, y);
            x += font_text_width_ds(buf) + 1;
            font_draw_text_ds("%", x, y);
            pStr = "Damage:";
            x = 0x4e;
            y += 0xa;
            font_draw_text_ds(pStr, x, y);
            val = cspell_compute_effect_magnitude(param_1, param_3, param_2);
            itoa(val, buf, 10);
            x = 0x99;
            font_draw_text_ds(buf, x, y);
        }
    }
}

void far combat_arena_draw_tgt_info_panel(void) {
    ItemRecord far *quarrelRec;
    CombatActor *target;
    int dmg;
    int kindIdx;
    char *pStr;
    char buf[30];
    int accuracy;
    int x;
    int y;

    quarrelRec = (ItemRecord far *)0L;
    combat_arena_shootmenu_qrl_cur();
    if (g_nCurrentQuarrelKindIdx != -1) {
        kindIdx = g_nCurrentQuarrelKindIdx;
    } else {
        kindIdx = g_combat_menu_selected_item;
    }
    quarrelRec = combat_actor_qrl_rec_kind(kindIdx);
    combat_arena_shootmenu_init();
    combat_arena_shootmenu_rebuild();
    target = (CombatActor *)combat_actor_terr_under_cur();
    if ((target != (CombatActor *)0x0) && ((target->inner->flags & CAF_DEAD) != 0)) {
        target = (CombatActor *)0x0;
    }
    (g_current_actor)->inner->target = target;
    if ((target != (CombatActor *)0x0) && (combatgrid_tile_has_terr_bit2(target) == 0)) {
        (g_current_actor)->inner->target = target = (CombatActor *)0x0;
    }
    if ((target != (CombatActor *)0x0) && (combatenc_is_encounter_actor(target) == 0)) {
        target = (CombatActor *)0x0;
    }
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    blit_sprite_indirect((unsigned short)*g_parch_bmx, 0x49, 0x81, 0);
    g_graphics_context.bText_fg_color = 0;
    pStr = (char *)"Choose a target";
    x = 0x82 - (font_text_width_ds(pStr) >> 1);
    y = 0x84;
    font_draw_text_ds(pStr, x, y);
    sprintf(buf, "%Fs", quarrelRec);
    if (quarrelRec->wName_split_off != 0) {
        buf[quarrelRec->wName_split_off] = '\0';
        x = 0x82 - (font_text_width_ds(buf) >> 1);
        y += 10;
        font_draw_text_ds(buf, x, y);
        sprintf(buf, "%Fs", (char far *)quarrelRec + (quarrelRec->wName_split_off + 1));
    }
    x = 0x82 - (font_text_width_ds(buf) >> 1);
    y += 10;
    font_draw_text_ds(buf, x, y);
    x = 0x4e;
    y += 12;
    if (target != (CombatActor *)0x0) {
        pStr = (char *)"Accuracy:";
        font_draw_text_ds(pStr, x, y);
        accuracy = combatenc_compute_hit_chance(g_current_actor, target,
                                                stat_actor_get(g_current_actor, 5, 0) +
                                                    combataiturn_armor_eff_stat(g_current_actor),
                                                g_combat_menu_selected_item);
        if (accuracy < 2) {
            accuracy = 2;
        }
        itoa(accuracy, buf, 10);
        x = 0x99;
        font_draw_text_ds(buf, x, y);
        x += font_text_width_ds(buf) + 1;
        font_draw_text_ds("%", x, y);
        pStr = "Damage:";
        x = 0x4e;
        y += 10;
        font_draw_text_ds(pStr, x, y);
        dmg = combat_actor_calc_weapon_damage(g_current_actor, g_combat_menu_selected_item);
        itoa(dmg, buf, 10);
        x = 0x99;
        font_draw_text_ds(buf, x, y);
        return;
    }
    x += 5;
    pStr = (char *)"quarrels remaining";
    itoa(combat_actor_cnt_qrls_kind(g_current_actor, kindIdx), buf, 10);
    font_draw_text_ds(buf, x, y);
    x += font_text_width_ds(buf) + 4;
    font_draw_text_ds(pStr, x, y);
    return;
}

void far combat_arena_hud_melee_panel(void) {
    char numBuf[6];
    char *pStr;
    int hideSwing;
    ItemRecord far *weapon;
    int target;
    int n;
    int y;
    register int x;

    if ((g_current_actor == 0) || !(g_current_actor)->cParty_slot) {
        return;
    }
    g_graphics_context.bClip_enabled = 0;
    target = combat_actor_terr_under_cur();
    blit_sprite_indirect((unsigned short)*g_parch_bmx, 0x49, 0x81, 0);
    if ((combatgrid_actors_ortho_adj(g_current_actor, (CombatActor *)target) != 0) &&
        ((int)stat_actor_get(g_current_actor, 0x10, 0) > 1)) {
        hideSwing = 0;
    } else {
        hideSwing = 1;
    }
    g_graphics_context.bText_fg_color = 0;
    pStr = "Thrust";
    x = 0x53;
    y = 0x86;
    font_draw_text_ds(pStr, x, y);
    g_graphics_context.bGfx_outline_color = 2;
    draw_line(x, y + 0xa, x + 0x5e, y + 0xa);
    g_graphics_context.bGfx_outline_color = 3;
    draw_line(x, y + 0xb, x + 0x5e, y + 0xb);
    if (!hideSwing) {
        pStr = "Swing";
        n = font_text_width_ds(pStr);
        x = 0x73 - n;
        x += 0x3f;
        font_draw_text_ds(pStr, x, y);
    }
    pStr = "Damage";
    n = font_text_width_ds(pStr);
    x = 0x82 - (n >> 1);
    y += 0xf;
    font_draw_text_ds(pStr, x, y);
    weapon = cbstat_find_intact_equip_cat(g_current_actor, 1);
    x = weapon->nSwing_damage + stat_actor_get(g_current_actor, 3, 0);
    x += cbstat_armor_absorption_by_class(g_current_actor, (CombatActor *)target, 0);
    if (x < 1)
        x = 1;
    itoa(x, numBuf, 10);
    x = 0xad - (font_text_width_ds(numBuf) >> 1);
    if (!hideSwing) {
        font_draw_text_ds(numBuf, x, y);
    }
    x = weapon->nThrust_damage + stat_actor_get(g_current_actor, 3, 0);
    x += cbstat_armor_absorption_by_class(g_current_actor, (CombatActor *)target, 1);
    if (x < 1)
        x = 1;
    itoa(x, numBuf, 10);
    x = 0x53;
    font_draw_text_ds(numBuf, x, y);
    pStr = "Accuracy";
    n = font_text_width_ds(pStr);
    x = 0x82 - (n >> 1);
    y += 0xa;
    font_draw_text_ds(pStr, x, y);
    n = stat_actor_get(g_current_actor, 6, 0) + weapon->nDefense_or_range_close;
    if (n < 2)
        n = 2;
    itoa(n, numBuf, 10);
    x = 0xbc - ((font_text_width_ds(numBuf) >> 1) + 0x17);
    if (!hideSwing) {
        font_draw_text_ds(numBuf, x, y);
        x += font_text_width_ds(numBuf) + 1;
        font_draw_text_ds("%", x, y);
    }
    n = stat_actor_get(g_current_actor, 6, 0) + weapon->nAttack_or_range_long;
    if (n < 2)
        n = 2;
    itoa(n, numBuf, 10);
    x = 0x53;
    font_draw_text_ds(numBuf, x, y);
    x += font_text_width_ds(numBuf) + 1;
    font_draw_text_ds("%", x, y);
    pStr = "Left";
    x = 0x53;
    y += 0xc;
    font_draw_text_ds(pStr, x, y);
    if (!hideSwing) {
        pStr = "Right";
        n = font_text_width_ds(pStr);
        x = 0x73 - n;
        x += 0x3f;
        font_draw_text_ds(pStr, x, y);
    }
}

static void far combat_arena_menu_refr_avail(CombatActor *actor) {
    MenuEntry *entry;
    int i;

    i = 0;
    while ((int)g_combat_menu->wEntry_count > i) {
        entry = g_combat_menu->pEntries + i;
        switch (entry->wAction_id) {
        case 0x1f:
            entry->bActive_flag = combatenc_show_missile_stat_row(actor);
            entry->wEnable_gate = (uint)(!entry->bActive_flag);
            break;
        case 0x2e:
            entry->bActive_flag = combatenc_actor_can_cast_spells(actor, 1);
            entry->wEnable_gate = (uint)(!entry->bActive_flag);
            break;
        case 0xe:
            entry->bActive_flag = (combatenc_show_missile_stat_row(actor) == 0) &&
                                  (combatenc_actor_can_cast_spells(actor, 1) == 0);
            entry->wEnable_gate = 1;
            break;
        }
        i++;
    }
    return;
}

static void far combat_arena_redraw_hud_bufs(int draw_world, int draw_stats) {
    int i;

    i = 0;
    do {
        if (draw_world != 0) {
            world_render_with_overlay(MK_FP(0, 0xffff));
        }
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        g_graphics_context.bGfx_fill_enabled = '\x01';
        g_graphics_context.bClip_enabled = '\0';
        menupage_draw_entries(g_combat_menu->pEntries, g_combat_menu->wEntry_count,
                              g_combat_menu->rect.x, g_combat_menu->rect.y);
        if (draw_stats != 0) {
            combat_actor_draw_stats_panel(g_current_actor);
        }
        screen_frame_present();
        i = i + 1;
    } while (i < 2);
    return;
}

static void far combat_arena_gfx_full_unclip(void) {
    g_graphics_context.bClip_enabled = '\0';
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    return;
}

static void far combat_arena_enc_setup_view_v2(void) {
    g_wInCombatMode = 1;
    g_nHorizonRowY = 0;
    g_combat_cancelled = 0;
    combatgrid_build_combatant_list(&g_world_camera->base.pos.xy,
                                    &g_world_camera->base.orientation.pitch);
    world_render_view(0, 0);
    g_lSpriteFogOnsetDist += 1000000;
    combat_arena_mode_enter();
    combatgrid_load_and_init();
    combat_actor_refresh_all_stats();
    combatenc_refr_actor_flags_far();
    menupage_begin(g_combat_menu);
    if (combatgrid_any_terrain_6() != 0) {
        gstate_event_write(0x27, 1);
    }
    return;
}

static void far combat_arena_finalize_round(void) {
    int i;

    menupage_end(g_combat_menu);
    g_lSpriteFogOnsetDist -= 1000000L;
    i = 0;
    if (i < g_combat_count_A) {
        do {
            if ((int)stat_actor_get(&g_combat_actors_A[i], 0, 0) < 1) {
                g_combat_actors_A[i].stats[1].base = '\0';
                g_combat_actors_A[i].stats[0].base = '\x01';
                stat_actor_get(&g_combat_actors_A[i], 0, 0);
            }
            i = i + 1;
        } while (i < g_combat_count_A);
    }
    combat_actor_deploy_encounter();
    combat_arena_remove_flagd_actors();
    combat_arena_mode_exit();
    combatgrid_clear_combatants();
    g_wInCombatMode = 0;
    return;
}

static void far combat_arena_advance_turn(void) {
    if (g_current_actor != 0) {
        combatenc_actor_face_target(g_current_actor);
        (g_current_actor)->inner->flags &= ~CAF_READY;
    }
    combat_arena_redraw_hud_bufs(1, 1);
    do {
        combat_actor_pick_next();
        if (g_current_actor == 0)
            break;
    } while (((g_current_actor)->inner->flags & CAF_DEAD) != 0);
    while (g_current_actor != 0 && combatenc_is_encounter_actor(g_current_actor)) {
        g_picked_actor = g_current_actor;
        combatenc_ai_run_turn();
        combat_actor_pick_next();
    }
    if (g_current_actor == 0) {
        combat_actor_refresh_all_stats();
        combatenc_refr_actor_flags_far();
        while ((combat_actor_pick_next(), combatenc_is_encounter_actor(g_current_actor))) {
            g_picked_actor = g_current_actor;
            combatenc_ai_run_turn();
        }
    }
    if (g_current_actor != 0) {
        combatgrid_build_move_attack_map(g_current_actor);
    }
    return;
}

static int combat_arena_action_is_allowed(int p1, int p2) {
    int result;

    if (g_current_actor == 0)
        return 0;
    if (p2 != 3 && p2 != 4)
        result = (short)g_acting_actor_speed >= p1;
    else
        result = 0;
    return result;
}

static void far combat_arena_switch_active_actor(CombatActor *actor) {
    if (actor != g_current_actor) {
        cbstat_spell_tables_free();
        cspell_subsystem_unload();
        combatenc_anim_actor_stat_rolls(actor);
        screen_frame_present();
        cspell_subsystem_load();
        cbstat_spell_tables_load();
        do {
        } while (combat_arena_wait_confirm_cancel() != 0);
    }
}

static void far combat_arena_wait_confirm_canc_2(CombatActor *target, int quarrel_slot) {
    combat_arena_redraw_hud_bufs(1, 1);
    quarrel_slot = combataiturn_sel_consum_qrl(g_current_actor, quarrel_slot, 1);
    if (quarrel_slot != -1) {
        combataiturn_ranged_attack(g_current_actor, target, quarrel_slot);
    }
    do {
    } while (combat_arena_wait_confirm_cancel() != 0);
}

void combat_arena_actor_set_anim_pose(CombatActor *actor, uchar frame) {
    actor->inner->flags |= CAF_KNOCKBACK;
    actor->inner->knockback_timer = 2;
    actor->inner->knockback_value = frame;
}

void combat_arena_tick_status_timers(void) {
    int i;

    for (i = 0; i < g_combat_count_A; i++) {
        if ((g_combat_actors_A[i].inner->flags & CAF_KNOCKBACK) != 0) {
            g_combat_actors_A[i].inner->knockback_timer--;
            if (!(char)g_combat_actors_A[i].inner->knockback_timer) {
                g_combat_actors_A[i].inner->flags &= ~CAF_KNOCKBACK;
            }
        }
    }
    for (i = 0; i < g_combat_count_B; i++) {
        if ((g_combat_actors_B[i].inner->flags & CAF_KNOCKBACK) != 0) {
            g_combat_actors_B[i].inner->knockback_timer--;
            if (!(char)g_combat_actors_B[i].inner->knockback_timer) {
                g_combat_actors_B[i].inner->flags &= ~CAF_KNOCKBACK;
            }
        }
    }
}

void far combat_arena_swap_tgt_state(void) {
    int tmpCount;
    AnimSlot *tmpAnimPool;
    CombatActor *tmpActors;

    tmpActors = g_pCombatActiveActors;
    tmpCount = g_nCombatActiveCount;
    tmpAnimPool = g_pCombatActiveAnimPool;
    g_pCombatActiveActors = g_pCombatOtherActors;
    g_nCombatActiveCount = g_nCombatOtherCount;
    g_pCombatActiveAnimPool = g_pCombatOtherAnimPool;
    g_pCombatOtherActors = tmpActors;
    g_nCombatOtherCount = tmpCount;
    g_pCombatOtherAnimPool = tmpAnimPool;
    tmpActors = g_picked_actor;
    g_picked_actor = g_current_actor;
    g_current_actor = tmpActors;
}

static int far combat_arena_maybe_random_trap(void) {
    int flag;
    int i;

    flag = 1;
    i = 0;
    if (i < g_nCombatActiveCount) {
        do {
            if ((g_pCombatActiveActors[i].inner->flags & CAF_DEAD) != 0 &&
                g_pCombatActiveActors[i].cParty_slot != 0) {
                flag = 0;
                break;
            }
            i = i + 1;
        } while (i < g_nCombatActiveCount);
    }
    if (flag) {
        flag = RND(100) < 50;
    }
    if (flag && g_traps_loaded_flag != 0) {
        return 1;
    }
    return 0;
}

static void combat_arena_menu_entry_flags(void) {
    MenuEntry *entry;
    int i;

    for (i = 0; i < (int)g_shoot_menu->wEntry_count; i = i + 1) {
        entry = g_shoot_menu->pEntries + i;
        if (g_shoot_menu->pEntries[i].wAction_id != 0x16) {
            entry->bActive_flag = 1;
        }
        if (g_shoot_menu->pEntries[i].wAction_id != 0x21) {
            entry->wEnable_gate = 1;
        } else {
            entry->wEnable_gate = 0;
        }
    }
    return;
}

static void far combat_arena_turn_loop(void) {
    int b_done;
    ushort menu_sel;
    int b_bail;
    int alive_count;
    uint menu_result;

    b_done = 0;
    alive_count = 1;
    b_bail = 0;
    combat_arena_menu_entry_flags();
    combat_actor_draw_stats_panel(g_current_actor);
    menupage_draw_entries(g_shoot_menu->pEntries, g_shoot_menu->wEntry_count, g_shoot_menu->rect.x,
                          g_shoot_menu->rect.y);
    world_render_with_overlay(MK_FP(0, 0xffff));
    screen_frame_present();
    combat_actor_draw_stats_panel(g_current_actor);
    menupage_draw_entries(g_shoot_menu->pEntries, g_shoot_menu->wEntry_count, g_shoot_menu->rect.x,
                          g_shoot_menu->rect.y);
    while (!b_bail && (b_done == 0)) {
        if (!combatenc_alive_actor_count() || !alive_count) {
            b_done = 1;
        } else {
            combat_actor_pick_next();
            while (g_current_actor != (CombatActor *)0x0 &&
                   combatenc_is_encounter_actor(g_current_actor)) {
                g_picked_actor = g_current_actor;
                combatenc_ai_run_turn();
                combat_actor_pick_next();
            }
            if (g_current_actor == (CombatActor *)0x0) {
                combat_arena_swap_tgt_state();
                alive_count = combatenc_alive_actor_count();
                combat_arena_swap_tgt_state();
            }
            while (g_current_actor != (CombatActor *)0x0 &&
                   !combatenc_is_encounter_actor(g_current_actor) && !b_bail) {
                combat_actor_draw_stats_panel(g_current_actor);
                menupage_draw_entries(g_shoot_menu->pEntries, g_shoot_menu->wEntry_count,
                                      g_shoot_menu->rect.x, g_shoot_menu->rect.y);
                world_render_with_overlay(MK_FP(0, 0xffff));
                screen_frame_present();
                combat_actor_draw_stats_panel(g_current_actor);
                menupage_draw_entries(g_shoot_menu->pEntries, g_shoot_menu->wEntry_count,
                                      g_shoot_menu->rect.x, g_shoot_menu->rect.y);
                menu_result = menupage_run(g_shoot_menu, &menu_sel);
                if ((menu_result == 0x21) || (menu_result == 1) ||
                    combat_arena_wait_confirm_cancel()) {
                    b_bail = 1;
                }
                combat_arena_swap_tgt_state();
                combatenc_ai_run_turn();
                alive_count = combatenc_alive_actor_count();
                combat_arena_swap_tgt_state();
                combat_actor_pick_next();
            }
            if (alive_count != 0 && combatenc_alive_actor_count() != 0 &&
                g_current_actor == (CombatActor *)0x0 && !b_bail) {
                combat_actor_refresh_all_stats();
                combatenc_refr_actor_flags_far();
            }
        }
        world_render_with_overlay(MK_FP(0, 0xffff));
        menupage_draw_entries(g_shoot_menu->pEntries, g_shoot_menu->wEntry_count,
                              g_shoot_menu->rect.x, g_shoot_menu->rect.y);
        screen_frame_present();
        menu_result = menupage_run(g_shoot_menu, &menu_sel);
        if ((menu_result == 0x21) || (menu_result == 1) || combat_arena_wait_confirm_cancel()) {
            b_bail = 1;
        }
    }
    do {
    } while (combat_arena_wait_confirm_cancel() != 0);
    return;
}

static int combat_arena_actor_cnt_flags(int flags_mask) {
    int count;
    int i;

    count = 0;
    for (i = 0; i < g_combat_count_B; i = i + 1) {
        if ((flags_mask & (int)(char)g_combat_actors_B[i].inner->flags) != 0) {
            count = count + 1;
        }
    }
    return count;
}

int far combat_arena_cnt_actors_combat(void) {
    int count;

    count = combat_arena_actor_cnt_flags(CAF_DEAD);
    return count;
}

int far combat_arena_cnt_actors_flag_10(void) {
    int count;

    count = combat_arena_actor_cnt_flags(CAF_FLEE);
    return count;
}

static void combat_arena_present(void) {
    g_graphics_context.wGfxBlitDstPage = g_wVgaScratchPageBase;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
    gfx_present_dispatch(0, 0, 0x140, 0x96);
}

static void far combat_arena_view_rstr_disp(int param) {
    g_graphics_context.wGfxBlitSrcPage = g_wVgaScratchPageBase;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    zone_load_scx_image();
    if (param != 0) {
        combat_arena_round_trans_show(0);
    } else {
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        gfx_present_dispatch(13, 11, 296, 102);
        screen_cursor_show_busy();
        world_render_with_overlay(MK_FP(0, 0xffff));
        cspell_gfx_wipe_horizontal_split(13, 11, 296, 102);
        screen_cursor_restore_shape();
    }
}

static uint far combat_arena_pick_target_actor(int requires_action_pred) {
    ushort menuRedraw;
    uint menuResult;
    int done;
    int adjacent;
    CombatActor *target;

    done = 0;
    target = (CombatActor *)0x0;
    while (combat_arena_wait_confirm_cancel() != 0)
        ;
    combat_actor_draw_stats_panel(g_current_actor);
    menupage_draw_entries(g_combat_menu->pEntries, g_combat_menu->wEntry_count,
                          g_combat_menu->rect.x, g_combat_menu->rect.y);
    screen_frame_present();
    combat_actor_draw_stats_panel(g_current_actor);
    menupage_draw_entries(g_combat_menu->pEntries, g_combat_menu->wEntry_count,
                          g_combat_menu->rect.x, g_combat_menu->rect.y);
    screen_frame_present();
    while (!done) {
        combatgrid_cur_tile_world();
        menuResult = menupage_run(g_combat_menu, &menuRedraw);
        target = (CombatActor *)combat_actor_terr_under_cur();
        if (requires_action_pred != 0) {
            adjacent = combatgrid_actors_ortho_adj(g_current_actor, target);
        } else {
            adjacent = 1;
        }
        if (adjacent == 0 || combatenc_is_encounter_actor(target) == 0) {
            target = (CombatActor *)0x0;
        }
        if (target != (CombatActor *)0x0) {
            world_render_with_overlay(MK_FP(0, 4));
        } else {
            world_render_with_overlay(MK_FP(0, 0xffff));
        }
        combat_arena_draw_tgt_info_hud((CombatActor *)0x0, -1, 0, 0);
        screen_frame_present();
        if (((combat_arena_wait_confirm_cancel() != 0) &&
             ((target != (CombatActor *)0x0 || (0x8c < g_cursor_tile_y)))) ||
            (menuResult == 1)) {
            done = 1;
        }
    }
    return (uint)target;
}

void far combat_arena_resume_dispatch(int command_id, int *p_spell_result, int *out_spell_result) {
    Actor far *inv;
    CombatActor *target;

    inv = (g_current_actor)->actor_record;

    switch (command_id) {
    case 0x0c:
        target = (CombatActor *)combat_arena_pick_target_actor(0);
        if (target != 0)
            combat_arena_actor_die(target, 1);
        else
            return;
    shared_tail:
        itemtbl_inv_consume_one_by_kind(inv, command_id);
        return;
    case 0x02:
        if (g_game_mode != 2) {
            target = (CombatActor *)combat_arena_pick_target_actor(0);
            if (target != 0)
                cspell_resolve_cast(g_current_actor, target, 5, -9);
            else
                return;
            goto shared_tail;
        }
        audio_play(0x13);
        return;
    case 0x04:
        target = (CombatActor *)combat_arena_pick_target_actor(0);
        if (target != 0)
            cspell_resolve_cast(g_current_actor, target, 4, -0x1e);
        else
            return;
        goto shared_tail;
    case 0x0f:
        target = (CombatActor *)combat_arena_pick_target_actor(0);
        if (target == 0)
            return;
        if (RND(100) < 0x1e)
            cspell_resolve_cast(g_current_actor, g_current_actor, 0x16, -0xf);
        else
            cspell_resolve_cast(g_current_actor, target, 0x16, -0xf);
        goto shared_tail;
    case 0x34:
        audio_play(0x4b);
        combatenc_apply_flee_tile_team(0x30);
        goto shared_tail;
    case 0x0b:
        audio_play(0x4c);
        cspell_summon_monster(0x2e, 1);
        do {
        } while (combat_arena_wait_confirm_cancel() != 0);
        cspell_summon_monster(0x2e, 1);
        goto shared_tail;
    case 0x09:
        cspell_summon_monster(0x38, 1);
        goto shared_tail;
    case 0x33:
        target = (CombatActor *)combat_arena_pick_target_actor(1);
        if (target != 0)
            cspell_resolve_cast(g_current_actor, target, 0xd, -0x10);
        else
            return;
        goto shared_tail;
    case 0x32:
        target = (CombatActor *)combat_arena_pick_target_actor(1);
        if (target != 0)
            combatenc_actor_flee_tile_east(target);
        else
            return;
        goto shared_tail;
    case 0x0d:
        if (combatenc_actor_can_cast_spells(g_current_actor, 1) == 0)
            return;
        combat_arena_present();
        *p_spell_result = cspell_cast_menu_loop(g_current_actor, out_spell_result, 0, 0);
        combat_arena_view_rstr_disp(0);
        if (*p_spell_result == -1)
            return;
        g_bStormAmplify = 1;
        goto shared_tail;
    }
}

void far combat_arena_suspend_char_screen(CombatActor *actor, int *p_spell_result,
                                          int *out_spell_result) {
    int cmdId;
    CombatActorInner *savedInner;
    int i;

    g_dwDialogInputCooldown = 0;
    combat_arena_present();
    combat_arena_gfx_full_unclip();
    cbstat_spell_tables_free();
    cspell_subsystem_unload();
    i = 0;
    if (i < g_combat_count_A) {
        do {
            if (g_combat_actors_A[i].cParty_slot != '\0') {
                *(CombatActor
                  far *)&g_gameState.party_members[(signed char)g_gameState.party_roster[i]] =
                    g_combat_actors_A[i];
                ((CombatActor
                  far *)&g_gameState.party_members[(signed char)g_gameState.party_roster[i]])
                    ->inner = (CombatActorInner *)0;
            }
            i = i + 1;
        } while (i < g_combat_count_A);
    }
    if (menupage_state_0e7c() == 2 || key_is_down(0x2a) || key_is_down(0x36)) {
        charscreen_info_loop(actor);
    } else {

        cmdId =
            cmbinv_inventory_screen_run(actor->actor_record, gstate_find_party_slot(actor) + 1, 0);
    }
    i = 0;
    if (i < g_combat_count_A) {
        do {
            if (g_combat_actors_A[i].cParty_slot != '\0') {
                savedInner = g_combat_actors_A[i].inner;
                g_combat_actors_A[i] =
                    *(CombatActor
                      far *)&g_gameState.party_members[(signed char)g_gameState.party_roster[i]];
                g_combat_actors_A[i].inner = savedInner;
            }
            i = i + 1;
        } while (i < g_combat_count_A);
    }
    cspell_subsystem_load();
    cbstat_spell_tables_load();
    combat_arena_view_rstr_disp(1);
    combat_arena_resume_dispatch(cmdId, p_spell_result, out_spell_result);
    return;
}

int combat_arena_dist_actors_by_id(int actor_id_a, int actor_id_b) {
    CombatActorInner *actor_a_ptr;
    CombatActorInner *actor_b_ptr;
    int i;
    int dist;

    actor_a_ptr = 0;
    actor_b_ptr = 0;
    actor_id_b = (&g_gameState.party_count)[actor_id_b] + 1;
    if (actor_id_a != 0) {
        actor_id_a = (&g_gameState.party_count)[actor_id_a] + 1;
    } else {
        actor_id_a = -1;
    }
    for (i = 0; i < g_combat_count_A; i = i + 1) {
        if (g_combat_actors_A[i].cParty_slot == actor_id_a) {
            actor_a_ptr = g_combat_actors_A[i].inner;
        } else if ((int)g_combat_actors_A[i].cParty_slot == actor_id_b) {
            actor_b_ptr = g_combat_actors_A[i].inner;
        }
    }
    if (actor_id_a == -1) {
        if (g_current_actor->inner == actor_b_ptr) {
            return 0;
        }
        return 1000;
    }
    if (actor_a_ptr != 0 && actor_b_ptr != 0) {
        dist = combatgrid_chebyshev_distance(actor_a_ptr->grid_x, actor_a_ptr->grid_y,
                                             actor_b_ptr->grid_x, actor_b_ptr->grid_y);
    } else {
        dist = 1000;
    }
    return dist;
}

void far combat_arena_show_message_by_id(int message_id, unsigned short *p_menu, int *p_param3,
                                         int *p_param4, int *p_param5, int *p_spell_result,
                                         int *p_spell_out, int *p_param8, MenuPage **p_menu_slot,
                                         int *p_param10, int *p_param11) {
    uint is_preview;

    if (message_id != 0) {
        is_preview = (uint)(menupage_state_0e7c() == 2);
    }
    switch (message_id) {
    case 2:
        if (is_preview != 0) {
            dialog_play_record(0xfe, 1);
            return;
        }
        (g_current_actor)->inner->pad_e[4] = (uchar)(*p_menu = 0);
        return;
    case 3:
        if (is_preview != 0) {
            dialog_play_record(0xff, 1);
            return;
        }
        (g_current_actor)->inner->pad_e[4] = (uchar)(*p_menu = 1);
        return;
    case 4:
        if (is_preview != 0) {
            dialog_play_record(0x100, 1);
            return;
        }
        (g_current_actor)->inner->pad_e[4] = (uchar)(*p_menu = 2);
        return;
    case 5:
        if (is_preview != 0) {
            dialog_play_record(0x101, 1);
            return;
        }
        (g_current_actor)->inner->pad_e[4] = (uchar)(*p_menu = 3);
        return;
    case 6:
        if (is_preview != 0) {
            dialog_play_record(0x102, 1);
            return;
        }
        (g_current_actor)->inner->pad_e[4] = (uchar)(*p_menu = 4);
        return;
    case 8:
        if (is_preview != 0) {
            dialog_play_record(0x103, 1);
            return;
        }
        (g_current_actor)->inner->pad_e[4] = (uchar)(*p_menu = 5);
        return;
    case 9:
        if (is_preview != 0) {
            dialog_play_record(0x104, 1);
            return;
        }
        (g_current_actor)->inner->pad_e[4] = (uchar)(*p_menu = 6);
        return;
    case 7:
        if (is_preview != 0) {
            dialog_play_record(0x105, 1);
            return;
        }
        (g_current_actor)->inner->pad_e[4] = (uchar)(*p_menu = 7);
        return;
    case 50:
        if (is_preview != 0) {
            dialog_play_record(0x106, 1);
            return;
        }
        g_combat_menu_current_page = (g_combat_menu_current_page == 1) ? 2 : 1;
        return;
    case 19:
        if (is_preview != 0) {
            dialog_play_record(0x107, 1);
            return;
        }
        combatenc_actor_enter_defense(g_current_actor);
        return;
    case 31:
        if (is_preview != 0) {
            dialog_play_record(0x108, 1);
            return;
        }
        if (combatenc_show_missile_stat_row(g_current_actor) == 0) {
            return;
        }
        *p_param4 = 4;
        *p_menu_slot = g_shoot_menu;
        combat_arena_shootmenu_rebuild();
        combat_arena_menu_sync_sel_actor(g_current_actor);
        *p_param10 = 2;
        return;
    case 46:
        if (is_preview != 0) {
            dialog_play_record(0x109, 1);
            return;
        }
        if (combatenc_actor_can_cast_spells(g_current_actor, 1) == 0) {
            return;
        }
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        combat_arena_gfx_full_unclip();
        combat_arena_present();
        *p_spell_result = cspell_cast_menu_loop(g_current_actor, p_spell_out, (int *)0, (int *)0);
        combat_arena_view_rstr_disp(0);
        if (*p_spell_result != -1) {
            *p_param4 = 4;
            *p_param10 = 2;
            return;
        }
        *p_param5 = -1;
        *p_param4 = 1;
        *p_param10 = 2;
        return;
    case 32:
        if (is_preview != 0) {
            dialog_play_record(0x10a, 1);
            return;
        }
        combatenc_set_flag8_clear_flag1(g_current_actor);
        *p_param3 = 1;
        return;
    case 47:
        if (is_preview != 0) {
            dialog_play_record(0x10b, 1);
            return;
        }
        *p_param4 = 3;
        return;
    case 30:
        if (is_preview != 0) {
            dialog_play_record(0x10c, 1);
            return;
        }
        if (combatgrid_any_terrain_6() != 0) {
            return;
        }
        combat_arena_turn_loop();
        *p_param3 = 1;
        return;
    case 33:
        if (is_preview != 0) {
            dialog_play_record(0x10d, 1);
            return;
        }
        if (*p_menu_slot == g_shoot_menu) {
            *p_menu_slot = g_combat_menu;
            *p_param4 = -1;
            *p_param5 = 1;
            *p_param10 = 2;
            return;
        }
        g_gameState.nEvtArgActor0 = (g_current_actor)->cParty_slot - 1;
        if (combat_arena_maybe_random_trap() != 0) {
            combat_arena_redraw_hud_bufs(1, 1);
            dialog_play_record(0x22, 0);
            *p_param8 = 1;
            *p_param4 = -1;
            g_combat_cancelled = 1;
            return;
        }
        combat_arena_swap_tgt_state();
        if (combatenc_alive_actor_count() != g_nCombatOtherCount) {
            dialog_play_record(0x23, 0);
        } else {
            dialog_play_record(0x12f, 0);
        }
        combat_arena_swap_tgt_state();
        (g_current_actor)->inner->flags &= ~CAF_READY;
        *p_param3 = 1;
        return;
    case 22:
        if (is_preview == 0) {
            *p_spell_result = -1;
        }
        combat_arena_suspend_char_screen(g_current_actor, p_spell_result, p_spell_out);
        combat_arena_redraw_hud_bufs(1, 1);
        *p_param10 = 2;
        if (*p_spell_result != -1) {
            *p_param4 = 4;
            return;
        }
        if (is_preview != 0) {
            return;
        }
        (g_current_actor)->inner->flags &= ~CAF_READY;
        *p_param3 = 1;
        return;
    case 16:
        if (key_is_down(0x1d) == 0) {
            return;
        }
        if (dialog_play_record(0x14b, 0) == 0) {
            combat_actor_kill_remaining_enc();
            *p_param8 = 1;
            *p_param11 = 3;
            g_combat_cancelled = 1;
            return;
        }
        return;
    case 1:
        if (*p_spell_result != -1) {
            *p_spell_result = -1;
            *p_param4 = -1;
            *p_param5 = -1;
            *p_param10 = 2;
        }
        return;
    case 34:
        g_bCombatGridLinesEnabled ^= 1;
    default:
        return;
    }
}

CombatActor *combat_arena_disp_spell_action(int *param_1, int *param_2, int *param_3, int param_4,
                                            int *param_5, int *param_6) {
    int tile_blocked;
    int invalid;
    CombatActor *actor;
    GridCombatant *combatant;

    invalid = 0;
    actor = (CombatActor *)combat_actor_terr_under_cur();
    if ((*param_3 == 1 ||
         (*param_3 == 2 &&
          combatgrid_is_pure_diagonal(g_current_actor, g_cursor_tile_x, g_cursor_tile_y) != 0)) &&
        combatgrid_tile_terrain_field((char)g_cursor_tile_x, (char)g_cursor_tile_y) == 5) {
        tile_blocked = 0;
    } else {
        tile_blocked = combat_actor_cur_tile_block();
    }
    *param_3 = combat_actor_cursor_distance(g_current_actor);
    *param_2 = combat_arena_action_is_allowed(*param_3, *param_1);
    if ((*param_2 == 0) && (*param_1 != 3) && (*param_1 != 4)) {
        invalid = 1;
    }
    if (*param_1 == 4) {
        if (combatenc_show_missile_stat_row(g_current_actor) == 0) {
            if (g_cursor_tile_x >= 0 && g_cursor_tile_x <= 8 && g_cursor_tile_y >= 0 &&
                g_cursor_tile_y <= 0xd) {
                switch ((unsigned int)cspell_record_field8(param_4)) {
                default:
                    goto validate_common;
                case 2:
                case 3:
                    if (actor == (CombatActor *)0x0 || !(int)(actor->cParty_slot) ||
                        tile_blocked != 0 || (actor->inner->flags & CAF_DEAD) ||
                        (actor->inner->flags & CAF_AI_SUMMON))
                        break;
                    goto validate_common;
                case 0:
                    if (actor == (CombatActor *)0x0 || !combatenc_is_encounter_actor(actor) ||
                        !combatgrid_tile_has_terr_bit2(actor) || (actor->inner->flags & CAF_DEAD))
                        break;
                    goto validate_common;
                case 1:
                case 4:
                    if (actor == (CombatActor *)0x0 || !combatenc_is_encounter_actor(actor) ||
                        tile_blocked != 0 || (actor->inner->flags & CAF_DEAD))
                        break;
                    goto validate_common;
                case 7:
                    actor = (CombatActor *)combat_actor_encounter_at_tile(g_cursor_tile_x,
                                                                          g_cursor_tile_y);
                    if (actor == (CombatActor *)0x0 ||
                        !((int)(char)(actor->inner->flags) & CAF_DEAD))
                        break;
                    goto validate_common;
                case 8:
                    combatant = combatgrid_find_cmbt_at_tile((uchar)g_cursor_tile_x,
                                                             (uchar)g_cursor_tile_y);
                    if (combatant == (GridCombatant *)0x0 ||
                        (combatant->paged_id != 7 && combatant->paged_id != 8))
                        break;
                    goto validate_common;
                case 5:
                case 6:
                    if (combatgrid_tile_is_blocked((uchar)g_cursor_tile_x, (uchar)g_cursor_tile_y))
                        break;
                    goto validate_common;
                }
            }
        } else {
            if (actor != (CombatActor *)0x0 && (actor->inner->flags & CAF_DEAD) != 0) {
                actor = (CombatActor *)0x0;
            }
            if (combatgrid_tile_has_terr_bit2(actor) != 0 &&
                combatenc_is_encounter_actor(actor) != 0 &&
                combataiturn_sel_consum_qrl(g_current_actor, g_combat_menu_selected_item, 0) != -1)
                goto validate_common;
        }
        invalid = 1;
    }
validate_common:
    if ((*param_1 != 3) && (*param_1 != 4) &&
        ((actor != (CombatActor *)0x0 && combatenc_is_encounter_actor(actor) == 0) ||
         (actor == g_current_actor || tile_blocked != 0) ||
         (actor != (CombatActor *)0x0 &&
          combat_actor_step_to_tgt_adj(g_current_actor, actor) == 0))) {
        invalid = 1;
    }
    if (invalid) {
        *param_2 = 0;
        if (*param_1 == 4) {
            *param_3 = 1000;
            if (*param_5 == 4) {
                *param_6 = 2;
            } else {
                *param_5 = 4;
            }
        }
        *param_1 = -1;
    }
    do {
        ;
    } while (kbhit_read() >> 8);
    return actor;
}

void far combat_arena_turn_actor_inact(uint *p_far_offset, int *p_turn_done, int *p_hud_state,
                                       int *p_ai_flag) {
    *p_far_offset = 0xffff;
    combat_arena_advance_turn();
    if ((combatgrid_any_terrain_6() != 0 && combatgrid_actor_past_terr6_row() != 0 &&
         combatenc_alive_actor_count() == 0) ||
        (combatenc_alive_actor_count() == 0 && combatgrid_any_terrain_6() == 0) ||
        g_current_actor == 0) {
        *p_turn_done = 1;
    }
    screen_cur_refr_during_long_op();
    combat_arena_menu_refr_avail(g_current_actor);
    combat_arena_redraw_hud_bufs(1, 1);
    *p_hud_state = 2;
    if (((g_current_actor)->inner->flags & CAF_AI_SUMMON) != 0) {
        combat_arena_swap_tgt_state();
        combatenc_ai_run_turn();
        combat_arena_swap_tgt_state();
    } else {
        *p_ai_flag = 0;
    }
    return;
}

void far combat_arena_resolve_menu_action(int *p_state_a, int *p_move_cost, int *p_state_b,
                                          int b_input_locked, int b_input_gate, int *p_dirty_hud,
                                          CombatActor **pp_cursor_target, int arg8,
                                          int spell_record_id, int arg10, MenuPage **pp_menu_slot) {
    int tmp;
    int confirmCancel;
    int switchMenu;

    switch (*p_state_a) {
    case 3:

        if (*p_move_cost == 1000) {
            *p_state_b = 3;
            *p_state_a = -1;
        } else {
            if (combat_arena_wait_confirm_cancel() != 0) {
                if (b_input_locked == 0) {
                    *pp_cursor_target = (CombatActor *)combat_actor_terr_under_cur();
                    if (*pp_cursor_target != (CombatActor *)0x0) {
                        if (combatenc_is_encounter_actor(*pp_cursor_target) != 0) {
                            (g_current_actor)->inner->flags &= ~CAF_READY;
                            *p_state_a = (*p_state_b = -1);
                            *p_dirty_hud = 2;
                            combat_arena_switch_active_actor(*pp_cursor_target);
                        }
                    }
                }
            }
        }
        break;
    case -1:
    case 0:
    case 1:

        if (b_input_gate != 0) {
            if (*pp_cursor_target == (CombatActor *)0x0) {
                if (combatgrid_cursor_tile_movable() != 0) {
                    combat_actor_face_cursor();
                    *p_state_a = 1;
                    if (*p_state_b != 1) {
                        *p_dirty_hud = 2;
                    }
                    if (combat_arena_wait_confirm_cancel() != 0) {
                        if (b_input_locked == 0) {
                            if (screen_cursor_get_y() < 0x8c) {
                                (g_current_actor)->inner->target = (CombatActor *)0x0;
                                combat_actor_move_to_cursor(g_current_actor);
                                combatenc_actor_face_target(g_current_actor);
                                (g_current_actor)->inner->flags &= ~CAF_READY;
                                *p_dirty_hud = 2;
                            }
                        }
                    }
                } else {
                    *p_state_a = -1;
                }
            } else {
                if ((int)g_acting_actor_speed >= *p_move_cost) {
                    combat_actor_face_cursor();
                    *p_state_a = 0;
                    if (*p_state_b != 0) {
                        *p_dirty_hud = 2;
                    }
                    confirmCancel = combat_arena_wait_confirm_cancel();
                    if (confirmCancel == 1 && b_input_locked == 0) {
                        combat_arena_redraw_hud_bufs(1, 1);
                        if (combat_actor_melee_approach(g_current_actor, *pp_cursor_target) != 0) {
                            if (((tmp = (int)(char)((g_current_actor)->inner->flags)) & CAF_DEAD) !=
                                0)
                                goto check_defend;
                            *p_state_a = -1;
                            combat_arena_resolve_melee_swing(g_current_actor, *pp_cursor_target, 0);
                            *p_dirty_hud = 2;
                            do {
                            } while (combat_arena_wait_confirm_cancel() != 0);
                        }
                    } else if (confirmCancel == 2) {
                        if (combatgrid_actors_ortho_adj(g_current_actor, *pp_cursor_target) != 0) {
                            if ((int)stat_actor_get(g_current_actor, 0x10, 4) > 1) {
                                (g_current_actor)->inner->flags &= ~CAF_READY;
                                *p_state_a = -1;
                                combat_arena_melee_attack(g_current_actor, *pp_cursor_target, 0);
                                *p_dirty_hud = 2;
                                do {
                                } while (combat_arena_wait_confirm_cancel() != 0);
                            }
                        }
                    }
                } else {
                    *p_state_a = -1;
                }
            }
        }
    check_defend:
        if (*pp_cursor_target == g_current_actor) {
            confirmCancel = combat_arena_wait_confirm_cancel();
            if (confirmCancel == 2) {
                combatenc_set_flag8_clear_flag1(*pp_cursor_target);
                (g_current_actor)->inner->flags &= ~CAF_READY;
                *p_dirty_hud = 2;
                do {
                } while (combat_arena_wait_confirm_cancel() != 0);
            } else if (confirmCancel == 1) {
                if (combat_actor_stat_percent(*pp_cursor_target, 1) >= 0x50) {
                    combatenc_set_flag8_clear_flag1(*pp_cursor_target);
                } else {
                    combatenc_actor_enter_defense(*pp_cursor_target);
                }
                *pp_menu_slot = g_combat_menu;
                (g_current_actor)->inner->flags &= ~CAF_READY;
                *p_dirty_hud = 2;
                do {
                } while (combat_arena_wait_confirm_cancel() != 0);
            }
        }
        break;
    case 4:

        combat_actor_face_cursor();
        if (*pp_cursor_target != (CombatActor *)0x0) {
            (g_current_actor)->inner->target = *pp_cursor_target;
        }
        tmp = combatenc_show_missile_stat_row(g_current_actor);
        if (combat_arena_wait_confirm_cancel() != 0 && *p_move_cost != 1000 &&
            screen_cursor_get_y() < 0x8c) {
            if (*pp_cursor_target != (CombatActor *)0x0 ||
                (tmp == 0 && cspell_record_field8(spell_record_id) == 8)) {
                if (tmp != 0) {
                    combat_arena_wait_confirm_canc_2(*pp_cursor_target, arg8);
                    switchMenu = 1;
                } else {
                    cspell_resolve_cast(g_current_actor, *pp_cursor_target, spell_record_id, arg10);
                }
                (g_current_actor)->inner->flags &= ~CAF_READY;
                *p_state_a = -1;
            } else if ((tmp == 0 && cspell_record_field8(spell_record_id) == 5) ||
                       cspell_record_field8(spell_record_id) == 6) {
                cspell_resolve_cast(g_current_actor, (CombatActor *)0x0, spell_record_id, arg10);
                (g_current_actor)->inner->flags &= ~CAF_READY;
            } else {
                *p_state_a = 1;
                *p_state_b = -1;
                *p_move_cost = combat_actor_cursor_distance(g_current_actor);
                *p_dirty_hud = 2;
                switchMenu = 1;
            }
            if (switchMenu != 0)
                *pp_menu_slot = g_combat_menu;
        }
        if (*pp_cursor_target != (CombatActor *)0x0 &&
            combatenc_is_encounter_actor(*pp_cursor_target) != 0) {
            *p_dirty_hud = 2;
        }
    }
    if (*p_move_cost != 1000) {
        *p_state_b = *p_state_a;
    }
    return;
}

void far combat_arena_actor_turn_loop(int encounter_id, int *p_status, int b_has_fired) {
    CombatActor *cursorTarget;
    MenuPage *menu;
    int hudState;
    ushort menuConsumed;
    uint menuResult;
    int done;
    int allowed;
    int moveDist;
    uint stateA;
    uint stateB;
    int turnInact;
    int spellRecId;
    int castArg;
    int allPartyDown;
    short prevTileX;
    short prevTileY;
    int i;
    int flags;
    int menu_redraw;

    hudState = 2;
    done = 0;
    stateA = 1;
    stateB = 1;
    turnInact = 0;
    spellRecId = -1;
    *p_status = -1;
    g_encounter_id = encounter_id;
    screen_cursor_show_busy();
    combat_arena_enc_setup_view_v2();
    screen_cursor_restore_shape();
    dialog_input_wait_with_cooldown(1);
    menu = g_combat_menu;
    g_combat_menu_selected_item = 0;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    world_render_with_overlay((void far *)0xffff);
    g_current_actor = 0;
    combat_actor_pick_next();
    combat_arena_round_trans_show(1);
    while (combatenc_is_encounter_actor(g_current_actor) != 0) {
        if (b_has_fired == 0) {
            g_picked_actor = g_current_actor;
            combatenc_ai_run_turn();
        } else {
            (g_current_actor)->inner->flags &= ~CAF_READY;
        }
        combat_actor_pick_next();
    }
    g_acting_actor = g_current_actor;
    combatgrid_build_move_attack_map(g_current_actor);
    combat_arena_menu_refr_avail(g_current_actor);
    combat_arena_redraw_hud_bufs(1, 1);
    while (done == 0) {
        prevTileX = g_cursor_tile_x;
        prevTileY = g_cursor_tile_y;
        combatgrid_cur_tile_world();
        menuResult = menupage_run(menu, &menuConsumed);
        if (menuConsumed != 0) {
            menu_redraw = 2;
        }
        if (((flags = (char)(g_current_actor)->inner->flags) & CAF_READY) == 0) {
            turnInact = 1;
        }
        combat_arena_show_message_by_id(menuResult, &g_combat_menu_selected_item, &turnInact,
                                        (int *)&stateA, (int *)&stateB, &spellRecId, &castArg,
                                        &done, &menu, &hudState, p_status);
        if (turnInact != 0) {
            combat_arena_turn_actor_inact(&stateA, &done, &hudState, &turnInact);
            spellRecId = -1;
            castArg = -1;
            stateA = stateB = 0xffff;
            while (combat_arena_wait_confirm_cancel() != 0) {
                world_render_with_overlay((void far *)0xffff);
                screen_frame_present();
            }
        }
        cursorTarget = combat_arena_disp_spell_action((int *)&stateA, &allowed, &moveDist,
                                                      spellRecId, (int *)&stateB, &hudState);
        combat_arena_resolve_menu_action((int *)&stateA, &moveDist, (int *)&stateB, menuResult,
                                         allowed, &hudState, &cursorTarget,
                                         g_combat_menu_selected_item, spellRecId, castArg, &menu);
        if (g_combat_cancelled == 0) {
            world_render_with_overlay(MK_FP(0, stateA));
        }
        if ((prevTileX != g_cursor_tile_x) || (prevTileY != g_cursor_tile_y)) {
            hudState = 2;
        }
        if (((hudState != 0) || (menu_redraw != 0)) && (stateA != 0)) {
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            g_graphics_context.bGfx_fill_enabled = '\x01';
            g_graphics_context.bClip_enabled = '\0';
            if ((hudState != 0) && (done == 0)) {
                if (menu == g_shoot_menu) {
                    combat_arena_draw_tgt_info_panel();
                } else {
                    if ((combatgrid_tile_terrain_field((char)g_cursor_tile_x,
                                                       (char)g_cursor_tile_y) == 5) &&
                        (combatgrid_cursor_tile_movable() != 0)) {
                        combat_actor_show_push_prompt();
                        hudState++;
                    } else if (spellRecId != -1) {
                        combat_arena_draw_tgt_info_hud(cursorTarget, spellRecId, castArg, stateA);
                    } else {
                        combat_actor_draw_stats_panel(g_current_actor);
                    }
                }
                menupage_draw_entries(menu->pEntries, menu->wEntry_count, menu->rect.x,
                                      menu->rect.y);
                hudState--;
            } else {
                menupage_draw_entries(menu->pEntries, menu->wEntry_count, menu->rect.x,
                                      menu->rect.y);
                menu_redraw--;
            }
        }
        if ((done == 0) && (stateA == 0)) {
            combat_arena_hud_melee_panel();
            hudState = 2;
        }
        if (moveDist == 1000) {
            stateA = stateB;
        }
        screen_frame_present();
    }
    allPartyDown = 1;
    i = 0;
    if (i < g_combat_count_A) {
        do {
            if (((g_combat_actors_A[i].cParty_slot != '\0') &&
                 (((flags = (char)(g_combat_actors_A[i].inner)->flags) & CAF_DEAD) == 0)) &&
                (combatenc_actor_can_act(&g_combat_actors_A[i], 0) != 0)) {
                allPartyDown = 0;
            }
            i = i + 1;
        } while (i < g_combat_count_A);
    }
    if (allPartyDown) {
        if (*p_status == 3)
            goto LAB_600f_3c8d;
        *p_status = 0;
        g_gameState.nEvtArgActor0 = g_acting_actor->cParty_slot + -1;
        if (combatgrid_any_terrain_6() != 0) {
            dialog_play_record(0x6b, 0);
        } else {
            dialog_play_record(0x21, 0);
        }
    } else {
        if (g_combat_cancelled != 0) {
            *p_status = 2;
            goto LAB_600f_3c8d;
        }
        *p_status = 1;
        if (g_encounter_id != 0x221) {
            g_gameState.nEvtArgActor0 = g_acting_actor->cParty_slot + -1;
            combat_arena_swap_tgt_state();
            if (combatenc_count_active_enemies() != 0) {
                i = 0;
                if (i < g_combat_count_A) {
                    do {
                        if ((g_combat_actors_A[i].cParty_slot != '\0') &&
                            (((g_combat_actors_A[i].inner)->flags & CAF_DEAD) != 0)) {
                            g_acting_actor = &g_combat_actors_A[i];
                        }
                        i = i + 1;
                    } while (i < g_combat_count_A);
                }
                g_gameState.nEvtArgActor0 = g_acting_actor->cParty_slot + -1;
                i = 0;
                if (i < g_combat_count_A) {
                    do {
                        if ((g_combat_actors_A[i].cParty_slot != '\0') &&
                            (((flags = (char)(g_combat_actors_A[i].inner)->flags) & CAF_DEAD) ==
                             0)) {
                            g_acting_actor = &g_combat_actors_A[i];
                            break;
                        }
                        i = i + 1;
                    } while (i < g_combat_count_A);
                }
                g_gameState.nEvtArgActor1 = g_acting_actor->cParty_slot + -1;
                dialog_play_record(0x83, 0);
            } else {
                combat_arena_swap_tgt_state();
                if (combatenc_count_active_enemies() > 1) {
                    if (combat_arena_all_targets_immune() == 0) {
                        if (hotspotevt_monst_dispatch_by_tag((long)(short)g_encounter_id) == 0) {
                            dialog_play_record(0x20, 0);
                        } else {
                            dialog_play_record(0x142, 0);
                        }
                    } else {
                        dialog_play_record(0x131, 0);
                    }
                } else {
                    if (combatenc_count_active_enemies() != 0) {
                        if (combat_arena_all_targets_immune() == 0) {
                            dialog_play_record(0x81, 0);
                        } else {
                            dialog_play_record(0x132, 0);
                        }
                    } else {
                        if (combatgrid_any_terrain_6() != 0) {
                            dialog_play_record(0x1f, 0);
                        } else {
                            dialog_play_record(0x82, 0);
                        }
                    }
                }
            }
        } else {
            dialog_play_record(0x150, 0);
        }
    }
LAB_600f_3c8d:
    combat_arena_redraw_hud_bufs(0, 1);
    combat_arena_finalize_round();
    if ((g_encounter_id != 0x221) && (*p_status != 3)) {
        dialog_input_wait_with_cooldown(1);
    }
    return;
}
