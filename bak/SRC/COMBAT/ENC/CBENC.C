#include <dos.h>
#include <stdlib.h>
#include <string.h>
#include "SRC/GAME/STATE/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/R3D/SCENE/ZONE.H"
#include "SRC/R3D/SPRITE/WORLDRND.H"
#include "structs.h"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "SRC/SYS/RAND.H"
#include "SRC/IO/RESOURCE.H"
#include "SRC/SYS/MEM.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/GAME/STATE/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/WORLD/ACTOR/ACTSPAWN.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "SRC/COMBAT/AI/CMBTAI.H"
#include "SRC/COMBAT/AI/CBTAI.H"
#include "SRC/COMBAT/AI/CBTAITRN.H"
#include "SRC/COMBAT/SPELL/CSPELL.H"
#include "SRC/COMBAT/AI/CBTAIACT.H"
#include "SRC/COMBAT/STATS/CBSTAT.H"
#include "defines.h"

char *combatenc_build_save_filename(int slot) {
    char prefix[5] = "comb";
    char slot_dec[6];
    char suffix[5] = ".dat";
    int i;

    itoa(slot, slot_dec, 10);
    for (i = 0; i < 5; i++)
        g_combat_save_filename[i] = prefix[i];
    strcat(g_combat_save_filename, slot_dec);
    strcat(g_combat_save_filename, suffix);
    return g_combat_save_filename;
}

short g_anStatCheckThreshold[9] = {10, 10, 10, 0, 0, 0, 0, 0, 0};
unsigned short g_ai_flee_threshold_table[10] = {0x0055, 0x0037, 0x002d, 0x0023, 0x0019,
                                                0x0014, 0x000a, 0x0005, 0x0005, 0x0000};

static short cbenc_dead_1410 = 0;

#include "structs.h"

void far combatenc_pty_load_chap_state(void) {
    int elapsed_time_units;
    long last_visit_time;
    int slot;

    g_combat_actors_B = (Combatant *)galloc_safe_zcalloc(0x299);
    g_inner_pool_B = (unsigned short)galloc_safe_zcalloc(0x9a);
    g_anim_pool_B = (AnimSlot *)galloc_safe_zcalloc(0x77);

    gstate_temp_file_read_at((unsigned char far *)g_chapter_roster, (unsigned long)GAM_ENC_ROSTER(g_encounter_id),
                             0xe);
    g_combat_count_B = 0;
    slot = 0;
    do {
        if (g_chapter_roster[slot] != -1) {
            g_combat_count_B++;
        }
        slot++;
    } while (slot < 7);
    slot = 0;
    if (slot < g_combat_count_B) {
        do {
            gstate_temp_file_read_at((unsigned char far *)&g_combat_actors_B[slot],
                                     GAM_COMBAT_ACTOR((long)g_chapter_roster[slot]), 0x5f);
            gstate_temp_file_read_at((unsigned char far *)((CombatantState *)g_inner_pool_B + slot),
                                     GAM_COMBAT_ACTOR_INNER((long)g_chapter_roster[slot]), 0x16);
            gstate_temp_file_read_at((unsigned char far *)&last_visit_time,
                                     (unsigned long)GAM_ENC_FOUGHT_TIME(g_encounter_id), 4);
            if (last_visit_time != 0) {
                elapsed_time_units = (int)((g_gameState.game_time - last_visit_time) / 0x708);
                stat_combatant_modify(&g_combat_actors_B[slot], 0x10,
                                      (long)(elapsed_time_units << 8), 100);
            }
            slot++;
        } while (slot < g_combat_count_B);
    }
    slot = 0;
    do {
        g_combat_actors_B[slot].inner = (CombatantState *)g_inner_pool_B + slot;
        g_combat_actors_B[slot].inner->target = (Combatant *)0;
        slot++;
    } while (slot < 7);
    slot = 0;
    if (slot < g_combat_count_B) {
        do {
            g_combat_actors_B[slot].name = (char *)galloc_safe_zcalloc(0x20);
            combatenc_mnames_lookup_dest(g_combat_actors_B[slot].inner->creatureType,
                                         &g_combat_actors_B[slot].name);
            g_combat_actors_B[slot].actor_record =
                actorspawn_objfixed(100, (long)slot, (long)(int)g_encounter_id);
            g_combat_actors_B[slot].inner->statusHead = -1;
            slot++;
        } while (slot < g_combat_count_B);
    }
    combatenc_init_actor_anim_pool();
    g_actors_B_origin = g_combat_actors_B;
    return;
}

#include "structs.h"

