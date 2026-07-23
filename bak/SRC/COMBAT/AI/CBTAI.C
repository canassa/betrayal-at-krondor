#include "globals.h"
#include "SRC/GAME/GMAIN.H"
#include "structs.h"
#include "SRC/COMBAT/AI/CBTAI.H"
#include "SRC/SYS/RAND.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "SRC/COMBAT/AI/CMBTAI.H"
#include "SRC/COMBAT/AI/CBTAITRN.H"
#include "SRC/COMBAT/SPELL/CSPELL.H"
#include "defines.h"
#include <stddef.h>

EncounterAiTurnFn far *g_encounter_ai_turn_table[8] = {
    &combat_ai_try_cast_heal,     &combat_ai_turn_kind6,          &combat_ai_turn_packet_10006,
    &combat_ai_turn_packet_20006, &combat_ai_turn_packet_40006,   &combat_ai_turn_packet_50006,
    &combat_ai_turn_packet_30006, &combat_ai_try_aoe_cast_spell_7};
unsigned char __dat_153c[128] = {
    0x01, 0x00, 0x08, 0x00, 0x06, 0x00, 0x03, 0x00, 0x07, 0x00, 0x02, 0x00, 0x04, 0x00, 0x05, 0x00,
    0x02, 0x00, 0x01, 0x00, 0x03, 0x00, 0x07, 0x00, 0x05, 0x00, 0x08, 0x00, 0x06, 0x00, 0x04, 0x00,
    0x03, 0x00, 0x06, 0x00, 0x08, 0x00, 0x07, 0x00, 0x01, 0x00, 0x02, 0x00, 0x04, 0x00, 0x05, 0x00,
    0x04, 0x00, 0x03, 0x00, 0x05, 0x00, 0x06, 0x00, 0x02, 0x00, 0x01, 0x00, 0x07, 0x00, 0x08, 0x00,
    0x05, 0x00, 0x04, 0x00, 0x07, 0x00, 0x06, 0x00, 0x03, 0x00, 0x08, 0x00, 0x01, 0x00, 0x02, 0x00,
    0x06, 0x00, 0x08, 0x00, 0x01, 0x00, 0x03, 0x00, 0x02, 0x00, 0x07, 0x00, 0x04, 0x00, 0x05, 0x00,
    0x07, 0x00, 0x03, 0x00, 0x02, 0x00, 0x08, 0x00, 0x06, 0x00, 0x01, 0x00, 0x05, 0x00, 0x04, 0x00,
    0x08, 0x00, 0x02, 0x00, 0x03, 0x00, 0x07, 0x00, 0x05, 0x00, 0x01, 0x00, 0x06, 0x00, 0x04, 0x00};

void far combat_ai_actor_cast_spell(CombatActor *caster, CombatActor *target, int spell_id) {
    cspell_resolve_cast(caster, target, spell_id,
                        cspell_actor_stat_get_comb_dflt(caster, spell_id));
}

void far combat_ai_resolve_attack_attempt(CombatActor *attacker, CombatActor *target,
                                          int spell_id) {
    if (combatenc_skill_check_random(attacker, target, stat_actor_get(attacker, 7, 0), -1) != 0) {
        cspell_resolve_cast(attacker, target, spell_id,
                            cspell_actor_stat_get_comb_dflt(attacker, spell_id));
    } else {
        combat_actor_anim0_if_not_dead(attacker, combat_actor_heading_from_to(attacker, target));
    }
}

