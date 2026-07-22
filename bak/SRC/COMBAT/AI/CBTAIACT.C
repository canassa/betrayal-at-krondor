#include <dos.h>
#include <stdlib.h>

#include "globals.h"
#include "structs.h"
#include "SRC/COMBAT/AI/CBTAIACT.H"
#include "SRC/SYS/RAND.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/R3D/FX/WORLDFX.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "SRC/COMBAT/AI/CMBTAI.H"
#include "SRC/COMBAT/AI/CBTAI.H"
#include "SRC/COMBAT/AI/CBTAITRN.H"
#include "SRC/COMBAT/SPELL/CSPELL.H"
#include "SRC/COMBAT/STATS/CBSTAT.H"
#include "defines.h"

void far combataiact_pick_melee_or_missl(CombatActor *actor) {
    CombatActor *target;
    int distance;

    target = combatenc_find_nearest_actor(actor, &distance);
    if (distance <= 1) {
        combat_arena_melee_attack(actor, target, RNDR(0x19, 0x31));
    } else {
        if (RND(10) >= (unsigned int)distance) {
            combat_ai_actor_cast_spell(actor, target, 4);
        } else {
            combataiturn_ranged_attack(actor, target, 8);
        }
    }
}

void far combataiact_random_move_attack(CombatActor *actor) {
    CombatActor *target;
    unsigned int roll;
    int distance;
    int halfStat;

    g_cursor_tile_x = RND2(8);
    g_cursor_tile_y = RND(0xd);
    combatgrid_build_move_attack_map(actor);
    while (!combatgrid_cursor_tile_movable()) {
        g_cursor_tile_x = RND2(8);
        g_cursor_tile_y = RND(0xd);
    }
    actor->inner->pad_6[0] = (unsigned char)g_cursor_tile_x;
    actor->inner->pad_6[1] = (unsigned char)g_cursor_tile_y;
    combataipath_actor_walk_path(actor, 0);
    roll = RND(100);
    halfStat = (int)stat_actor_get(actor, 0, 0) >> 1;
    target = combatenc_find_nearest_actor(actor, &distance);
    if (distance <= 1) {
        combat_arena_melee_attack(actor, target, RNDR(0x19, 0x31));
    } else {
        if (!((halfStat != 1) && (distance >= 2) && ((int)roll < 0x50) &&
              (combat_actor_trace_proj_path(actor, target, 1) != 0))) {
            combatenc_actor_enter_defense(actor);
            if (0x32 < (int)roll) {
                combatenc_set_flag8_clear_flag1(actor);
            }
        } else {
            if ((int)roll < 0x32) {
                cspell_resolve_cast(actor, target, 5, halfStat);
            } else {
                cspell_resolve_cast(actor, target, 4, halfStat);
            }
            return;
        }
    }
    return;
}

void far combataiact_ranged_attack_turn(CombatActor *actor) {
    CombatActor *target;
    int distance;
    int hit;
    unsigned short actionId;
    int knockback;
    int cspell_slot;

    hit = 1;
    target = combatenc_find_nearest_actor(actor, &distance);
    if ((combat_actor_trace_proj_path(actor, target, 1) == 0) || (RND(100) < 0x32)) {
        combataipath_select_action(actor);
    } else {
        if ((RND2(4) <= 2) || (actor->inner->class_id == 0x39)) {
            switch (actor->inner->class_id) {
            case 0x29:
                actionId = 2;
                knockback = 1;
                goto do_audio;
            case 0x2a:
                actionId = 3;
                knockback = 3;
                break;
            case 0x2b:
            case 0x39:
                actionId = 0x32;
                knockback = 3;
                break;
            }
        do_audio:
            audio_play(0x12);
            if (actor->inner->class_id == 0x39) {
                combat_actor_play_ranged_windup(actor, combat_actor_heading_from_to(actor, target));
            } else {
                combat_actor_anim7_field2_var(actor, combat_actor_heading_from_to(actor, target));
            }
            target = world_rndr_ranged_attack_anim(actor, target, &hit, actionId, 0xfa, -1);
            combat_actor_anim0_if_not_dead(actor, -1);
            target->inner->flags |= CAF_KNOCKBACK;
            target->inner->knockback_value = (unsigned char)knockback;
            target->inner->knockback_timer = 'd';
            cspell_slot = cspell_status_effect_add(target, 4, 0, 0, '\0');
            g_nVfxParticleColor = 0xa0;
            audio_play(0x15);
            worldfx_combat_damage_ptcl_burst(target, 0x2d);
            cspell_status_effect_remove(target, cspell_slot);
            combat_arena_apply_damage(target, RNDR(0x14, 0x1d), 0, knockback, 0x200, 0);
        } else {
            combat_actor_play_anim_sprite4(actor, combat_actor_heading_from_to(actor, target));
            target = world_rndr_ranged_attack_anim(actor, target, &hit, 5, 300, -1);
            combat_actor_anim0_if_not_dead(actor, -1);
            combat_arena_apply_damage(target, RNDR(4, 8), 0, 1, 0x200, 0);
        }
    }
    return;
}

