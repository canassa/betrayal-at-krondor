#include <dos.h>
#include "globals.h"
#include "structs.h"
#include "SRC/COMBAT/AI/CMBTAI.H"
#include "SRC/SYS/RAND.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "SRC/COMBAT/AI/CBTAITRN.H"
#include "SRC/COMBAT/SPELL/CSPELL.H"
#include "defines.h"

CombatAiActionFn far *g_combat_ai_action_table[8] = {
    &combataipath_low_health_action, &combataipath_action_6,     &combataipath_action_100_1,
    &combataipath_action_100_2,      &combataipath_action_60064, &combataipath_action_50064,
    &combataipath_action_30064,      &combataipath_action_40064};
unsigned short g_bActorAdjacentToTarget = 0x0000;
unsigned char __dat_1492[138] = {
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 0x00, 0x08, 0x00, 0x04, 0x00,
    0x06, 0x00, 0x03, 0x00, 0x02, 0x00, 0x07, 0x00, 0x05, 0x00, 0x02, 0x00, 0x04, 0x00, 0x08, 0x00,
    0x05, 0x00, 0x03, 0x00, 0x07, 0x00, 0x06, 0x00, 0x01, 0x00, 0x03, 0x00, 0x06, 0x00, 0x07, 0x00,
    0x08, 0x00, 0x01, 0x00, 0x02, 0x00, 0x05, 0x00, 0x04, 0x00, 0x04, 0x00, 0x05, 0x00, 0x08, 0x00,
    0x06, 0x00, 0x07, 0x00, 0x02, 0x00, 0x03, 0x00, 0x01, 0x00, 0x05, 0x00, 0x04, 0x00, 0x03, 0x00,
    0x07, 0x00, 0x02, 0x00, 0x06, 0x00, 0x01, 0x00, 0x08, 0x00, 0x06, 0x00, 0x01, 0x00, 0x02, 0x00,
    0x03, 0x00, 0x07, 0x00, 0x08, 0x00, 0x04, 0x00, 0x05, 0x00, 0x07, 0x00, 0x05, 0x00, 0x08, 0x00,
    0x04, 0x00, 0x01, 0x00, 0x02, 0x00, 0x06, 0x00, 0x03, 0x00, 0x08, 0x00, 0x02, 0x00, 0x04, 0x00,
    0x05, 0x00, 0x03, 0x00, 0x06, 0x00, 0x07, 0x00, 0x01, 0x00};

typedef struct {
    unsigned char b[10];
} AnimBuf10;

static void far combataipath_rng_atk_tmp_tile(CombatActor *actor, int x, int y) {
    int hit;
    AnimBuf10 animBuf;
    CombatActor savedActor;
    CombatActorInner savedInner;
    ushort action_id;
    int direction;

    hit = 1;
    animBuf = *(AnimBuf10 far *)MK_FP(FP_SEG(__dat_1492), (unsigned)__dat_1492);
    savedActor.inner = &savedInner;
    savedInner.grid_x = actor->inner->grid_x;
    savedInner.grid_y = actor->inner->grid_y;
    actor->inner->grid_x = x;
    actor->inner->grid_y = y;
    action_id = actor->inner->class_id;
    savedInner.class_id = action_id;
    combatgrid_tile_set_word(x, y, 0);
    if (cspell_stat_effect_find_type(actor, 0x10) != -1) {
        direction = -1;
    } else {
        direction = combat_actor_heading_from_to(actor, &savedActor);
    }
    combat_actor_anim0_if_not_dead(actor, direction);
    combat_actor_anim_step(animBuf.b, actor);
    world_rndr_ranged_attack_anim(actor, &savedActor, &hit, action_id, 100, animBuf.b[0]);
    actor->inner->grid_x = savedInner.grid_x;
    actor->inner->grid_y = savedInner.grid_y;
    combatgrid_tile_set_word(savedInner.grid_x, savedInner.grid_y, (uint)actor);
    return;
}