void combatenc_persist_actors_to_temp(int srcEncounterId) {
    short roster[7];
    int i;

    gstate_temp_file_read_at((unsigned char far *)roster, (unsigned long)(unsigned)GAM_ENC_ROSTER(srcEncounterId),
                             0xe);
    g_pendingTempWriteRegion = TWR_ENCOUNTER_STATE;
    gstate_temp_file_write_at((unsigned char far *)roster, (unsigned long)(unsigned)GAM_ENC_ROSTER(g_encounter_id),
                              0xe);
    i = 0;
    if (i < g_combat_count_B) {
        do {
            g_pendingTempWriteRegion = TWR_COMBAT_ACTOR;
            gstate_temp_file_write_at((unsigned char far *)&g_combat_actors_B[i],
                                      GAM_COMBAT_ACTOR((long)roster[i]), 0x5f);
            g_pendingTempWriteRegion = TWR_COMBAT_ACTOR_INNER;
            gstate_temp_file_write_at((unsigned char far *)g_combat_actors_B[i].inner,
                                      GAM_COMBAT_ACTOR_INNER((long)roster[i]), 0x16);
            i++;
        } while (i < g_combat_count_B);
    }
    return;
}

void far combatenc_init_actor_anim_pool(void) {
    int i;

    for (i = 0; i < g_combat_count_B; i++) {
        combat_actor_rsrc_load_3values((g_combat_actors_B[i].inner)->creatureType,
                                       g_abCombatInnerPoolB[i]);
        g_anim_pool_B[i].sprite_header = g_abCombatInnerPoolB[i];
    }
    return;
}

void far combatenc_vis_actors_call_rev(void) {
    int i;

    for (i = g_combat_count_B - 1; i >= 0; i--) {
        combat_actor_release_anim_images((g_combat_actors_B[i].inner)->creatureType);
    }
    return;
}

void far combatenc_mnames_lookup_dest(int index, char **p_dest) {
    unsigned int blob_size;
    int count;
    char *blob;
    ResFile *file;
    int *offsets;

    file = res_fopen("mnames.dat", "rb");
    res_fread(&count, 2, 1, file);
    offsets = galloc_safe_zcalloc(count << 1);
    res_fread(offsets, 2, count, file);
    res_fread(&blob_size, 2, 1, file);
    blob = galloc_safe_zcalloc(blob_size);
    res_fread(blob, 1, blob_size, file);
    res_fclose(file);
    offsets[index] += (int)blob;
    strcpy(*p_dest, (char *)offsets[index]);
    galloc_zfree(blob);
    galloc_zfree(offsets);
    return;
}

#include "structs.h"

void far combatenc_release_actors(void) {
    int i;

    if (g_encounter_id != 0) {
        combatenc_persist_actors_to_temp(g_encounter_id);
    }
    combatenc_vis_actors_call_rev();
    combatenc_clear_pty_grid_occ();
    for (i = g_combat_count_B - 1; i >= 0; i--) {
        g_combat_actors_B[i].actor_record->needsFlush = TRUE;
        g_combat_actors_B[i].actor_record->canFlush = TRUE;
        actorspawn_destroy_and_persist(g_combat_actors_B[i].actor_record);
        galloc_zfree(g_combat_actors_B[i].name);
    }
    g_actors_B_origin = (Combatant *)0;
    galloc_zfree(g_anim_pool_B);
    galloc_zfree((void *)g_inner_pool_B);
    galloc_zfree(g_combat_actors_B);
    return;
}

#include "structs.h"

void far combatenc_save_state(void) {
    char *filename;
    ResFile *file;
    int i;

    filename = combatenc_build_save_filename(g_encounter_id);
    file = res_fopen(filename, "wb");
    res_fwrite(&g_combat_count_B, 2, 1, file);
    i = 0;
    if (i < g_combat_count_B) {
        do {
            res_fwrite(&g_combat_actors_B[i], 0x5f, 1, file);
            res_fwrite(g_combat_actors_B[i].inner, 0x16, 1, file);
            i++;
        } while (i < g_combat_count_B);
    }
    res_fclose(file);
    combatgrid_save_traps_terr(g_encounter_id);
    combatenc_persist_actors_to_temp(g_encounter_id);
    return;
}

void combatenc_draw_actor_roster_idx(Combatant *actor) {
    short x;
    short y;
    char buf[10];
    int value;

    for (value = 0; value < g_combat_count_B; value++) {
        if (&g_combat_actors_B[value] == actor) {
            itoa(value, buf, 10);
            x = g_nBillboardScrX;
            y = g_nBillboardScrY;
            {
                short bx = g_graphics_context.clip.xmin + 2;
                if (x < bx) {
                    x = bx;
                } else {
                    bx = (g_graphics_context.clip.xmax + -2) - font_text_width_ds(buf);
                    if (x > bx) {
                        x = bx;
                    }
                }
            }
            {
                short bx = g_graphics_context.clip.ymin + 2;
                if (y < bx) {
                    y = bx;
                } else {
                    bx = g_graphics_context.clip.ymax + -0xc;
                    if (y > bx) {
                        y = bx;
                    }
                }
            }
            g_graphics_context.bText_fg_color = 0;
            font_draw_text_ds(buf, x, y);
        }
    }
}

#include "structs.h"
#include <stdlib.h>