#ifndef V102CD
void far combat_ai_resolve_hit(CombatActor *attacker, CombatActor *target, int damage, int dir) {
    int hpBefore;
    int staminaBefore;
    int b;

    if ((attacker == (CombatActor *)0x0) || (cspell_stat_effect_find_type(attacker, 0x1f) == -1)) {
        hpBefore = target->stats[0].base;
        staminaBefore = target->stats[1].base;
        combat_arena_actor_set_anim_pose(target, '\x04');
        combat_arena_apply_damage(attacker, damage, 0, 0, 0, 1);
        attacker->inner->flags &= ~CAF_KNOCKBACK;
        if (((b = target->cParty_slot) == '\0') ||
            ((((b = (char)g_gameState.abActorStatusRanks[target->cParty_slot - 1][0]) == '\0' &&
               (b = (char)g_gameState.abActorStatusRanks[target->cParty_slot - 1][1]) == '\0' &&
               (b = (char)g_gameState.abActorStatusRanks[target->cParty_slot - 1][2]) == '\0' &&
               (b = (char)g_gameState.abActorStatusRanks[target->cParty_slot - 1][3]) == '\0' &&
               (b = (char)g_gameState.abActorStatusRanks[target->cParty_slot - 1][5]) == '\0' &&
               (b = (char)g_gameState.abActorStatusRanks[target->cParty_slot - 1][6]) == '\0')))) {
            stat_combatant_modify(target, 0x10, (long)(dir << 8), 0x50);
        }
        target->inner->dmg_value =
            -(((target->stats[0].base - hpBefore) + target->stats[1].base) - staminaBefore);
        target->inner->dmg_frames_left = '\b';
        stat_actor_get(target, 0, 0);
        stat_actor_get(target, 1, 0);
        if (attacker != (CombatActor *)0x0) {
            combat_actor_anim0_if_not_dead(attacker,
                                           combat_actor_heading_from_to(attacker, target));
        }
    }
    return;
}
#endif

int far combat_ai_pick_action(CombatActor *actor) {
    int action_id;
    int i;
    int sc;

    action_id = -1;
    for (i = 0; i < g_nCombatActiveCount; i++) {
        if (g_pCombatActiveActors[i].inner->class_id == 0x16 ||
            g_pCombatActiveActors[i].inner->class_id == 0x17) {
            if (RND(100) > 10)
                break;
        }
    }
    if (i < g_nCombatActiveCount) {
        if (((sc = (signed char)g_pCombatActiveActors[i].inner->flags) & 2) == 0 &&
            cspell_check_castable(9, actor, 0) != 0 &&
            combat_actor_trace_proj_path(actor, &g_pCombatActiveActors[i], 1) != 0 &&
            g_pCombatActiveActors[i].inner->class_id != 0x17) {
            action_id = 9;
        } else if ((g_pCombatActiveActors[i].inner->flags & CAF_DEAD) != 0 &&
                   cspell_check_castable(0x20, actor, 0) != 0 &&
                   ((sc = (signed char)g_pCombatActiveActors[i].inner->flags) & 0x10) == 0 &&
                   g_pCombatActiveActors[i].inner->grid_x != -1) {
            action_id = 0x20;
        }
        if (action_id == -1)
            goto L_phase2;
        cspell_resolve_cast(actor, &g_pCombatActiveActors[i], action_id,
                            cspell_actor_stat_get_comb_dflt(actor, action_id));
        return 1;
    }

L_phase2:
    for (i = 0; i < g_nCombatActiveCount; i++) {
        if (g_pCombatActiveActors[i].inner->class_id == 0x36) {
            if (RND(100) > 10)
                break;
        }
    }
    if (i < g_nCombatActiveCount &&
        ((sc = (signed char)g_pCombatActiveActors[i].inner->flags) & 2) == 0 &&
        cspell_check_castable(0x2a, actor, 0) != 0) {
        cspell_resolve_cast(actor, &g_pCombatActiveActors[i], 0x2a,
                            cspell_actor_stat_get_comb_dflt(actor, 0x2a));
        return 1;
    }

    for (i = 0; i < g_nCombatActiveCount; i++) {
        if (g_pCombatActiveActors[i].inner->class_id == 0x29 ||
            g_pCombatActiveActors[i].inner->class_id == 0x2a ||
            g_pCombatActiveActors[i].inner->class_id == 0x2b) {
            if (RND(100) > 10)
                break;
        }
    }
    if (i < g_nCombatActiveCount &&
        ((sc = (signed char)g_pCombatActiveActors[i].inner->flags) & 2) == 0 &&
        ((sc = (signed char)g_pCombatActiveActors[i].inner->flags) & 0x10) == 0 &&
        cspell_check_castable(0x29, actor, 0) != 0) {
        cspell_resolve_cast(actor, &g_pCombatActiveActors[i], 0x29,
                            cspell_actor_stat_get_comb_dflt(actor, 0x29));
        return 1;
    }
    return 0;
}