static void combataipath_resolv_blockd_diag(int x, int y, int *dx, int *dy) {
    if ((*dx != 0) && (*dy != 0)) {
        if (combatgrid_tile_walkable_kind(x + *dx, y, -1) != 0) {
            if (combatgrid_tile_walkable_kind(x, y + *dy, -1) != 0) {
                if (combatgrid_find_cmbt_at_tile((uchar)((char)x + (char)*dx), (uchar)y) != 0) {
                    *dx = 0;
                } else {
                    *dy = 0;
                }
            }
        }
    }
}

static int far combataipath_step_to_target(CombatActor *actor, int ranged) {
    int dx;
    int dy;
    int orig_x;
    int orig_y;
    int new_x;
    int new_y;
    CombatActor prevActor;
    CombatActorInner prevInner;
    int target_x;
    int target_y;
    unsigned char scratch;

    prevActor.inner = &prevInner;
    target_x = (char)actor->inner->pad_6[0];
    target_y = (char)actor->inner->pad_6[1];

    if (actor->inner->grid_x == target_x && actor->inner->grid_y == target_y)
        goto LAB_0408;

    if (target_x < 0 || target_x >= 8 || target_y < 0 || target_y >= 13)
        return 0;

    if (actor->inner->grid_x > target_x)
        dx = -1;
    else if (actor->inner->grid_x < target_x)
        dx = 1;
    else
        dx = 0;

    if (actor->inner->grid_y > target_y)
        dy = -1;
    else if (actor->inner->grid_y < target_y)
        dy = 1;
    else
        dy = 0;

    orig_x = actor->inner->grid_x;
    orig_y = actor->inner->grid_y;
    combataipath_resolv_blockd_diag(orig_x, orig_y, &dx, &dy);

    actor->inner->grid_x = actor->inner->grid_x + (char)dx;
    actor->inner->grid_y = actor->inner->grid_y + (char)dy;

    new_x = actor->inner->grid_x;
    new_y = actor->inner->grid_y;

    if (combatgrid_tile_is_blocked(new_x, new_y) != 0) {
        if (combatgrid_tile_terrain_field(new_x, new_y) == 5 && g_bActorAdjacentToTarget != 0) {
            if (ranged != 0)
                goto LAB_0408;
            if (combatgrid_place_actor_on_tile(new_x, new_y, new_x + dx, new_y + dy) == 0) {
                actor->inner->grid_y = actor->inner->grid_y - (char)dy;
                actor->inner->grid_x = actor->inner->grid_x - (char)dx;
                combat_actor_path_blocked_anim();
                goto LAB_038e;
            }
            audio_play(0x13);
            combataipath_rng_atk_tmp_tile(actor, orig_x, orig_y);
            combatgrid_pathfind_from_tile(new_x + dx, new_y + dy, -1);
            goto LAB_0408;
        }
        if (!((dx == 0 || dy != 0) && (dx != 0 || dy == 0))) {

            if (combatgrid_tile_is_blocked(actor->inner->grid_x + (char)dy,
                                           actor->inner->grid_y + (char)dx) == 0) {
                actor->inner->grid_y = actor->inner->grid_y + (char)dx;
                actor->inner->grid_x = actor->inner->grid_x + (char)dy;
            } else {
                if (combatgrid_tile_is_blocked(actor->inner->grid_x - (char)dy,
                                               actor->inner->grid_y - (char)dx) != 0)
                    goto LAB_038e;
                actor->inner->grid_y = actor->inner->grid_y - (char)dx;
                actor->inner->grid_x = actor->inner->grid_x - (char)dy;
            }
        } else {

            if (combatgrid_tile_is_blocked(actor->inner->grid_x - (char)dx, actor->inner->grid_y) ==
                0) {
                actor->inner->grid_x = actor->inner->grid_x - (char)dx;
            } else if (combatgrid_tile_is_blocked(actor->inner->grid_x,
                                                  actor->inner->grid_y - (char)dy) == 0) {
                actor->inner->grid_y = actor->inner->grid_y - (char)dy;
            }
        }
    }
LAB_038e:
    if (combatgrid_tile_is_blocked(actor->inner->grid_x, actor->inner->grid_y) == 0) {
        if (ranged == 0) {
            combataipath_rng_atk_tmp_tile(actor, orig_x, orig_y);
            prevActor.inner->grid_x = (unsigned char)orig_x;
            prevActor.inner->grid_y = (unsigned char)orig_y;
            combat_actor_anim0_if_not_dead(actor, combat_actor_heading_from_to(&prevActor, actor));
        }
        return 1;
    } else if (actor->inner->grid_x != orig_x || actor->inner->grid_y != orig_y) {
        actor->inner->grid_x = (unsigned char)orig_x;
        actor->inner->grid_y = (unsigned char)orig_y;
        return 0;
    }
LAB_0408:
    return 1;
}