static void far combatenc_stat_roll_draw_line(char *label, int stat_val, int *px, int *py, int flag,
                                              int *pcount) {
    char buf[10];
    int roll;
    int stat;

    stat = (int)stat_actor_get(g_current_actor, 8, 0);
    roll = (int)RND(100);
    if (roll > stat)
        return;
#ifdef V102CD
    if (*px >= 0x10e)
        return;
#endif

    *pcount = 1;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaFrontPageBase;
    font_draw_text_ds(label, *px, *py);
    itoa(stat_val, buf, 10);
    font_draw_text_ds(buf, *px + 50, *py);
    if (flag)
        font_draw_text_ds("%", *px + 61, *py);

    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    font_draw_text_ds(label, *px, *py);
    font_draw_text_ds(buf, *px + 50, *py);
    if (flag)
        font_draw_text_ds("%", *px + 61, *py);

    *py += 10;
    if (*py > 0x5a) {
        *py = 0x44;
        *px += 100;
    }
}

#include "structs.h"

void far combatenc_anim_actor_stat_rolls(Combatant *actor) {
    int stat_anim_state[3];

    stat_anim_state[2] = 0x44;
    stat_anim_state[1] = 0x46;
    stat_anim_state[0] = 0;
    if (actor != (Combatant *)0x0) {
        g_graphics_context.bText_fg_color = g_graphics_context.bText_bg_color = '\0';
        screen_cursor_hide();
        g_gameState.nEvtArgActor0 = g_current_actor->charSlot + -1;
        g_gameState.nEvtArgAux1 = actor->inner->creatureType;
        dialog_play_record(0x84, 0);
        while (stat_anim_state[0] == 0) {
            combatenc_stat_roll_draw_line("Health:", (int)stat_actor_get(actor, 0, 0),
                                          &stat_anim_state[1], &stat_anim_state[2], 0,
                                          &stat_anim_state[0]);
            combatenc_stat_roll_draw_line("Stamina:", (int)stat_actor_get(actor, 1, 0),
                                          &stat_anim_state[1], &stat_anim_state[2], 0,
                                          &stat_anim_state[0]);
            combatenc_stat_roll_draw_line("Speed:", (int)stat_actor_get(actor, 2, 0),
                                          &stat_anim_state[1], &stat_anim_state[2], 0,
                                          &stat_anim_state[0]);
            combatenc_stat_roll_draw_line("Strength:", (int)stat_actor_get(actor, 3, 0),
                                          &stat_anim_state[1], &stat_anim_state[2], 0,
                                          &stat_anim_state[0]);
            if (combatenc_show_missile_stat_row(actor) != 0) {
                combatenc_stat_roll_draw_line("Missle:", (int)stat_actor_get(actor, 5, 0),
                                              &stat_anim_state[1], &stat_anim_state[2], 1,
                                              &stat_anim_state[0]);
            }
            combatenc_stat_roll_draw_line("Melee:", (int)stat_actor_get(actor, 6, 0),
                                          &stat_anim_state[1], &stat_anim_state[2], 1,
                                          &stat_anim_state[0]);
            if (combatenc_actor_can_cast_spells(actor, 0) != 0) {
                combatenc_stat_roll_draw_line("Cast:", (int)stat_actor_get(actor, 7, 0),
                                              &stat_anim_state[1], &stat_anim_state[2], 1,
                                              &stat_anim_state[0]);
            }
            combatenc_stat_roll_draw_line("Defense:", (int)stat_actor_get(actor, 4, 0),
                                          &stat_anim_state[1], &stat_anim_state[2], 1,
                                          &stat_anim_state[0]);
        }
        dialog_play_record(0x85, 0);
    }
}

#include "structs.h"

void far combatenc_place_b_free_tiles(void) {
    int i;

    for (i = 0; i < g_combat_count_B; i++) {
        combat_actor_place_on_free_tile(&g_combat_actors_B[i]);
    }
    return;
}

void combatenc_clear_pty_grid_occ(void) {
    int i;

    for (i = 0; i < g_combat_count_B; i++) {
        combatgrid_tile_set_word(g_combat_actors_B[i].inner->gridX,
                                 g_combat_actors_B[i].inner->gridY, 0);
    }
    return;
}

#include "structs.h"

void far combatenc_apply_flee_tile_team(int team_id) {
    int i;

    i = 0;
    if (i < g_nCombatOtherCount) {
        do {
            if ((g_pCombatOtherActors[i].inner->creatureType == team_id) &&
                (!((signed char)g_pCombatOtherActors[i].inner->flags & CAF_DEAD))) {
                combatenc_actor_flee_tile_east(&g_pCombatOtherActors[i]);
            }
            i = i + 1;
        } while (i < g_nCombatOtherCount);
    }
    return;
}

#include "structs.h"

int far combatenc_actor_stat_above_table(int threshold_idx, Combatant *actor) {
    return (unsigned int)((int)stat_actor_get(actor, 0, 0) > g_anStatCheckThreshold[threshold_idx]);
}

#include "structs.h"

int far combatenc_actor_has_spell_1or4(Combatant *actor) {
    return cbstat_find_intact_equip_cat(actor, 1) != (ItemRecord far *)0 ||
           cbstat_find_intact_equip_cat(actor, 4) != (ItemRecord far *)0;
}