int far combat_ai_execute_turn(CombatActor *actor, int param_2, unsigned int param_3) {
    int ret;
    int clearance;
    int spell_id;

    if (combat_ai_pick_action(actor) != 0) {
        return 1;
    }
    ret = 0;
    clearance = 4 - (int)stat_actor_get(actor, 7, 0) / 0x19;
    combatenc_ai_pick_target_by_role(actor, param_2, param_3, clearance);
    if (actor->inner->target != (CombatActor *)0) {
        spell_id = cspell_ai_pick_castable_spell(actor, actor->inner->target, 1, 0);
        if (spell_id < 0) {
            spell_id = cspell_ai_pick_castable_spell(actor, actor->inner->target, 1, 1);
        }
        if (spell_id > -1) {
            if (combatenc_actor_stat_above_table(0, actor) != 0) {
                if (combat_actor_trace_proj_path(actor, actor->inner->target, 1) != 0) {
                    combat_ai_actor_cast_spell(actor, actor->inner->target, spell_id);
                    ret = 1;
                }
            }
        }
    } else {
        combatenc_ai_pick_target_by_role(actor, param_2, param_3, 0);
        if (actor->inner->target != (CombatActor *)0) {
            spell_id = cspell_ai_pick_castable_spell(actor, actor->inner->target, 1, 1);
            if (spell_id > -1) {
                if (combatenc_actor_stat_above_table(1, actor) != 0) {
                    combat_ai_resolve_attack_attempt(actor, actor->inner->target, spell_id);
                    ret = 1;
                }
            }
        }
    }
    return ret;
}

int far combat_ai_pick_heal_spell(CombatActor *caster, CombatActor *target) {
    unsigned int curHp;
    unsigned int min_hp_pct;
    unsigned int threshold;
    register int i;
    int result;

    min_hp_pct = 0x6e;
    i = 0;
    while (i < g_nCombatActiveCount) {
        if (&g_pCombatActiveActors[i] != caster) {
            curHp = stat_actor_get(&g_pCombatActiveActors[i], 0, 0);
            if ((int)curHp < (int)min_hp_pct) {
                min_hp_pct = curHp;
            }
        }
        i++;
    }
    threshold = RND(80);
    if ((int)curHp < (int)threshold) {
        if (cspell_check_castable(7, caster, -1)) {
            result = 7;
            return result;
        }
    }
    if (cspell_check_castable(6, caster, -1)) {
        if (cspell_stat_effect_find_type(target, 6) == -1) {
            result = 6;
            return result;
        }
    }
    result = -1;
    return result;
}

int far combat_ai_try_cast_heal(register CombatActor *caster) {
    int casted;
    int spell_id;
    CombatActor *target;

    casted = 0;
    target = g_pCombatOtherActors;
    if (combatenc_actor_stat_above_table(2, caster) != 0) {
        spell_id = combat_ai_pick_heal_spell(caster, target);
        if (spell_id == -1) {
            return 0;
        }
        {
            int hp_pct;
            int i;
            hp_pct = combat_actor_stat_percent(target, 0);
            if (caster != target && hp_pct > 0 && hp_pct < 100) {
                cspell_resolve_cast(caster, target, spell_id,
                                    cspell_actor_stat_get_comb_dflt(caster, spell_id));
                casted = 1;
            } else {
                i = 0;
                if (i < g_nCombatOtherCount) {
                    do {
                        hp_pct = combat_actor_stat_percent(&g_pCombatOtherActors[i], 0);
                        if (&g_pCombatOtherActors[i] != caster && hp_pct > 0 && hp_pct < 100) {
                            cspell_resolve_cast(caster, &g_pCombatOtherActors[i], spell_id,
                                                cspell_actor_stat_get_comb_dflt(caster, spell_id));
                            i = g_nCombatOtherCount;
                            casted = 1;
                        }
                        i++;
                    } while (i < g_nCombatOtherCount);
                }
            }
        }
    }
    return casted;
}