int far combataipath_actor_walk_path(CombatActor *actor, int ranged) {
    int iSpeedRem;
    int result;
    int savedX;
    int savedY;
    uint uTerrain;

    result = 1;
    if (ranged != 0) {
        savedX = actor->inner->grid_x;
        savedY = actor->inner->grid_y;
    }
    {
        int iDist;
        int iSteps;
        iDist = combatgrid_chebyshev_distance(actor->inner->grid_x, actor->inner->grid_y,
                                              actor->inner->pad_6[0], actor->inner->pad_6[1]);
        iSteps = g_acting_actor_speed;
        iSpeedRem = iSteps - iDist;
        if (iDist == 1) {
            g_bActorAdjacentToTarget = 1;
        } else {
            g_bActorAdjacentToTarget = 0;
        }
        while (iSteps != 0) {
            result = combataipath_step_to_target(actor, ranged);
            if ((actor->inner->pad_6[0] == actor->inner->grid_x) &&
                (actor->inner->pad_6[1] == actor->inner->grid_y)) {
                iSteps = 0;
            } else {
                iSteps = iSteps - 1;
            }
            if (ranged == 0) {
                uTerrain =
                    combatgrid_tile_terrain_field(actor->inner->grid_x, actor->inner->grid_y);
                switch (uTerrain) {
                case 3:
                    combatgrid_spread_tile_fx_line(actor->inner->grid_x, actor->inner->grid_y);
                    combat_actor_play_short_cine(actor, 0);
                    combatgrid_line_effect_propagate(actor->inner->grid_x, actor->inner->grid_y);
                    combat_arena_apply_damage(actor, 100, 0, 3, 0x200, 0);
                    break;
                case 8:
                    cspell_tile_trap_trigger(actor);
                    break;
                }
                combatgrid_step_search(actor, -1);
                if ((actor->inner->flags & CAF_DEAD) != 0) {
                    iSteps = 0;
                }
            }
        }
    }
    if (ranged == 0) {
        g_acting_actor_speed = iSpeedRem > 0 ? iSpeedRem : 0;
    } else {
        actor->inner->grid_x = (unsigned char)savedX;
        actor->inner->grid_y = (unsigned char)savedY;
    }
    return result;
}