int combatenc_actor_id_eq_22(Combatant *actor) {
    int flag = 0;
    int creatureType = actor->inner->creatureType;
    if (creatureType == CREATURE_BLACK_SLAYER)
        flag = 1;
    return flag;
}

#include "structs.h"

Combatant *far combatenc_find_nearest_actor(Combatant *from, int *out_dist) {
    Combatant *best_actor;
    int best_dist;
    int i;
    int did_swap;

    best_actor = (Combatant *)0;
    best_dist = 100;
    did_swap = 0;
    if (combatenc_is_encounter_actor(from) == 0) {
        combat_arena_swap_tgt_state();
        did_swap = 1;
    }
    i = 0;
    if (i < g_nCombatActiveCount) {
        do {
            Combatant *cand = &g_pCombatActiveActors[i];
            int dist = combatgrid_chebyshev_distance(from->inner->gridX, from->inner->gridY,
                                                     cand->inner->gridX, cand->inner->gridY);
            if (dist < best_dist) {
                if (!((int)(signed char)cand->inner->flags & CAF_DEAD)) {
                    best_dist = dist;
                    best_actor = cand;
                }
            }
            i++;
        } while (i < g_nCombatActiveCount);
    }
    if (did_swap) {
        combat_arena_swap_tgt_state();
    }
    if (out_dist != (int *)0) {
        *out_dist = best_dist;
    }
    return best_actor;
}

int far combatenc_compute_hit_chance(Combatant *attacker, Combatant *target, int base_skill,
                                     int quarrel_kind) {
    int dist;
    int result;
    ItemRecord far *rec = 0;
    ItemSlot far *slot;

    dist = combatgrid_chebyshev_distance(attacker->inner->gridX, attacker->inner->gridY,
                                         target->inner->gridX, target->inner->gridY);
    if (--dist < 0) {
        dist = 0;
    }
    result = base_skill - dist * 2;

    slot = alloc_far(1, 0);
    slot->item_id = 0xff;
    switch (quarrel_kind) {
    case 0:
    case 3:
    case 4:
    case 7:
    case 9:
        slot->item_id = 0x24;
        break;
    case 1:
    case 8:
        slot->item_id = 0x25;
        break;
    case 2:
        slot->item_id = 0x26;
        break;
    }
    if (slot->item_id != 0xff) {
        rec = itemtbl_record_ptr(slot);
        result += rec->nDefense_or_range_close;
    }
    if (result < 0) {
        result = 0;
    }
    _freemem(slot);
    return result;
}

int combatenc_skill_check_random(Combatant *attacker, Combatant *target, int base_skill,
                                 int quarrel_kind) {
    int hit_chance;
    int rand_val;

    hit_chance = combatenc_compute_hit_chance(attacker, target, base_skill, quarrel_kind);
    rand_val = RND(100);
    return rand_val < hit_chance ? hit_chance : 0;
}

#include "structs.h"

int far combatenc_show_missile_stat_row(Combatant *actor) {
    int nearestDist;

    if ((actor != (Combatant *)0x0) &&
        (combatgrid_tile_terrain_field(actor->inner->gridX, actor->inner->gridY) != 1)) {
        combatenc_find_nearest_actor(actor, &nearestDist);
        if ((((combat_actor_cnt_qrls_kind(actor, -1) != 0) &&
              (cbstat_find_intact_equip_cat(actor, 2) != (ItemRecord far *)0x0)) ||
             (actor->inner->creatureType == 0x1a)) &&
            ((1 < nearestDist && (stat_actor_get(actor, 5, 0) != 0)))) {
            return 1;
        }
    }
    return 0;
}

int far combatenc_actor_can_cast_spells(Combatant *actor, int find_nearest) {
    int total_stats;
    int nearest_dist;

    total_stats = 0;
    if (!actor)
        return 0;
    if (combatgrid_tile_terrain_field(actor->inner->gridX, actor->inner->gridY) == 1)
        return 0;
    if (g_gameState.nChapter == 8 && actor->charSlot != 0 &&
        itemtbl_inv_count_by_kind(actor->actor_record, 1) == 0)
        return 0;
    if (find_nearest != 0) {
        combatenc_find_nearest_actor(actor, &nearest_dist);
    } else {
        nearest_dist = 100;
    }
    {
        int i;
        for (i = 0; i < 9; i++) {
            total_stats += combatenc_actor_stat_above_table(i, actor);
        }
    }
    return stat_actor_get(actor, 7, 0) != 0 && total_stats != 0 && nearest_dist >= 2;
}

#include "structs.h"

