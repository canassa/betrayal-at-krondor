#include "structs.h"
#include "SRC/COMBAT/AI/CBTAITRN.H"
#include "SRC/SYS/RAND.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/R3D/FX/WORLDFX.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "SRC/COMBAT/AI/CMBTAI.H"
#include "SRC/COMBAT/SPELL/CSPELL.H"
#include "SRC/COMBAT/STATS/CBSTAT.H"
#include "defines.h"

EncounterAiActionFn far *g_encounter_ai_action_table[8] = {
    &combataiturn_thunk_action_6, &combataiturn_action_kind6,     &combataiturn_action_1000a,
    &combataiturn_action_2000a,   &combataiturn_action_4000a,     &combataiturn_action_5000a,
    &combataiturn_action_3000a,   &combataiturn_select_and_engage};
unsigned char __dat_15dc[128] = {
    0x01, 0x00, 0x04, 0x00, 0x06, 0x00, 0x05, 0x00, 0x07, 0x00, 0x08, 0x00, 0x03, 0x00, 0x02, 0x00,
    0x02, 0x00, 0x08, 0x00, 0x03, 0x00, 0x07, 0x00, 0x04, 0x00, 0x05, 0x00, 0x06, 0x00, 0x01, 0x00,
    0x03, 0x00, 0x06, 0x00, 0x07, 0x00, 0x08, 0x00, 0x02, 0x00, 0x01, 0x00, 0x04, 0x00, 0x05, 0x00,
    0x04, 0x00, 0x02, 0x00, 0x07, 0x00, 0x03, 0x00, 0x08, 0x00, 0x01, 0x00, 0x05, 0x00, 0x06, 0x00,
    0x05, 0x00, 0x08, 0x00, 0x04, 0x00, 0x01, 0x00, 0x06, 0x00, 0x07, 0x00, 0x02, 0x00, 0x03, 0x00,
    0x06, 0x00, 0x03, 0x00, 0x08, 0x00, 0x07, 0x00, 0x05, 0x00, 0x04, 0x00, 0x02, 0x00, 0x01, 0x00,
    0x07, 0x00, 0x03, 0x00, 0x02, 0x00, 0x08, 0x00, 0x06, 0x00, 0x01, 0x00, 0x05, 0x00, 0x04, 0x00,
    0x08, 0x00, 0x06, 0x00, 0x07, 0x00, 0x03, 0x00, 0x04, 0x00, 0x02, 0x00, 0x01, 0x00, 0x05, 0x00};

int far combataiturn_pick_tile_or_attack(CombatActor *actor, int min_score_threshold,
                                         int may_attack) {
    int try_x, try_y;
    int best_x, best_y;
    int saved_x, saved_y;
    int cur_score;
    int ret_val;
    int rand_pct;
    int best_score;

    combatenc_find_nearest_actor(actor, &cur_score);
    if (cur_score > min_score_threshold) {
        ret_val = 0;
        goto done;
    }
    ret_val = 1;
    best_score = cur_score;
    best_x = (int)actor->inner->grid_x;
    best_y = (int)actor->inner->grid_y;
    for (try_x = 7; try_x > -1; try_x--) {
        for (try_y = 0xc; try_y > -1; try_y--) {
            actor->inner->pad_6[0] = (unsigned char)try_x;
            actor->inner->pad_6[1] = (unsigned char)try_y;
            if (combatgrid_tile_is_blocked((unsigned char)try_x, (unsigned char)try_y) == 0) {
                if (combataipath_actor_walk_path(actor, 1) != 0) {
                    saved_x = (int)actor->inner->grid_x;
                    saved_y = (int)actor->inner->grid_y;
                    actor->inner->grid_x = (unsigned char)try_x;
                    actor->inner->grid_y = (unsigned char)try_y;
                    combatenc_find_nearest_actor(actor, &cur_score);
                    if (cur_score > best_score || (cur_score == best_score && RND(100) < 0x33)) {
                        best_score = cur_score;
                        best_x = try_x;
                        best_y = try_y;
                    }
                    actor->inner->grid_x = (unsigned char)saved_x;
                    actor->inner->grid_y = (unsigned char)saved_y;
                }
            } else
                continue;
        }
    }
    rand_pct = RND(100);
    if ((((int)actor->inner->grid_x == best_x && (int)actor->inner->grid_y == best_y) ||
         rand_pct < 0xf) &&
        may_attack) {
        combataipath_select_action(actor);
    } else {
        actor->inner->pad_6[0] = (unsigned char)best_x;
        actor->inner->pad_6[1] = (unsigned char)best_y;
        combataipath_actor_walk_path(actor, 0);
    }
done:
    return ret_val;
}