void combataipath_select_target(CombatActor *actor, int max_dist, int target_mode) {
    int attackers;
    int iDist;
    int bMatch;
    int iStat;
    int approachX;
    int tile_y;
    int tile_x;
    int approachY;
    int maxAttackersPerTarget;
    int nOther;
    int nActive;
    int jj;
    int flags;
    int di;

    nActive = 0;
    nOther = 0;
    di = 0;
    if (di < g_nCombatActiveCount) {
        do {
            if (((flags = (char)g_pCombatActiveActors[di].inner->flags) & 2) == 0) {
                nActive++;
            }
            di++;
        } while (di < g_nCombatActiveCount);
    }
    di = 0;
    if (di < g_nCombatOtherCount) {
        do {
            if (((flags = (char)g_pCombatOtherActors[di].inner->flags) & 2) == 0) {
                nOther++;
            }
            di++;
        } while (di < g_nCombatOtherCount);
    }
    maxAttackersPerTarget = (nActive + nOther - 1) / nActive;
    if (maxAttackersPerTarget < 1) {
        maxAttackersPerTarget = 1;
    }

    if (actor->inner->target == (CombatActor *)0) {
        for (di = 0; di < g_nCombatActiveCount; di++) {
            iDist = combatgrid_chebyshev_distance(actor->inner->grid_x, actor->inner->grid_y,
                                                  g_pCombatActiveActors[di].inner->grid_x,
                                                  g_pCombatActiveActors[di].inner->grid_y);
            bMatch = 0;
            switch (target_mode) {
            case 0:
                bMatch = 1;
                break;
            case 1:
                if (stat_actor_get(&g_pCombatActiveActors[di], 7, 0) != 0)
                    bMatch = 1;
                break;
            case 3:
                if (combatenc_show_missile_stat_row(&g_pCombatActiveActors[di]) != 0)
                    bMatch = 1;
                break;
            case 2:
                iStat = combat_actor_stat_percent(&g_pCombatActiveActors[di], 1);
                if (iStat <= 50)
                    bMatch = 1;
                break;
            case 6:
                if (g_pCombatActiveActors[di].inner->target != (CombatActor *)0 &&
                    (g_pCombatActiveActors[di].inner->target->inner->flags & CAF_DEAD) != 0)
                    bMatch = 1;
                break;
            case 4:
                if (g_pCombatActiveActors[di].inner->target != (CombatActor *)0 &&
                    ((flags = (char)g_pCombatActiveActors[di].inner->target->inner->flags) & 2) ==
                        0)
                    bMatch = 1;
                break;
            case 5:
                if (g_pCombatActiveActors[di].inner->target == g_actors_B_origin)
                    bMatch = 1;
                break;
            }
            if (bMatch && ((flags = (char)g_pCombatActiveActors[di].inner->flags) & 2) == 0 &&
                iDist < max_dist) {

                if (g_pCombatActiveActors[di].inner->grid_x < actor->inner->grid_x) {
                    approachX = g_pCombatActiveActors[di].inner->grid_x + 1;
                } else {
                    approachX = g_pCombatActiveActors[di].inner->grid_x - 1;
                }
                tile_y = g_pCombatActiveActors[di].inner->grid_y;
                if (g_pCombatActiveActors[di].inner->grid_y < actor->inner->grid_y) {
                    tile_x = g_pCombatActiveActors[di].inner->grid_x;
                    approachY = g_pCombatActiveActors[di].inner->grid_y + 1;
                } else {
                    tile_x = g_pCombatActiveActors[di].inner->grid_x;
                    approachY = g_pCombatActiveActors[di].inner->grid_y - 1;
                }
                if (combatgrid_tile_is_blocked(approachX, tile_y) == 0 ||
                    combatgrid_tile_is_blocked(tile_x, approachY) == 0 ||
                    (actor->inner->grid_x == approachX && actor->inner->grid_y == tile_y) ||
                    (actor->inner->grid_x == tile_x && actor->inner->grid_y == approachY)) {

                    attackers = 0;
                    for (jj = 0; jj < g_nCombatOtherCount; jj++) {
                        if (g_pCombatOtherActors[jj].inner->target == &g_pCombatActiveActors[di] &&
                            ((flags = (char)g_pCombatOtherActors[jj].inner->flags) & 2) == 0) {
                            attackers++;
                        }
                    }
                    if (attackers < maxAttackersPerTarget) {
                        max_dist = iDist;
                        actor->inner->target = &g_pCombatActiveActors[di];
                        if (combatgrid_tile_is_blocked(approachX, tile_y) == 0 ||
                            (actor->inner->grid_x == approachX && actor->inner->grid_y == tile_y)) {
                            actor->inner->pad_6[0] = (uchar)approachX;
                            actor->inner->pad_6[1] = (uchar)tile_y;
                        } else {
                            actor->inner->pad_6[0] = (uchar)tile_x;
                            actor->inner->pad_6[1] = (uchar)approachY;
                        }
                    }
                }
            }
        }
    }

    if (actor->inner->target != 0 &&
        (actor->inner->grid_x != actor->inner->pad_6[0] ||
         actor->inner->grid_y != actor->inner->pad_6[1]) &&
        combataipath_actor_walk_path(actor, 0) == 0) {
        actor->inner->target = 0;
    }
}

void far combataipath_followup_action(CombatActor *actor) {
    int r;
    r = RND(100);
    if (r > 0x19) {
        combatenc_ai_attempt_melee(actor);
        return;
    }
    combatenc_set_flag8_clear_flag1(actor);
}