void far combatenc_ai_pick_target_by_role(Combatant *actor, int max_distance,
                                          unsigned int role_filter, int min_party_clearance) {
    int accepted;
    int dist;
    int pct;
    int flagtmp;
    int i;

    actor->inner->target = (Combatant *)0;
    for (i = 0; i < g_nCombatActiveCount; i++) {
        dist = combatgrid_chebyshev_distance(actor->inner->gridX, actor->inner->gridY,
                                             g_pCombatActiveActors[i].inner->gridX,
                                             g_pCombatActiveActors[i].inner->gridY);
        if (dist > max_distance)
            continue;
        if ((flagtmp = (char)g_pCombatActiveActors[i].inner->flags) & CAF_DEAD)
            continue;
        if (combatenc_party_within_cheby(&g_pCombatActiveActors[i], min_party_clearance) != 0)
            continue;
        accepted = 0;
        switch (role_filter) {
        default:
            goto skip;
        case 0:
        accept:
            accepted = 1;
            goto skip;
        case 1:
            if (combatenc_actor_can_cast_spells(&g_pCombatActiveActors[i], 0) != 0)
                goto accept;
            goto skip;
        case 3:
            if (combatenc_show_missile_stat_row(&g_pCombatActiveActors[i]) != 0)
                goto accept;
            goto skip;
        case 2:
            pct = combat_actor_stat_percent(&g_pCombatActiveActors[i], 1);
            if (pct <= 50)
                accepted = 1;
            break;
        case 6:
            if (g_pCombatActiveActors[i].inner->target != (Combatant *)0 &&
                (g_pCombatActiveActors[i].inner->target->inner->flags & CAF_DEAD) != 0)
                goto accept;
            goto skip;
        case 4:
            if (g_pCombatActiveActors[i].inner->target != (Combatant *)0 &&
                ((flagtmp = (char)g_pCombatActiveActors[i].inner->target->inner->flags) &
                 CAF_DEAD) == 0)
                goto accept;
            goto skip;
        case 5:
            if (g_pCombatActiveActors[i].inner->target != g_actors_B_origin)
                goto skip;
            goto accept;
        }
    skip:
        if (accepted) {
            actor->inner->target = &g_pCombatActiveActors[i];
            max_distance = dist;
        }
    }
}

#include <stdlib.h>

void far combatenc_actor_flee_tile_east(Combatant *actor) {
    int v;
    int best_y;
    int x;
    int y;

    best_y = 0;
    if ((v = (signed char)actor->inner->morale) == 0)
        return;
    actor->inner->flags |= CAF_FLEE;
    actor->inner->target = (Combatant *)0;
    for (x = 0; x < 8; x++) {
        for (y = 0; y < 13; y++) {
            if (!combatgrid_tile_is_blocked((char)x, (char)y)) {
                if (y > best_y) {
                    if (RND(100) > 50) {
                        actor->inner->destX = (unsigned char)x;
                        actor->inner->destY = (unsigned char)y;
                        best_y = y;
                    }
                }
            }
        }
    }
}

void far combatenc_ai_morale_flee_check(Combatant *actor) {
    int threshold;
    int rand_pct;
    int morale_adj;
    int index;

    if (actor->inner->morale == 0xff)
        return;
    if (g_game_mode == 2)
        return;

    index = combat_actor_stat_percent(actor, 1) / 10 - 1;

    morale_adj = 8 - (signed char)actor->inner->morale;
    index += morale_adj;

    if (index > 9)
        index = 9;

    threshold = g_ai_flee_threshold_table[index];

    rand_pct = RND(100);

    if (threshold <= rand_pct)
        return;

    if (actor->inner->morale == 0)
        return;

    combatenc_actor_flee_tile_east(actor);
}

#include "structs.h"

int far combatenc_actor_can_act(Combatant *actor, int strict) {
    int result;

    result = 1;
    if (strict != 0) {
        if (!((int)(signed char)actor->inner->flags & CAF_READY) ||
            (actor->inner->flags & CAF_DEAD)) {
            result = 0;
        }
    }
    if (cspell_stat_effect_find_type(actor, 3) != -1)
        goto L_clear;
    if (cspell_stat_effect_find_type(actor, 0xd) != -1)
        goto L_clear;
    if (cspell_stat_effect_find_type(actor, 1) == -1)
        goto L_done;
L_clear:
    result = 0;
L_done:
    return result;
}

#include "structs.h"

void far combatenc_pick_next_active_actor(void) {
    int i;
    Combatant *actor;
    Combatant sentinel;
    Combatant *cand;

    i = 0;
    do {
        (sentinel.stats + i)->max = '\0';
        sentinel.stats[i].base = '\0';
        sentinel.stats[i].cached = '\0';
        sentinel.stats[i].frac = '\0';
        sentinel.stats[i].perm_mod = '\0';
        i = i + 1;
    } while (i < 0x10);
    sentinel.stats[0].max = '\x01';
    i = 0;
    do {
        stat_actor_get(&sentinel, i, 0);
        i = i + 1;
    } while (i < 0x10);
    actor = &sentinel;
    i = 0;
    while (i < g_nCombatOtherCount) {
        cand = &g_pCombatOtherActors[i];
        if ((int)stat_actor_get(cand, 2, 0) > (int)stat_actor_get(actor, 2, 0)) {
            if (combatenc_actor_can_act(&g_pCombatOtherActors[i], 1) != 0) {
                actor = &g_pCombatOtherActors[i];
            }
        }
        i = i + 1;
    }
    if (&sentinel == actor) {
        actor = (Combatant *)0x0;
    }
    g_picked_actor = actor;
    if (g_picked_actor != (Combatant *)0x0) {
        g_acting_actor_speed = stat_actor_get(g_picked_actor, 2, 0);
    } else {
        g_acting_actor_speed = 0;
    }
    return;
}