void far combataiact_actor_melee_attack(CombatActor *actor) {
    CombatActor *target;
    int distance;
    int hit;
    int i;

    hit = 1;
    target = combatenc_find_nearest_actor(actor, &distance);
    if (combat_actor_trace_proj_path(actor, target, 1) != 0 && distance > 1) {
        combat_actor_play_anim_sprite4(actor, combat_actor_heading_from_to(actor, target));
        audio_play(0x51);
        target = world_rndr_ranged_attack_anim(actor, target, &hit, 0x3b, 0x15e, (char)-1);
        combat_actor_anim0_if_not_dead(actor, (int)(char)-1);
        i = 0;
        do {
            target->inner->flags |= CAF_KNOCKBACK;
            target->inner->knockback_value = (unsigned char)i + 1;
            target->inner->knockback_timer = 0x64;
            world_render_with_overlay((void far *)0xffff);
            screen_frame_present();
            ++i;
        } while (i < 4);
        combat_arena_apply_damage(target, RNDR(0xf, 0x22), 0, 1, 0x200, 0);
        audio_play(0x1d);
    } else {
        if (combataiturn_pick_tile_or_attack(actor, 1, 1) == 0) {
            combataipath_select_action(actor);
        }
    }
}

void far combataiact_action_charge_near(CombatActor *actor) {
    int distance;
    CombatActor *target;

    target = combatenc_find_nearest_actor(actor, &distance);
    if (distance >= 3 && combat_actor_trace_proj_path(actor, target, 0) != 0 && RND(100) >= 5) {
        goto ranged;
    }
    combataipath_select_action(actor);
    goto clear;
ranged:
    combataiturn_ranged_attack(actor, target, 8);
clear:
    actor->inner->target = (CombatActor *)0x0;
    return;
}

void far combataiact_melee_random_attack(CombatActor *actor) {
    int distance;
    int hit;
    int knockback;
    CombatActor *target;
    int damage;

    hit = 1;
    target = combatenc_find_nearest_actor(actor, &distance);
    if (combat_actor_trace_proj_path(actor, target, 1) != 0 && distance > 2) {
        knockback = (int)RND(3);
        switch (knockback) {
        case 0:
            combat_actor_play_anim_sprite4(actor, combat_actor_heading_from_to(actor, target));
            target = world_rndr_ranged_attack_anim(actor, target, &hit, 2, 0x15e, -1);

            combat_actor_anim0_if_not_dead(actor, -1);
            damage = cbstat_scale_base_stat_pct(actor, RNDR(0xf, 0x22));
            combat_arena_apply_damage(target, damage, 0, 1, 0x200, 0);
            break;
        case 1:
            combat_actor_play_ranged_windup(actor, combat_actor_heading_from_to(actor, target));
            target = world_rndr_ranged_attack_anim(actor, target, &hit, 3, 0x15e, -1);
            combat_actor_anim0_if_not_dead(actor, -1);
            damage = cbstat_scale_base_stat_pct(actor, RNDR(5, 34));
            combat_arena_apply_damage(target, damage, 0, 2, 0x200, 0);
            break;
        case 2:
            combat_actor_play_melee_swing(actor, combat_actor_heading_from_to(actor, target));
            target = world_rndr_ranged_attack_anim(actor, target, &hit, 4, 0x15e, -1);
            combat_actor_anim0_if_not_dead(actor, -1);
            damage = cbstat_scale_base_stat_pct(actor, RNDR(5, 14));
            combat_arena_apply_damage(target, damage, 0, 3, 0x200, 0);
            break;
        }
    } else {
        combataipath_select_action(actor);
    }
    return;
}