int combataipath_follow_tgt_check(CombatActor *actor, int max_dist, int target_mode) {
    int savedX;
    int savedY;
    int bFlag;
    int dist;
    int f;

    bFlag = 0;
    if (actor->inner->target != (CombatActor *)0x0) {
        dist = combatgrid_chebyshev_distance(actor->inner->grid_x, actor->inner->grid_y,
                                             actor->inner->target->inner->grid_x,
                                             actor->inner->target->inner->grid_y);
    } else {
        dist = 2;
    }
    savedX = actor->inner->grid_x;
    savedY = actor->inner->grid_y;
    if ((dist > 1) || (combatgrid_actors_ortho_adj(actor, actor->inner->target) == 0)) {
        if (cspell_stat_effect_find_type(actor, 3) != -1) {
            g_acting_actor_speed = 0;
        }
        actor->inner->target = (CombatActor *)0x0;
        combataipath_select_target(actor, max_dist, target_mode);
        bFlag = 1;
    }
    if (actor->inner->target != (CombatActor *)0x0) {
        dist = combatgrid_chebyshev_distance(actor->inner->grid_x, actor->inner->grid_y,
                                             actor->inner->target->inner->grid_x,
                                             actor->inner->target->inner->grid_y);
        if ((dist <= 1) && (combatgrid_actors_ortho_adj(actor, actor->inner->target) != 0) &&
            (((f = (signed char)actor->inner->flags) & 2) == 0)) {
            if (bFlag) {
                g_acting_actor_speed = 0;
            }
            combataipath_followup_action(actor);
        }
        return 1;
    } else {
        if ((actor->inner->grid_x == savedX) && (actor->inner->grid_y == savedY)) {
            return 0;
        }
    }
    return 1;
}

int far combataipath_low_health_action(CombatActor *actor) {
    int stat_pct;
    int dist;
    int r;
    stat_pct = combat_actor_stat_percent(actor, 1);
    combatenc_find_nearest_actor(actor, &dist);
    r = RND(100);
    if (stat_pct < 0x4b && dist > 2 && r < 0x50) {
        combatenc_actor_enter_defense(actor);
        return 1;
    }
    return 0;
}

int far combataipath_action_6(CombatActor *actor) {
    int r;
    r = combataipath_follow_tgt_check(actor, 6, 0);
    return r;
}

int far combataipath_action_100_1(CombatActor *actor) {
    int r;
    r = combataipath_follow_tgt_check(actor, 100, 1);
    return r;
}

int far combataipath_action_100_2(CombatActor *actor) {
    int r;
    r = combataipath_follow_tgt_check(actor, 100, 2);
    return r;
}

int far combataipath_action_60064(CombatActor *actor) {
    int r;
    r = combataipath_follow_tgt_check(actor, 100, 6);
    return r;
}

int far combataipath_action_50064(CombatActor *actor) {
    int r;
    r = combataipath_follow_tgt_check(actor, 100, 5);
    return r;
}

int far combataipath_action_30064(CombatActor *actor) {
    int r;
    r = combataipath_follow_tgt_check(actor, 100, 3);
    return r;
}

int far combataipath_action_40064(CombatActor *actor) {
    int r;
    r = combataipath_follow_tgt_check(actor, 100, 4);
    return r;
}

#define AI_ACTION_FN ((CombatAiActionFn far *)(g_combat_ai_action_table - 1))

#define AI_ACTION_INDEX ((short (*)[8])(g_combat_ai_action_table + 7))

void far combataipath_select_action(CombatActor *actor) {
    int(far * fn)(CombatActor *);

    int i = 0;
    int ret = 0;
    while (ret == 0 && i < 8 && actor->inner->pad_e[3] != 0) {
        fn = (int(far *)(
            CombatActor *))AI_ACTION_FN[AI_ACTION_INDEX[(signed char)actor->inner->pad_e[3]][i]];
        ret = fn(actor);
        i++;
    }
    if (ret == 0) {
        if (combat_actor_stat_percent(actor, 1) < 10) {
            if (RND(100) < 25) {
                if (RND(100) <= 20) {
                    if (combataiturn_pick_tile_or_attack(actor, 1, 0))
                        return;
                }
                combatenc_actor_enter_defense(actor);
                return;
            }
        }
        combataipath_follow_tgt_check(actor, 100, 0);
    }
}