void combatenc_refresh_actor_flags(void) {
    int i;

    i = 0;
    if (i < g_nCombatOtherCount) {
        do {
            g_pCombatOtherActors[i].inner->flags |= CAF_READY;
            g_pCombatOtherActors[i].inner->flags &= ~CAF_DEFEND_CMD;
            if ((g_pCombatOtherActors[i].inner->target != (Combatant *)0x0) &&
                ((g_pCombatOtherActors[i].inner->target->inner->flags & CAF_DEAD) != 0)) {
                g_pCombatOtherActors[i].inner->target = (Combatant *)0x0;
            }
            i = i + 1;
        } while (i < g_nCombatOtherCount);
    }
    return;
}

#include "structs.h"

#include <dos.h>

void far combatenc_ai_suicide_on_arrival(Combatant *actor) {
    int hit;
    Combatant tmpActor;
    CombatantState tmpInner;

    hit = 0;
    if (g_acting_actor_speed == 0) {
        g_acting_actor_speed = 1;
    }
    combataipath_actor_walk_path(actor, 0);
    if ((actor->inner->gridX == actor->inner->destX) &&
        (actor->inner->gridY == actor->inner->destY)) {
        combatgrid_tile_set_word(actor->inner->gridX, actor->inner->gridY, 0);
        tmpActor.inner = &tmpInner;
        tmpActor.actor_record = (Actor far *)0x0;
        tmpInner = *(CombatantState far *)MK_FP(FP_SEG(g_pMapIconsTable), (unsigned)actor->inner);
        world_rndr_ranged_attack_anim(actor, &tmpActor, &hit, tmpInner.creatureType, 0x96, -1);
        combat_arena_actor_die(actor, 0);
    }
    return;
}

void combatenc_set_flag8_clear_flag1(Combatant *actor) {
    actor->inner->flags |= CAF_PARRY;
    actor->inner->flags &= ~CAF_READY;
}

#include "structs.h"

void far combatenc_actor_enter_defense(Combatant *actor) {
    Combatant *to;
    int healAmt;
    int sumMax;

    sumMax = (int)((unsigned int)actor->stats->max + (unsigned int)(actor->stats + 1)->max);
    healAmt = sumMax / 0x1e;
    if (healAmt < 1) {
        healAmt = 1;
    }
    if (!actor->charSlot ||
        ((!*(char *)((int)g_gameState.aSkillTrainRate + 5 + actor->charSlot * 7) &&
          !*(char *)((int)g_gameState.aSkillTrainRate + 6 + actor->charSlot * 7)) &&
         (!*(char *)((int)g_gameState.aSkillTrainRate + 7 + actor->charSlot * 7) &&
          ((!*(char *)((int)g_gameState.aSkillTrainRate + 8 + actor->charSlot * 7) &&
            !*(char *)((int)g_gameState.aSkillTrainRate + 10 + actor->charSlot * 7)) &&
           !*(char *)((int)g_gameState.aSkillTrainRate + 0xb + actor->charSlot * 7))))) {
        stat_combatant_modify(actor, 0x10, (long)(int)(healAmt << 8), 0x50);
    }
    g_acting_actor_speed = 0;
    actor->inner->flags |= CAF_DEFEND_CMD;
    actor->inner->flags &= ~CAF_READY;
    stat_actor_get(actor, 2, 0);
    stat_actor_get(actor, 0, 0);
    stat_actor_get(actor, 1, 0);
    to = combatenc_find_nearest_actor(actor, (int *)0x0);
    combat_actor_anim0_if_not_dead(actor, combat_actor_heading_from_to(actor, to));
    return;
}

#include "structs.h"

void far combatenc_ai_attempt_melee(Combatant *actor) {
    int rand_roll;
    int total_score;
    ItemRecord far *weapon_rec;

    if ((actor->inner->target != (Combatant *)0) &&
        ((actor->inner->target->inner->flags & CAF_DEAD) == 0)) {
        rand_roll = RND(100);
        weapon_rec = cbstat_find_intact_equip_cat(actor, 1);
        total_score = stat_actor_get(actor, 6, 0) + weapon_rec->nDefense_or_range_close;
        if (rand_roll > total_score)
            goto L_resolve;
        if ((int)g_acting_actor_speed < 2)
            goto L_resolve;
        combat_arena_melee_attack(actor, actor->inner->target, 0);
        return;
    L_resolve:
        combat_arena_resolve_melee_swing(actor, actor->inner->target, 0);
    }
}

#include "structs.h"