int far combataiturn_armor_eff_stat(CombatActor *actor) {
    int effStat;
    ItemRecord far *weapon;

    weapon = cbstat_find_intact_equip_cat(actor, 2);
    if (weapon != (ItemRecord far *)0) {
        effStat =
            (weapon->nDefense_or_range_close * cbstat_inv_item_condition_rec(weapon, actor)) / 100;
    } else {
        effStat = 0;
    }
    return effStat;
}

void far combataiturn_ranged_attack(CombatActor *attacker, CombatActor *target, int quarrel_type) {
    ItemRecord far *weapon;
    int hit;
    int local_damage;
    int knockback;
    int slot;
    unsigned int damageFlags;
    unsigned short actionId;
    int armor_stat;
    CombatActor *actor;

    weapon = cbstat_find_intact_equip_cat(attacker, 2);
    stat_combatant_modify(attacker, 5, 1, 3);
    armor_stat = combataiturn_armor_eff_stat(attacker);
    hit = combatenc_skill_check_random(attacker, target,
                                       stat_actor_get(attacker, 5, 0) + armor_stat, quarrel_type);
    if (hit != 0) {
        stat_combatant_modify(attacker, 5, 1, 3);
    }
    combat_actor_anim7_field2_var(attacker, combat_actor_heading_from_to(attacker, target));
    if (attacker->inner->class_id == 0x1a) {
        combat_actor_anim0_if_not_dead(attacker, -1);
        combat_actor_anim7_field2_var(attacker, -1);
        combat_actor_anim0_if_not_dead(attacker, -1);
        actionId = 0x3c;
    } else {
        actionId = 1;
    }
    if (quarrel_type == 8) {
        actor = world_rndr_ranged_attack_anim(attacker, target, &hit, 0x14, 0x5a, -1);
        audio_play(0x49);
        combat_actor_anim0_if_not_dead(attacker, -1);
    } else {
        if (weapon != (ItemRecord far *)0) {
            audio_play(0x44);
        }

        actor = world_rndr_ranged_attack_anim(attacker, target, &hit, actionId, 300, -1);
    }
    if (hit != 0) {

        damageFlags = 0x540;
        switch (quarrel_type) {
        case 0:
        case 1:
        case 2:
        case 3:
        case 7:
        case 8:
        case 9:
            knockback = 1;
            break;
        case 4:
        case 5:
        case 6:
            knockback = 2;
            damageFlags |= 1;
            break;
        }
        local_damage = combat_actor_calc_weapon_damage(attacker, quarrel_type);
        audio_play(0x42);
        if (quarrel_type == 3) {
            damageFlags |= 8;
            slot = cspell_status_effect_add(actor, 4, 0, 0, '\0');
            g_nVfxParticleColor = 200;
            actor->inner->flags |= CAF_KNOCKBACK;
            actor->inner->knockback_value = (unsigned char)knockback;
            actor->inner->knockback_timer = 'd';
            audio_play(0x1d);
            worldfx_combat_damage_ptcl_burst(actor, 10);
            cspell_status_effect_remove(actor, slot);
        }
        combat_arena_apply_damage(actor, local_damage, 1, knockback, damageFlags, 0);
        cbstat_damage_equipped_items(actor, 4, 0x200);
    }
    cbstat_damage_equipped_items(attacker, 2, 0x100);
}

int combataiturn_sel_consum_qrl(CombatActor *actor, int kind, int consume_flag) {
    int item_id;
    int scan_kind;
    int kind_picked;
    int n_quarrels;

    kind_picked = kind;
    item_id = -1;
    if (actor->inner->class_id == 0x1a) {
        return 9;
    }
    if (kind == -1) {
        for (scan_kind = 7; scan_kind > -1; scan_kind--) {
            if (combat_actor_cnt_qrls_kind(actor, scan_kind) != 0) {
                kind_picked = scan_kind;
                break;
            }
        }
    }
    n_quarrels = combat_actor_cnt_qrls_kind(actor, kind_picked);
    if (n_quarrels != 0) {
        switch (kind_picked) {
        case 0:
            item_id = 0x24;
            break;
        case 2:
            item_id = 0x26;
            break;
        case 3:
            item_id = 0x2a;
            break;
        case 4:
            item_id = 0x27;
            break;
        case 7:
            item_id = 0x2b;
            break;
        case 1:
            item_id = 0x25;
            break;
        case 5:
            item_id = 0x28;
            break;
        case 6:
            item_id = 0x29;
            break;
        }
    } else
        kind_picked = -1;
    if ((consume_flag != 0) && (item_id != -1)) {
        itemtbl_inv_consume_one_by_kind(actor->actor_record, item_id);
    }
    return kind_picked;
}