void far combataiact_ranged_attack(CombatActor *actor) {
    CombatActor *target;
    int distance;
    int hit;
    int cspellSlot;

    hit = 1;
    actor->stats[3].base = actor->stats[3].max;
    target = combatenc_find_nearest_actor(actor, &distance);
    if (combat_actor_trace_proj_path(actor, target, 1) != 0 && distance > 1) {
        combat_actor_play_ranged_windup(actor, combat_actor_heading_from_to(actor, target));
        target = world_rndr_ranged_attack_anim(actor, target, &hit, 4, 100, -1);
        combat_actor_anim0_if_not_dead(actor, -1);
        cspellSlot = cspell_status_effect_add(target, 4, 0, 0, '\0');
        g_nVfxParticleColor = 0xe8;
        audio_play(0x15);
        worldfx_combat_damage_ptcl_burst(target, 0x23);
        cspell_status_effect_remove(target, cspellSlot);
        combat_arena_apply_damage(target, RNDR(0x2d, 0x4a), 0, 4, 0x200, 0);
    } else {
        combataipath_select_action(actor);
    }
    return;
}

void far combataiact_bhood_revive_cycle(CombatActor *actor) {
    int slot;
    int done;
    int i;

    done = 0;
    if (combatgrid_tile_is_blocked(actor->inner->grid_x, actor->inner->grid_y) == 0) {
        i = 0;
        if (i < g_combat_count_B) {
            do {
                if ((g_combat_actors_B[i].inner)->class_id == 0x16)
                    break;
                i = i + 1;
            } while (i < g_combat_count_B);
        }
        i = 0;
        if (i < g_combat_count_B) {
            do {
                if (&g_combat_actors_B[i] == actor)
                    break;
                i = i + 1;
            } while (i < g_combat_count_B);
        }
        actor->inner->flags |= CAF_KNOCKBACK;
        actor->inner->knockback_value = '\x03';
        actor->inner->knockback_timer = '\xe8';
        combat_actor_grid_remove(actor);
        audio_play(0x47);
        slot = cspell_status_effect_add(actor, 0x20, 0, 0, '\0');
        cspell_vfx_run_and_wait();
        cspell_status_effect_remove(actor, slot);
        if (actor->inner->class_id == 0x17) {
            combat_actor_release_anim_images(actor->inner->class_id);
            actor->inner->class_id = 0x16;
            combat_actor_rsrc_load_3values(0x16, g_abCombatInnerPoolB[i]);
            g_anim_pool_B[i].sprite_header = g_abCombatInnerPoolB[i];
        }
        actor->stats[0].base = actor->stats[0].max;
        actor->stats[1].base = actor->stats[1].max;
        combatgrid_set_tile_effect(actor->inner->grid_x, actor->inner->grid_y, 9, 400);
        actor->inner->knockback_timer = '\0';
        actor->inner->dmg_value = '\0';
        actor->inner->dmg_frames_left = '\0';
        actor->inner->flags = CAF_READY;
        combat_actor_anim0_if_not_dead(actor, -1);
        while (!done) {
            i = 0;
            do {
                cspell_tick_damage_terrain();
                i = i + 1;
            } while (i < 0xf);
            world_render_with_overlay(MK_FP(0, 0xffff));
            screen_frame_present();
            if (combatgrid_tile_terrain_field(actor->inner->grid_x, actor->inner->grid_y) != 9) {
                done = 1;
            }
        }
        combatgrid_set_tile_effect(actor->inner->grid_x, actor->inner->grid_y, 0, -1);
    }
    return;
}

int combataiact_cnt_pty_stat_22(void) {
    int count;
    int i;

    count = 0;
    i = 0;
    if (i < g_combat_count_B) {
        do {
            if (g_combat_actors_B[i].inner->class_id == CREATURE_BLACK_SLAYER) {
                count = count + 1;
            }
            i = i + 1;
        } while (i < g_combat_count_B);
    }
    return count;
}

void far combataiact_party_tick_status(void) {
    int i;
    int flags;
    int dmgFramesLeft;

    if (combataiact_cnt_pty_stat_22() != 0) {
        i = 0;
        if (i < g_combat_count_B) {
            do {
                if ((g_combat_actors_B[i].inner)->flags & 2) {
                    if (!((flags = (char)(g_combat_actors_B[i].inner)->flags) & 0x10)) {
                        if ((g_combat_actors_B[i].inner)->class_id == 0x16 ||
                            (g_combat_actors_B[i].inner)->class_id == 0x17) {
                            if ((dmgFramesLeft =
                                     (char)(g_combat_actors_B[i].inner)->dmg_frames_left) == 0 &&
                                (g_combat_actors_B[i].inner)->grid_x != -1) {
                                combataiact_bhood_revive_cycle(&g_combat_actors_B[i]);
                            } else {
                                (g_combat_actors_B[i].inner)->dmg_frames_left--;
                            }
                        }
                    }
                }
                i = i + 1;
            } while (i < g_combat_count_B);
        }
    }
}