int far combatenc_count_active_enemies(void) {
    int anyEngaged;
    int count;
    int i;

    anyEngaged = 0;
    count = 0;
    for (i = 0; i < g_nCombatOtherCount; i = i + 1) {
        if (g_pCombatOtherActors[i].charSlot != '\0') {
            anyEngaged = 1;
        }
    }
    for (i = 0; i < g_nCombatOtherCount; i = i + 1) {
        if ((((g_pCombatOtherActors[i].inner->flags & CAF_DEAD) != 0) &&
             (!((signed char)g_pCombatOtherActors[i].inner->flags & CAF_FLEE))) &&
            (((anyEngaged && (g_pCombatOtherActors[i].charSlot != '\0')) || (!anyEngaged)))) {
            count = count + 1;
        }
    }
    return count;
}

#include "structs.h"

int far combatenc_party_within_cheby(Combatant *actor, int range) {
    int count;
    int i;
    int dist;

    count = 0;
    if (range != 0) {
        for (i = 0; i < g_combat_count_B; i = i + 1) {
            dist = combatgrid_chebyshev_distance(actor->inner->gridX, actor->inner->gridY,
                                                 g_combat_actors_B[i].inner->gridX,
                                                 g_combat_actors_B[i].inner->gridY);
            if (dist < range) {
                count++;
            }
        }
    }
    return count;
}

int combatenc_alive_actor_count(void) {
    int count;
    int i;
    int v;

    count = 0;
    for (i = 0; i < g_nCombatOtherCount; i++) {
        if (((v = (signed char)g_pCombatOtherActors[i].inner->flags) & CAF_DEAD) == 0) {
            count++;
        }
    }
    return count;
}

int combatenc_is_encounter_actor(Combatant *actor) {
    int i;

    for (i = 0; i < g_nCombatOtherCount; i++) {
        if (&g_pCombatOtherActors[i] == actor) {
            return 1;
        }
    }
    return 0;
}

void combatenc_refr_actor_flags_far(void) {
    combatenc_refresh_actor_flags();
}

#include "structs.h"

void far combatenc_ai_sel_execute_action(Combatant *actor) {
    combatenc_ai_morale_flee_check(actor);
    if (actor->inner->flags & CAF_FLEE) {
        combatenc_ai_suicide_on_arrival(actor);
    } else {
        switch (actor->inner->creatureType) {
        case 0x13:
            combataiact_pick_melee_or_missl(actor);
            break;
        case 0x31:
            combataiact_random_move_attack(actor);
            break;
        case 0x29:
        case 0x2a:
        case 0x2b:
        case 0x39:
            combataiact_ranged_attack_turn(actor);
            break;
        case 0x38:
            combataiact_actor_melee_attack(actor);
            break;
        case 0x1d:
        case 0x1f:
        case 0x20:
        case 0x21:
            combataiact_action_charge_near(actor);
            break;
        case 0x1c:
            combataiact_melee_random_attack(actor);
            break;
        case 0x36:
            combataiact_ranged_attack(actor);
            break;
        default:
            if (combatenc_actor_can_cast_spells(actor, 0)) {
                combat_ai_take_turn(actor);
            } else if (combatenc_show_missile_stat_row(actor)) {
                combataiturn_take_actor_turn(actor);
            } else {
                combataipath_select_action(actor);
            }
            break;
        }
    }
}

#include "structs.h"

void combatenc_ai_run_turn(void) {
    if (((g_picked_actor == (Combatant *)0x0) ||
         ((g_picked_actor->inner->flags & CAF_DEAD) == 0)) &&
        (g_picked_actor != (Combatant *)0x0)) {
        if ((g_picked_actor->inner->target != (Combatant *)0x0) &&
            ((g_picked_actor->inner->target->inner->flags & CAF_DEAD) != 0)) {
            g_picked_actor->inner->target = (Combatant *)0x0;
        }
        combatenc_ai_sel_execute_action(g_picked_actor);
        if ((combat_actor_enc_lookup_field2(g_picked_actor) != 7) &&
            !((signed char)g_picked_actor->inner->flags & CAF_FLEE)) {
            combatenc_actor_face_target(g_picked_actor);
        }
        g_picked_actor->inner->flags &= ~CAF_READY;
    }
}

#include "structs.h"

void far combatenc_actor_face_target(Combatant *actor) {
    Combatant *to;

    if (actor->inner->target == (Combatant *)0x0) {
        to = combatenc_find_nearest_actor(actor, (int *)0x0);
    } else {
        to = actor->inner->target;
    }
    if (!((int)(signed char)actor->inner->flags & CAF_DEAD)) {
        combat_actor_anim0_if_not_dead(actor, combat_actor_heading_from_to(actor, to));
    }
}

Actor far *combatenc_corpse_tbl_spawn_actor(long record_id, int slot) {
    short rec[7];
    Actor far *spawned;

    spawned = (Actor far *)0;
    gstate_temp_file_read_at((unsigned char far *)rec, GAM_ENC_ROSTER(record_id), 0xe);
    if (slot < 7 && rec[slot] != -1) {
        spawned = actorspawn_objfixed(100, (long)slot, record_id);
    }
    return spawned;
}