int combataiturn_action_disp_base(CombatActor *actor, int param_2, unsigned int param_3) {
    int minClearance;
    unsigned int quarrelKind;
    int fired;

    minClearance = 4 - (int)(stat_actor_get(actor, 5, 0) + 0x18) / 0x19;
    combatenc_ai_pick_target_by_role(actor, param_2, param_3, minClearance);
    fired = 0;
    if (actor->inner->target != (CombatActor *)0x0) {
        if (combat_actor_trace_proj_path(actor, actor->inner->target, 0) != 0) {
            quarrelKind = combataiturn_sel_consum_qrl(actor, -1, 1);
            if ((int)quarrelKind != -1) {
                combataiturn_ranged_attack(actor, actor->inner->target, quarrelKind);
                fired = 1;
            }
        }
    }
    return fired;
}

int far combataiturn_thunk_action_6(CombatActor *actor) {
    int result = combataipath_action_6(actor);
    return result;
}

int far combataiturn_action_kind6(CombatActor *actor) {
    int fired = combataiturn_action_disp_base(actor, 6, 0);
    return fired;
}

int far combataiturn_action_1000a(CombatActor *actor) {
    int fired = combataiturn_action_disp_base(actor, 10, 1);
    return fired;
}

int far combataiturn_action_2000a(CombatActor *actor) {
    int fired = combataiturn_action_disp_base(actor, 10, 2);
    return fired;
}

int far combataiturn_action_4000a(CombatActor *actor) {
    int fired = combataiturn_action_disp_base(actor, 10, 4);
    return fired;
}

int far combataiturn_action_5000a(CombatActor *actor) {
    int fired = combataiturn_action_disp_base(actor, 10, 5);
    return fired;
}

int far combataiturn_action_3000a(CombatActor *actor) {
    int fired = combataiturn_action_disp_base(actor, 10, 3);
    return fired;
}

int far combataiturn_select_and_engage(CombatActor *actor) {
    int flag;
    int speed_thr;
    int dist;
    int rand_pct;
    int i;

    flag = 0;
    i = 0;
    goto loop_test;

loop_body:
    dist = combatgrid_chebyshev_distance(actor->inner->grid_x, actor->inner->grid_y,
                                         g_pCombatActiveActors[i].inner->grid_x,
                                         g_pCombatActiveActors[i].inner->grid_y);
    speed_thr = (int)g_acting_actor_speed - 3;
    if (speed_thr >= dist) {
        rand_pct = RND(100);
        if (rand_pct >= 50) {
        do_advance:
            combatenc_set_flag8_clear_flag1(actor);
            flag = 1;
            goto after_loop;
        }
    } else {
        if (stat_actor_get(&g_pCombatActiveActors[i], 7, 0) == 0)
            goto loop_inc;
        actor->inner->target = &g_pCombatActiveActors[i];
        rand_pct = RND(100);
        if (combat_actor_trace_proj_path(actor, &g_pCombatActiveActors[i], 0) == 0)
            goto loop_inc;
        if (rand_pct >= 75)
            goto do_advance;
    }
loop_inc:
    i++;
loop_test:
    if (i < g_nCombatActiveCount)
        goto loop_body;
after_loop:
    if (flag == 0)
        flag = combataiturn_action_4000a(actor);
    return flag;
}

void far combataiturn_take_actor_turn(CombatActor *actor) {
    int action_index;
    int rand_pct;
    unsigned int stat_pct;
    unsigned int result;
    unsigned int(far * fn)(CombatActor * actor);

    action_index = 1;
    result = 0;

    if (combataiturn_pick_tile_or_attack(actor, 1, 1) != 0) {
        result = 1;
    } else if ((int)stat_actor_get(actor, 0, 0) < 5) {
        action_index = 8;
    }

    while (result == 0 && action_index < 8 && actor->inner->pad_e[2] != 0) {
        rand_pct = RND(100);
        if (rand_pct < 0x5b) {
            fn = *(unsigned int(far **)(CombatActor *)) &
                 g_encounter_ai_action_table[*(short *)((char *)g_encounter_ai_action_table +
                                                        ((int)(signed char)actor->inner->pad_e[2]
                                                         << 4) +
                                                        (action_index << 1) + 0x10) -
                                             1];
            result = fn(actor);
        }
        action_index++;
    }

    if (result == 0) {
        rand_pct = RND(100);
        stat_pct = (unsigned int)combat_actor_stat_percent(actor, 1);
        if (rand_pct < 0x4b || stat_pct == 0x64) {
            combataipath_select_target(actor, 100, 0);
        } else {
            combatenc_actor_enter_defense(actor);
        }
    }

    actor->inner->target = (CombatActor *)0;
}