int far combat_ai_turn_kind6(CombatActor *actor) {
    int result;

    result = combat_ai_execute_turn(actor, 6, 0);
    return result;
}

int far combat_ai_turn_packet_10006(CombatActor *actor) {
    int result;

    result = combat_ai_execute_turn(actor, 6, 1);
    return result;
}

int far combat_ai_turn_packet_20006(CombatActor *actor) {
    int result;

    result = combat_ai_execute_turn(actor, 6, 2);
    return result;
}

int far combat_ai_turn_packet_40006(CombatActor *actor) {
    int result;

    result = combat_ai_execute_turn(actor, 6, 4);
    return result;
}

int far combat_ai_turn_packet_50006(CombatActor *actor) {
    int result;

    result = combat_ai_execute_turn(actor, 6, 5);
    return result;
}

int far combat_ai_turn_packet_30006(CombatActor *actor) {
    int result;

    result = combat_ai_execute_turn(actor, 6, 3);
    return result;
}

int far combat_ai_try_aoe_cast_spell_7(CombatActor *actor) {
    int result;
    CombatActor *target_actor;
    register int i;
    int stat;

    result = 0;
    if (combatenc_actor_stat_above_table(2, actor)) {
        i = 0;
        while (i < g_nCombatOtherCount) {
            if (g_pCombatOtherActors[i].inner->target != actor) {
                if (!((char)g_pCombatOtherActors[i].inner->target->inner->flags) & 2) {
                    if (g_pCombatOtherActors[i].inner->target != NULL) {
                        target_actor = g_pCombatOtherActors[i].inner->target;
                        stat = combat_actor_stat_percent(target_actor, 0);
                        if (target_actor == g_actors_B_origin)
                            goto do_origin_check;
                        if (stat < 0x46)
                            goto do_cast;
                    do_origin_check:
                        if (target_actor != g_actors_B_origin)
                            goto do_skip;
                        if (stat >= 0x50)
                            goto do_skip;
                    do_cast:
                        cspell_resolve_cast(actor, target_actor, 7,
                                            cspell_actor_stat_get_comb_dflt(actor, 7));
                        result = 1;
                        i = g_nCombatOtherCount;
                    do_skip:;
                    }
                }
            }
            i++;
        }
    }
    return result;
}

#define AI_TURN_INDEX (*(short (*)[8][8])((char *)&__dat_1492 + (0x152c - 0x1492)))

#define AI_TURN_FN ((EncounterAiTurnFn far *)((char *)&__dat_1492 + (0x1518 - 0x1492)))

typedef int(far *AiTurnFn)(CombatActor *actor);

void far combat_ai_take_turn(CombatActor *actor) {
    int spell_attempt;
    int dist;
    int rand_mod;
    int stat_pct;
    int result;
    AiTurnFn fn;

    spell_attempt = 0;
    result = 0;
    if (combataiturn_pick_tile_or_attack(actor, 1, 1)) {
        result = 1;
    } else {
        if ((int)stat_actor_get(actor, 0x10, 0) < 5)
            spell_attempt = 8;
    }

    while (result == 0 && spell_attempt < 8 && actor->inner->pad_e[1] != '\0') {
        rand_mod = RND(100);
        if (rand_mod < 0x5b) {
            fn = (AiTurnFn)
                AI_TURN_FN[AI_TURN_INDEX[(int)(signed char)actor->inner->pad_e[1]][spell_attempt]];
            result = fn(actor);
        }
        spell_attempt++;
    }

    if (result == 0) {
        stat_pct = combat_actor_stat_percent(actor, 1);
        if (stat_pct > 0x28 && RND(100) > 0xa && !actor->cParty_slot) {
            combatenc_find_nearest_actor(g_picked_actor, &dist);
            if (dist <= 6)
                dist = 7;
            dist -= 6;
            g_acting_actor_speed = (dist > (int)g_acting_actor_speed) ? g_acting_actor_speed : dist;
            combataipath_select_target(actor, 0x64, 0);
        } else {
            combatenc_actor_enter_defense(actor);
        }
    }

    actor->inner->target = (CombatActor *)0;
}