void combatenc_spawns_load_zones_tmp(void) {
    ResFile *file;
    int i;
    int zone;
    int gidx;
    int count;
    char *filename;
    int index[7];
    Combatant actor;
    CombatantState inner;

    gidx = 0;
    zone = 0;
    do {
        for (i = 0; i < 7; i++)
            index[i] = -1;
        filename = combatenc_build_save_filename(zone);
        file = res_fopen(filename, "rb");
        if (file != (ResFile *)0) {
            res_fread(&count, 2, 1, file);
        } else {
            count = 0;
        }
        for (i = 0; i < count; i++) {
            index[i] = gidx;
            res_fread(&actor, 0x5f, 1, file);
            res_fread(&inner, 0x16, 1, file);
            actor.stats[0].base = actor.stats[0].max;
            actor.stats[1].base = actor.stats[1].max;
            inner.flags = CAF_READY;
            g_pendingTempWriteRegion = TWR_COMBAT_ACTOR;
            gstate_temp_file_write_at((unsigned char far *)&actor, GAM_COMBAT_ACTOR((long)gidx),
                                      0x5f);
            g_pendingTempWriteRegion = TWR_COMBAT_ACTOR_INNER;
            gstate_temp_file_write_at((unsigned char far *)&inner,
                                      GAM_COMBAT_ACTOR_INNER((long)gidx), 0x16);
            gidx++;
        }
        res_fclose(file);
        g_pendingTempWriteRegion = TWR_ENCOUNTER_STATE;

        gstate_temp_file_write_at((unsigned char far *)index,
                                  (unsigned long)(unsigned)GAM_ENC_ROSTER(zone), 0xe);
        zone++;

    } while (zone < 700);
}

void combatenc_saves_migr_all_slots(void) {
    char *filename;
    ResFile *file;
    ResFile *outStream;
    int encounterId;
    int j;
    int gidx;
    int count;
    int index[7];
    char actorBuf[0x5f];
    char innerBuf[0x16];

    gidx = 0;
    encounterId = 0;
    do {
        int i;
        for (i = 0; i < 7; i++)
            index[i] = -1;

        filename = combatenc_build_save_filename(encounterId);
        file = res_fopen(filename, "rb");
        if (file == (ResFile *)0)
            goto L_null;
        filename[3] = 'n';
        outStream = res_fopen(filename, "wb");
        res_fread(&count, 2, 1, file);
        res_fwrite(&count, 2, 1, outStream);
        goto L_shared;
    L_null:
        count = 0;
        outStream = (ResFile *)0;
    L_shared:
        j = 0;
        if (j < count) {
            do {
                index[j] = gidx;
                res_fread(actorBuf, 0x5e, 1, file);
                res_fread(innerBuf, 0x16, 1, file);
                actorBuf[0x58] = 0;
                res_fwrite(actorBuf, 0x5f, 1, outStream);
                res_fwrite(innerBuf, 0x16, 1, outStream);
                gidx++;
                j++;
            } while (j < count);
        }
        res_fclose(file);
        if (outStream != (ResFile *)0)
            res_fclose(outStream);
        encounterId++;
    } while (encounterId < 700);
}


unsigned char g_bssgap_5128[2];
Combatant *g_combat_actors_B;
AnimSlot *g_anim_pool_B;
int g_combat_count_B;
unsigned char g_bssgap_511e[4];
Combatant *g_actors_B_origin;
short g_chapter_roster[7];
/* Per-actor sprite tables: 11 near ImageRecord ** asset-table entries per row
   (22 bytes/row). Entries [2] and [10] of each row are never written (BSS zero). */
ImageRecord **g_abCombatInnerPoolB[7][11];
char g_combat_save_filename[14];
unsigned short g_inner_pool_B;

void combatenc_chap_load_party_grn(int chapter) {
    unsigned char actorBuf[95];
    unsigned char innerBuf[22];
    short roster[7];
    int i;
    int count;

    gstate_temp_file_read_at((unsigned char far *)roster, (unsigned long)(unsigned)GAM_ENC_ROSTER(chapter), 0xe);

    count = 0;
    i = 0;
    do {
        if (roster[i] != -1)
            count++;
        i++;
    } while (i < 7);

    i = 0;
    if (i < count) {
        do {
            gstate_temp_file_read_at((unsigned char far *)actorBuf, GAM_COMBAT_ACTOR((long)roster[i]), 0x5f);
            gstate_temp_file_read_at((unsigned char far *)innerBuf, GAM_COMBAT_ACTOR_INNER((long)roster[i]),
                                     0x16);
            innerBuf[8] = 1;
            actorBuf[9] = actorBuf[8];
            g_pendingTempWriteRegion = TWR_COMBAT_ACTOR;
            gstate_temp_file_write_at((unsigned char far *)actorBuf, GAM_COMBAT_ACTOR((long)roster[i]),
                                      0x5f);
            g_pendingTempWriteRegion = TWR_COMBAT_ACTOR_INNER;
            gstate_temp_file_write_at((unsigned char far *)innerBuf,
                                      GAM_COMBAT_ACTOR_INNER((long)roster[i]), 0x16);
            i++;
        } while (i < count);
    }
}
