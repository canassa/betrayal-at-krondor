#include <dos.h>
#include <stdio.h>
#include <stdlib.h>
#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/INPUT/TIMER.H"
#include "SRC/COMBAT/AI/CBTAITRN.H"
#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"
#include "SRC/COMBAT/SPELL/CSPELL.H"
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
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/GAME/MAINDATA.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/R3D/FX/WORLDFX.H"
#include "SRC/AUDIO/ENGINE/AUDDRVST.H"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"
#include "SRC/COMBAT/ENC/CBENC.H"
#include "SRC/COMBAT/AI/CMBTAI.H"
#include "SRC/COMBAT/AI/CBTAI.H"
#include "SRC/COMBAT/STATS/MONSTAT.H"
#include "SRC/COMBAT/SPELL/HEXANIM.H"
#include "SRC/COMBAT/STATS/CBSTAT.H"
#include "defines.h"

unsigned short g_nSpellSymbolAnimFrame = 0x0000;
unsigned char __dat_165e[12] = {0x0f, 0x00, 0x8e, 0x00, 0x48, 0x00,
                                0x8e, 0x00, 0x82, 0x00, 0x8e, 0x00};

unsigned char g_bssgap_5154[6];
short g_nSpellCount;
unsigned char g_bssgap_5150[2];
SpellDef *g_pSpellDefs;
char *g_szSpellNameBlob;
SpellDocRow *g_pSpellDocRows;
unsigned char far *g_pSpellDocBlob;
StatusEffectSlot *g_pStatusEffectPool;
unsigned char far *g_pSpellScreenBuffer;
ImageRecord **g_pCastfaceSpriteTable;
unsigned short *g_pSpellCastableScratch;
short g_nSnowParticleSeedX;
short g_nSpellFontSlot;
short g_nCombatTileEffectPending;
short g_nCombatTileX;
short g_nCombatTileY;
short g_nSpellSymbolCount;
SpellSymbolRecord *g_pSpellSymbolRecords;
short *g_pSpellSymbolX;
short *g_pSpellSymbolY;

void cspell_subsystem_load(void) {
    IoFile *f;
    int i;
    unsigned int blobLen;
    int docCount;

    if (g_wInCombatMode == 0) {
        audio_sfx_stop_scene_sounds();
    }
    g_pCastfaceSpriteTable = resblit_load_asset_table("castface.bmp", 2);
    f = bak_fopen("spells.dat", "rb");
    bak_fread(&g_nSpellCount, 2, 1, f);
    g_pSpellDefs = galloc_safe_zcalloc(g_nSpellCount * sizeof(SpellDef));
    g_pSpellCastableScratch = galloc_safe_zcalloc(g_nSpellCount << 1);
    bak_fread(g_pSpellDefs, sizeof(SpellDef), g_nSpellCount, f);
    bak_fread(&blobLen, 2, 1, f);
    g_szSpellNameBlob = galloc_safe_zcalloc(blobLen);
    bak_fread(g_szSpellNameBlob, 1, blobLen, f);
    bak_fclose(f);
    i = 0;
    if (i < g_nSpellCount) {
        do {
            g_pSpellDefs[i].pName += (int)g_szSpellNameBlob;
            i = i + 1;
        } while (i < g_nSpellCount);
    }
    audio_sfx_register(g_pSfxArchiveStream, 0x1b);
    f = bak_fopen("spelldoc.dat", "rb");
    bak_fread(&docCount, 2, 1, f);
    g_pSpellDocRows = galloc_safe_zcalloc(docCount << 2);
    bak_fread(g_pSpellDocRows, 4, docCount, f);
    bak_fread(&blobLen, 2, 1, f);
    g_pSpellDocBlob = alloc_far((long)(int)blobLen, 0);
    bak_fread_chunked(g_pSpellDocBlob, 1, (long)(int)blobLen, f);
    bak_fclose(f);
    i = 0;
    if (i < docCount) {
        do {
            ((long *)g_pSpellDocRows)[i] += (long)g_pSpellDocBlob;
            i = i + 1;
        } while (i < docCount);
    }
    return;
}

void far cspell_status_effect_pool_init(void) {
    int i;

    g_pStatusEffectPool = galloc_safe_zcalloc(0xdc);
    for (i = 0; i < 0x14; i++) {
        g_pStatusEffectPool[i].nType = -1;
        g_pStatusEffectPool[i].nNext = -1;
    }
}

void cspell_status_effect_pool_free(void) {
    galloc_zfree(g_pStatusEffectPool);
}

void cspell_subsystem_unload(void) {
    _freemem(g_pSpellDocBlob);
    galloc_zfree(g_pSpellDocRows);
    audio_sfx_stop(0x1b);
    galloc_zfree(g_szSpellNameBlob);
    galloc_zfree(g_pSpellCastableScratch);
    galloc_zfree(g_pSpellDefs);
    g_pSpellDefs = (SpellDef *)0x0;
    emsimg_free_paged(g_pCastfaceSpriteTable);
    if (g_wInCombatMode == 0) {
        audio_sfx_register_world_bank();
    }
    return;
}

int cspell_status_effect_alloc_slot(void) {
    int i;

    for (i = 0; i < 0x14; i++) {
        if (g_pStatusEffectPool[i].nType == -1) {
            return i;
        }
    }
    return -1;
}

int cspell_status_effect_add(CombatActor *actor, int type, int source, int duration, unsigned char flag) {
    short slot;

    slot = actor->inner->status_head;
    if (slot == -1) {
        slot = cspell_status_effect_alloc_slot();
        actor->inner->status_head = slot;
    } else {
        while (g_pStatusEffectPool[slot].nNext != -1) {
            slot = g_pStatusEffectPool[slot].nNext;
        }
        g_pStatusEffectPool[slot].nNext = cspell_status_effect_alloc_slot();
        slot = g_pStatusEffectPool[slot].nNext;
    }
    if (slot != -1) {
        g_pStatusEffectPool[slot].nType = type;
        g_pStatusEffectPool[slot].nSource = source;
        g_pStatusEffectPool[slot].nDuration_or_hp = duration;
        g_pStatusEffectPool[slot].bFlag = flag;
        g_pStatusEffectPool[slot].nAge_ticks = 0;
        g_pStatusEffectPool[slot].nNext = -1;
    }
    return slot;
}

void cspell_status_effect_remove(CombatActor *actor, int slot) {
    short cur;

    if ((slot >= 0) && (slot <= 0x14)) {
        if (actor->inner->status_head == slot) {
            actor->inner->status_head = -1;
        } else {
            cur = actor->inner->status_head;
            if (cur != -1) {
                while (g_pStatusEffectPool[cur].nNext != slot) {
                    cur = g_pStatusEffectPool[cur].nNext;
                }
                g_pStatusEffectPool[cur].nNext = g_pStatusEffectPool[slot].nNext;
            }
        }
        g_pStatusEffectPool[slot].nType = -1;
    }
    return;
}

void cspell_status_effect_clear_actor(CombatActor *actor) {
    int slot;

    for (slot = actor->inner->status_head; slot != -1; slot = g_pStatusEffectPool[slot].nNext) {
        g_pStatusEffectPool[slot].nType = -1;
    }
    actor->inner->status_head = -1;
    return;
}

int far cspell_stat_effect_find_type(CombatActor *actor, int type) {
    int slot;

    slot = actor->inner->status_head;
    if ((slot <= -2) || (slot >= 0x14)) {
        slot = -1;
    }
    while (slot != -1) {
        if (g_pStatusEffectPool[slot].nType == type)
            return slot;
        slot = g_pStatusEffectPool[slot].nNext;
    }
    return slot;
}

void far cspell_apply_damage_armor_wear(CombatActor *actor, int damage) {
    Actor far *inv;
    ItemSlot far *armor;

    inv = actor->actor_record;
    armor = (ItemSlot far *)0;

    if (g_gameState.nChapter == 8) {
        if (itemtbl_inv_count_by_kind(inv, 1) != 0) {
            int i;
            for (i = 0; inv->itemCount > i; i++) {
                if (ACTOR_ITEM(inv, i).item_id == 1 && (ACTOR_ITEM(inv, i).flags & 0x40) != 0) {
                    armor = &ACTOR_ITEM(inv, i);
                    break;
                }
            }
        }
    }

    combat_arena_apply_damage(actor, damage, 0, 0, 0, 1);

    if (armor != (ItemSlot far *)0) {
        if (armor->condition < damage) {
            armor->condition = 0;
        } else {
            armor->condition = armor->condition - damage;
        }
    }
    return;
}

int far cspell_actor_stat_get_comb_dflt(CombatActor *actor, int spell_id) {
    register SpellDef *pSpell;
    int power;
    short cost;

    pSpell = &g_pSpellDefs[spell_id];
    power = stat_actor_get(actor, 0x10, 0);
    cost = (pSpell->nCost_max < power) ? pSpell->nCost_max : (short)(power - 1);
    return cost;
}

int cspell_record_field8(int idx) {
    register SpellDef *p = &g_pSpellDefs[idx];
    return p->nSpell_kind;
}

int far cspell_ai_pick_castable_spell(CombatActor *caster, CombatActor *target, int school,
                                      int kind) {
    int spell_id;

    if (cspell_stat_effect_find_type(caster, 0x1f) != -1) {
        return -1;
    }

    for (spell_id = g_nSpellCount; spell_id > -1; spell_id--) {
        if (g_pSpellDefs[spell_id].nSchool != school)
            continue;
        if (g_pSpellDefs[spell_id].nSpell_kind != kind)
            continue;
        if (cspell_check_castable(spell_id, caster, school) == 0)
            continue;
        if (RND2(2) == 0)
            continue;
        if (spell_id == 0x1e)
            continue;
        if (spell_id == 0x1f)
            continue;
        if (cspell_stat_effect_find_type(target, spell_id) == -1)
            return spell_id;
    }
    return spell_id;
}

static int far cspell_actor_class_is_humanoid(CombatActor *actor) {
    int result;

    switch (actor->inner->class_id) {
    case 0x1c:
    case 0x27:
    case 0x29:
    case 0x2a:
    case 0x2b:
    case 0x2c:
    case 0x2e:
    case 0x31:
    case 0x36:
    case 0x38:
    case 0x39:
    case 0x3a:
        result = 0;
        break;
    default:
        result = 1;
    }
    return result;
}

void cspell_palette_fade_to(int target_color, int target_intensity) {
    int intensity;

    for (intensity = 0x3f; intensity > target_intensity; intensity--) {
        palette_set_scaled(0x70, 0x8f, target_color, intensity);
    }
    return;
}

static void far cspell_play_palette_flash(CombatActor *actor, int color_level) {
    int intensity;

    combat_arena_actor_set_anim_pose(actor, '\x01');
    world_render_with_overlay(MK_FP(0, 0xffff));
    screen_frame_present();
    palette_set_scaled(0x70, 0x8f, color_level, 0x32);
    palette_set_scaled(0x70, 0x8f, color_level, 0x1e);
    g_nFrameTickCountdown = 0x28;
    do {
    } while (g_nFrameTickCountdown != 0);
    for (intensity = 0x1f; intensity < 0x40; intensity = intensity + 2) {
        palette_set_scaled(0x70, 0x8f, color_level, intensity);
        screen_frame_present();
        world_render_with_overlay(MK_FP(0, 0xffff));
    }
    screen_frame_present();
    world_render_with_overlay(MK_FP(0, 0xffff));
    return;
}

static void cspell_actor_walk_steps(CombatActor *caster, CombatActor *target, int steps) {
    int x_delta;
    int y_delta;
    int slot;
    int direction;
    int heading;
    int flags;

    direction = combat_actor_lookup_param_rec(target);

    heading = combat_actor_heading_from_to(caster, target) / 0x1000;

    if (3 <= heading && heading <= 5) {
        y_delta = 1;
    } else if (((heading <= 1) && (heading != 0)) || (heading == 7)) {
        y_delta = -1;
    } else {
        y_delta = 0;
    }

    if (heading != 0 && heading <= 3) {
        x_delta = 1;
    } else if (5 <= heading && heading <= 7) {
        x_delta = -1;
    } else {
        x_delta = 0;
    }

    slot = cspell_status_effect_add(target, 0x10, 0, 0, '\0');
    while (steps != 0 && !((flags = (signed char)target->inner->flags) & CAF_DEAD)) {
        g_acting_actor_speed = 1;
        steps = steps + -1;
        target->inner->pad_6[0] = target->inner->grid_x + x_delta;
        target->inner->pad_6[1] = target->inner->grid_y + y_delta;
        combataipath_actor_walk_path(target, 0);
        if ((target->inner->pad_6[0] != target->inner->grid_x) ||
            (target->inner->pad_6[1] != target->inner->grid_y)) {
            steps = 0;
        }
        combat_actor_anim0_if_not_dead(target, direction);
    }
    cspell_status_effect_remove(target, slot);
    return;
}

void cspell_apply_hit_at(CombatActor *caster, CombatActor **target_ptr, int src_id, int *dst_ptr,
                         int magnitude, int spell_kind, int knockback) {
    unsigned short animKind;
    unsigned short knockbackVal;
    int burstSpread;

    g_nVfxParticleColor = src_id;
    switch (spell_kind) {
    case 4:
        animKind = 2;
        knockbackVal = '\x01';
        burstSpread = 0x23;
        break;
    case 9:
        animKind = 3;
        knockbackVal = '\x03';
        burstSpread = (magnitude >> 2) + 0x14;
        break;
    default:
        animKind = 0x32;
        knockbackVal = '\x03';
        burstSpread = (magnitude >> 2) + 10;
        break;
    }
    audio_play(1);
    *target_ptr = world_rndr_ranged_attack_anim(caster, *target_ptr, dst_ptr, animKind, 0xfa, -1);
    if (*dst_ptr != 0) {
        if (knockback != 0) {
            cspell_actor_walk_steps(caster, *target_ptr, 1);
        }
        audio_play(0x1d);
        (*target_ptr)->inner->flags |= CAF_KNOCKBACK;
        (*target_ptr)->inner->knockback_value = knockbackVal;
        (*target_ptr)->inner->knockback_timer = '\n';
        worldfx_combat_damage_ptcl_burst(*target_ptr, burstSpread);
    }
    return;
}

static void cspell_play_rebound_animation(CombatActor *attacker, CombatActor *target) {
    int hit;

    hit = 1;
    target = world_rndr_ranged_attack_anim(attacker, target, &hit, 0x26, 100, -1);
    if (g_nCombatTileEffectPending == 0) {
        target->inner->flags |= CAF_KNOCKBACK;
        target->inner->knockback_value = '\x03';
        target->inner->knockback_timer = 'd';
        world_rndr_ranged_attack_anim(target, attacker, &hit, 0x26, 100, -1);
        target->inner->flags &= ~CAF_KNOCKBACK;
    }
    return;
}

static void far cspell_play_burst_animation(CombatActor *caster, CombatActor *target) {
    int hit;
    int speed;
    int i;

    hit = 1;
    audio_play(1);
    speed = RNDR(0xc8, 0x18f);
    world_rndr_ranged_attack_anim(caster, target, &hit, 5, speed, -1);
    speed = RNDR(0xdc, 0x1a3);
    world_rndr_ranged_attack_anim(caster, target, &hit, 3, speed, -1);
    speed = RNDR(0xfa, 0x1c1);
    target = world_rndr_ranged_attack_anim(caster, target, &hit, 3, speed, -1);
    i = 0;
    do {
        target->inner->flags |= CAF_KNOCKBACK;
        target->inner->knockback_value = 3;
        target->inner->knockback_timer = 0x64;
        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
        target->inner->flags |= CAF_KNOCKBACK;
        target->inner->knockback_value = 1;
        target->inner->knockback_timer = 0x64;
        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
        i++;
    } while (i < 2);
    target->inner->flags &= ~CAF_KNOCKBACK;
}

static CombatActor *cspell_find_alive_actor_not_list(CombatActor **exclude_list,
                                                     int exclude_count) {
    int i;
    int j;
    CombatActor *cand;
    int flags;

    for (i = 0; i < g_nCombatOtherCount; i++) {
        cand = &g_pCombatOtherActors[i];
        if ((flags = (signed char)g_pCombatOtherActors[i].inner->flags) & CAF_DEAD)
            continue;
        for (j = 0; j <= exclude_count; j++) {
            if (exclude_list[j] == cand) {
                cand = (CombatActor *)0;
                break;
            }
        }
        if (cand != (CombatActor *)0)
            return cand;
    }
    return 0;
}

static void cspell_chain_damage_targets(CombatActor *caster, CombatActor *target, int magnitude) {
    CombatActor *chainTgt;
    int slot;
    int hit;
    int did_swap;
    int i;

    hit = 1;
    if (combatenc_is_encounter_actor(target) == 0) {
        combat_arena_swap_tgt_state();
        did_swap = 1;
    } else {
        did_swap = 0;
    }
    hit = combatenc_skill_check_random(caster, target, stat_actor_get(caster, 7, 0), -1);
    slot = cspell_status_effect_add(target, 0x1c, 0, 0, '\0');
    cspell_apply_hit_at(caster, &target, 0xd0, &hit, magnitude, 0x1c, 1);
    cspell_status_effect_remove(target, slot);
    if (hit != 0) {
        if (!(*(signed char *)&target->inner->flags & CAF_DEAD)) {
            combat_arena_apply_damage(target, magnitude, 0, 1, 0x200, 0);
        }
    }
    if (caster->inner->class_id != -1) {
        i = 0;
        if (i < g_nCombatOtherCount) {
            do {
                if (!(*(signed char *)&(g_pCombatOtherActors[i].inner)->flags & CAF_DEAD)) {
                    if (combat_actor_trace_proj_path(caster, &g_pCombatOtherActors[i], 0) != 0 &&
                        (&g_pCombatOtherActors[i] != target)) {
                        audio_play(0x12);
                        combat_actor_play_ranged_windup(
                            caster, combat_actor_heading_from_to(caster, &g_pCombatOtherActors[i]));
                        slot = cspell_status_effect_add(&g_pCombatOtherActors[i], 0x1c, 0, 0, '\0');
                        chainTgt = &g_pCombatOtherActors[i];
                        hit = combatenc_skill_check_random(caster, target,
                                                           stat_actor_get(caster, 7, 0), -1);
                        cspell_apply_hit_at(caster, &chainTgt, 0xd0, &hit, magnitude, 0x1c, 1);
                        cspell_status_effect_remove(&g_pCombatOtherActors[i], slot);
                        if (hit != 0) {
                            if (!(*(signed char *)&chainTgt->inner->flags & CAF_DEAD)) {
                                combat_arena_apply_damage(chainTgt, magnitude, 0, 1, 0x200, 0);
                            }
                        }
                    }
                }
                i = i + 1;
            } while (i < g_nCombatOtherCount);
        }
    }
    if (did_swap != 0) {
        combat_arena_swap_tgt_state();
    }
    return;
}

static void far cspell_chain_damage(CombatActor *param_1, CombatActor *param_2, int param_3) {
    int decay;
    int did_swap;
    int damage;
    CombatActor *hitList[7];
    int i;

    decay = 100;
    damage = param_3 << 1;
    if (combatenc_is_encounter_actor(param_1) != 0) {
        combat_arena_swap_tgt_state();
        did_swap = 1;
    } else {
        did_swap = 0;
    }
    for (i = 0; i < 7; i++) {
        hitList[i] = 0;
    }
    i = 0;
    if (i < g_nCombatOtherCount) {
        while (1) {
            damage = (damage * decay) / 100;
            decay = 0x50;
            if (damage == 0)
                break;
            cspell_play_burst_animation(param_1, param_2);
            if (cbstat_char_bitmap_3w_test(param_2->inner->class_id, 0x2c) == 0) {
                combat_arena_apply_damage(param_2, damage, 0, 1, 0x200, 0);
            }
            hitList[i] = param_2;
            param_1 = param_2;
            param_2 = cspell_find_alive_actor_not_list(hitList, i);
            if (param_2 == (CombatActor *)0)
                break;
            i++;
            if (i >= g_nCombatOtherCount)
                break;
        }
    }
    if (did_swap != 0) {
        combat_arena_swap_tgt_state();
    }
}

static void far cspell_storm_flash_sequence(CombatActor *actor) {
    int i;

    combat_arena_actor_set_anim_pose(actor, '\x03');
    audio_play(0x11);
    i = 0;
    do {
        world_render_with_overlay(MK_FP(0, 0xffff));
        audio_play(0x15);
        g_nFrameTickCountdown = RND(0x28);
        screen_frame_present();
        while (g_nFrameTickCountdown != 0) {
        }
        i = i + 1;
    } while (i < 4);
    audio_driver_stop(0x11);
    cspell_play_palette_flash(actor, 3);
}

void far cspell_vfx_run_and_wait(void) {
    worldfx_state_arm_minus2();
    while (g_nVfxTickCountdown != 0) {
        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
    }
    return;
}

void far cspell_actor_charge_to_target(CombatActor *param_1, CombatActor *param_2, int param_3) {
    int dist;

    audio_play(0x51);
    dist = combatgrid_chebyshev_distance(param_1->inner->grid_x, param_1->inner->grid_y,
                                         param_2->inner->grid_x, param_2->inner->grid_y);
    g_acting_actor_speed = (dist < param_3) ? dist : param_3;
    param_2->inner->pad_6[0] = param_1->inner->grid_x;
    param_2->inner->pad_6[1] = param_1->inner->grid_y;
    combataipath_actor_walk_path(param_2, 0);
    if ((param_2->inner->flags & CAF_FLEE) != 0) {
        combatenc_actor_flee_tile_east(param_2);
    }
    return;
}

void far cspell_perform_ranged_hit(CombatActor *param_1, CombatActor *param_2, int param_3) {
    int hit;

    hit = 1;
#ifdef V102CD
    cspell_apply_damage_armor_wear(param_1, param_3);
#else
    combat_arena_apply_damage(param_1, param_3, 0, 0, 0, 1);
#endif
    param_1->inner->flags &= ~CAF_KNOCKBACK;
    audio_play(0x4f);
    param_2 = world_rndr_ranged_attack_anim(param_1, param_2, &hit, 4, 100, -1);
    if (cbstat_char_bitmap_3w_test(param_2->inner->class_id, 0x1b) == 0) {
        cspell_actor_walk_steps(param_1, param_2, param_3);
    }
    return;
}

void far cspell_select_target_tile(void) {
    int tile_chosen;
    int tile_in_range;
    unsigned short consumed;
#ifdef V102CD
    int valid;
#endif

    tile_chosen = 0;
    while (!tile_chosen) {
        menupage_run(g_combat_menu, &consumed);
        tile_in_range = (g_cursor_tile_x < 8 && -1 < g_cursor_tile_x && g_cursor_tile_y < 0xd &&
                         -1 < g_cursor_tile_y);
        if (tile_in_range) {
            if (combatgrid_tile_is_blocked((char)g_cursor_tile_x, (char)g_cursor_tile_y) != 0)
                goto show_invalid_overlay;
            world_render_with_overlay(MK_FP(0, 3));
        } else {
        show_invalid_overlay:
            world_render_with_overlay(MK_FP(0, 0xffff));
        }
#ifdef V102CD
        screen_frame_present();
        valid = (combatgrid_tile_is_blocked((char)g_cursor_tile_x, (char)g_cursor_tile_y) == 0 &&
                 combatgrid_tile_terrain_field((char)g_cursor_tile_x, (char)g_cursor_tile_y) != 3);
        if (combat_arena_wait_confirm_cancel() != 0) {
            if (valid && tile_in_range) {
                tile_chosen = 1;
            }
        }
#else
        screen_frame_present();
        if (combat_arena_wait_confirm_cancel() != 0) {
            if (combatgrid_tile_is_blocked((char)g_cursor_tile_x, (char)g_cursor_tile_y) == 0 &&
                tile_in_range) {
                tile_chosen = 1;
            }
        }
#endif
    }
}

void far cspell_summon_monster(int monster_type, int prompt_for_tile) {
    CombatActor *actor;
    CombatActorInner *in;

    actor = combat_actor_party_add(monster_type);
    if (actor == (CombatActor *)0x0) {
        dialog_play_record(0x91, 0);
    } else {
        in = actor->inner;
        if (prompt_for_tile != 0) {
            cspell_select_target_tile();
        }
        audio_play(0x3a);
        in->grid_x = (unsigned char)g_cursor_tile_x;
        in->grid_y = (unsigned char)g_cursor_tile_y;
        in->status_head = -1;
        in->flags = CAF_AI_SUMMON;
        in->class_id = monster_type;
        in->knockback_value = in->knockback_timer = in->pad_e[0] = in->dmg_frames_left = 0;
        in->pad_e[3] = 1;
        in->pad_e[2] = 1;
        actor->pSpellsKnown[0] = 0;
        actor->pSpellsKnown[1] = 0;
        actor->pSpellsKnown[2] = 0;
        monstat_roll_stats_from_file(actor);
        combatgrid_tile_set_word(in->grid_x, in->grid_y, (unsigned int)actor);
        combat_actor_anim0_if_not_dead(actor, 0);
    }
}

static void far cspell_summon_actor(CombatActor *param_1, int param_2) {
    CombatActor *actor;
    CombatActor tmpActor;
    CombatActorInner tmpInner;
    int hit;
    short slot;

    hit = 1;
    tmpActor.inner = &tmpInner;
    cspell_select_target_tile();
    slot = cspell_status_effect_alloc_slot();
    tmpInner.grid_x = (unsigned char)g_cursor_tile_x;
    tmpInner.grid_y = (unsigned char)g_cursor_tile_y;
    tmpInner.status_head = slot;
    g_pStatusEffectPool[slot].nType = 1;
    g_pStatusEffectPool[slot].nDuration_or_hp = param_2;
    tmpInner.flags = CAF_READY;
    tmpInner.class_id = param_1->inner->class_id;
    tmpInner.knockback_value = tmpInner.knockback_timer = tmpInner.pad_e[0] =
        tmpInner.dmg_frames_left = 0;
    do {
    } while (combat_arena_wait_confirm_cancel() != 0);
    actor = combat_actor_party_add(tmpInner.class_id);
    audio_play(0x3a);
    world_rndr_ranged_attack_anim(param_1, &tmpActor, &hit, tmpInner.class_id, 0x32, -1);
    *actor->inner = tmpInner;
    actor->stats[2].base = '\0';
    actor->stats[0].base = '\x01';
    actor->stats[1].base = '\x01';
    combat_actor_anim0_if_not_dead(actor, 0);
    combatgrid_tile_set_word(tmpInner.grid_x, tmpInner.grid_y, (unsigned int)actor);
}

void cspell_actor_walk_with_sound(CombatActor *actor, CombatActor *target) {
    combat_actor_play_anim_sprite3(target, combat_actor_heading_from_to(target, actor));
    audio_play(0x50);
    cspell_actor_walk_steps(target, actor, 0xf);
    combat_arena_actor_set_anim_pose(actor, 1);
    if (!(signed char)actor->inner->flags & CAF_DEAD) {
        combat_arena_actor_die(actor, 1);
    }
}

void far cspell_invoke_effect(CombatActor *actor, CombatActor **target_slot, int spell_id,
                              int *out_chain_flag, int extra) {
    int slot;
    CombatActor *tgt;
    Actor far *inv;
    SpellDef *pSpell;

    inv = actor->actor_record;
    pSpell = &g_pSpellDefs[spell_id];
    switch (pSpell->nEffect_kind) {
    case 0:
        slot = cspell_status_effect_add(*target_slot, spell_id, 0, 0, '\0');
        cspell_palette_fade_to(pSpell->nEffect_sprite_id, 0xf);
    LAB_1165:
        cspell_status_effect_remove(*target_slot, slot);
        return;
    case 2:
        slot = cspell_status_effect_add(*target_slot, spell_id, 0, 0, '\0');
        cspell_play_palette_flash(*target_slot, pSpell->nEffect_sprite_id);
        goto LAB_1165;
    case 3:
        tgt = *target_slot;
        slot = cspell_status_effect_add(tgt, spell_id, 0, 0, '\0');
        cspell_apply_hit_at(actor, target_slot, pSpell->nEffect_sprite_id, out_chain_flag, extra,
                            spell_id, 0);
        cspell_status_effect_remove(tgt, slot);
        return;
    case 19:
        cspell_chain_damage_targets(actor, *target_slot, extra);
        *out_chain_flag = 1;
        return;
    case 4:
        slot = cspell_status_effect_add(*target_slot, spell_id, 0, 0, '\0');
        cspell_storm_flash_sequence(*target_slot);
        goto LAB_1168;
    case 11:
        cspell_actor_walk_with_sound(*target_slot, actor);
        return;
    case 12:
        slot = cspell_status_effect_add(*target_slot, spell_id, 0, 0, '\0');
        worldfx_render_world_100_frames();
        goto LAB_1168;
    case 13:
        slot = cspell_status_effect_add(*target_slot, spell_id, 0, 0, '\0');
        audio_play(6);
        worldfx_render_particle_blast(*target_slot, pSpell->nEffect_sprite_id);
        audio_play(0x15);
        cspell_play_palette_flash(*target_slot, pSpell->nEffect_sprite_id);
        audio_driver_stop(0x15);
        audio_play(0x15);
        worldfx_render_particle_blast(*target_slot, pSpell->nEffect_sprite_id);
        goto LAB_1165;
    case 9:
        slot = cspell_status_effect_add(*target_slot, spell_id, 0, 0, '\0');
        worldfx_flux_vortex_play(pSpell->nEffect_sprite_id);
    LAB_1168:
        cspell_status_effect_remove(*target_slot, slot);
        return;
    case 16:
        slot = cspell_status_effect_add(*target_slot, spell_id, 0, 0, '\0');
        cspell_vfx_run_and_wait();
        goto LAB_1168;
    case 17:
        slot = cspell_status_effect_add(*target_slot, spell_id, 0, 0, '\0');
        cspell_summon_actor(*target_slot, extra);
        goto LAB_1165;
    case 18:
        if ((*target_slot)->inner->class_id == 0x29 || (*target_slot)->inner->class_id == 0x2a ||
            (*target_slot)->inner->class_id == 0x2b) {
            audio_play(0x51);
            cspell_status_effect_add(*target_slot, 0xc, 0, 0, '\0');
            (*target_slot)->inner->pad_e[0] = '\x01';
            combatenc_actor_flee_tile_east(*target_slot);
            itemtbl_inv_consume_one_by_kind(inv, pSpell->nInv_component_id);
        }
        return;
    default:
        return;
    }
}

static void far cspell_chance_pushback_actor(int chance_pct) {
    int threshold;
    int roll;

    threshold = chance_pct;
    audio_play(1);
    roll = RND(100);
    threshold = threshold * 700 / 100 + 10;
    if (roll < threshold)
        combatgrid_push_back_actor(g_cursor_tile_x, g_cursor_tile_y);
}

static void far cspell_aoe_storm_damage_all(CombatActor *caster, CombatActor *target) {
    int stableFlag;
    int frames;
    int didSwap;
    int damage;
    int baseDmg;
    int si, di;

    stableFlag = 0;
    didSwap = 0;
    baseDmg = 0xf;

    if (g_bStormAmplify != 0) {
        baseDmg += baseDmg >> 1;
    }
    g_bStormAmplify = 0;

    if (combatenc_is_encounter_actor(target) == 0) {
        combat_arena_swap_tgt_state();
        didSwap = 1;
    }

    audio_play(0x4e);

    frames = RNDR(0x14, 0x22);

    si = 0;
    if (si < frames) {
        do {
            world_render_with_overlay(MK_FP(0, 0xffff));
            screen_frame_present();
            di = 0;
            if (di < g_nCombatOtherCount) {
                do {
                    if (RND(0x64) < 0x19) {
                        if (!((signed char)g_pCombatOtherActors[si].inner->flags & CAF_DEAD) &&
                            !cbstat_char_bitmap_3w_test(g_pCombatOtherActors[si].inner->class_id,
                                                        0x15)) {
                            combatgrid_set_tile_effect(g_pCombatOtherActors[di].inner->grid_x,
                                                       g_pCombatOtherActors[di].inner->grid_y, 1,
                                                       1);
                        }
                    }
                    di++;
                } while (di < g_nCombatOtherCount);
            }
            si++;
        } while (si < frames);
    }

    si = 0;
    if (si < g_nCombatOtherCount) {
        do {
            if (!((signed char)g_pCombatOtherActors[si].inner->flags & CAF_DEAD) &&
                !cbstat_char_bitmap_3w_test(g_pCombatOtherActors[si].inner->class_id, 0x15)) {
                combatgrid_set_tile_effect(g_pCombatOtherActors[si].inner->grid_x,
                                           g_pCombatOtherActors[si].inner->grid_y, 1, 1);
            }
            si++;
        } while (si < g_nCombatOtherCount);
    }

    while (stableFlag == 0 && combat_actor_stat_percent(caster, 1) != 0) {
        world_render_with_overlay(MK_FP(0, 0xffff));
        stableFlag = 1;

        si = 0;
        if (si < g_nCombatOtherCount) {
            do {
                if (!((signed char)g_pCombatOtherActors[si].inner->flags & CAF_DEAD)) {
                    if (!cbstat_char_bitmap_3w_test(g_pCombatOtherActors[si].inner->class_id,
                                                    0x15)) {
                        stableFlag = 0;
                        if (RND(g_nCombatOtherCount) < (g_nCombatOtherCount >> 1) + 1) {

                            di = cspell_status_effect_add(&g_pCombatOtherActors[si], 5, 0, 0, '\0');
                            cspell_storm_flash_sequence(&g_pCombatOtherActors[si]);
                            cspell_status_effect_remove(&g_pCombatOtherActors[si], di);

                            damage = baseDmg + RND(5);

                            if (RND(3) == 0) {
                                di = cspell_status_effect_add(&g_pCombatOtherActors[si], 9, 0, 0,
                                                              '\0');
                                g_nVfxParticleColor = 0xaf;
                                g_pCombatOtherActors[si].inner->flags |= CAF_KNOCKBACK;
                                g_pCombatOtherActors[si].inner->knockback_value = '\x03';
                                g_pCombatOtherActors[si].inner->knockback_timer = '\x28';
                                audio_play(0x1d);
                                worldfx_combat_damage_ptcl_burst(&g_pCombatOtherActors[si], 0x19);
                                cspell_status_effect_remove(&g_pCombatOtherActors[si], di);
                                damage += 5;
                            }

                            if (!cbstat_char_bitmap_3w_test(
                                    g_pCombatOtherActors[si].inner->class_id, 0x15)) {
                                combatgrid_set_tile_effect(g_pCombatOtherActors[si].inner->grid_x,
                                                           g_pCombatOtherActors[si].inner->grid_y,
                                                           0, 1);
                                combat_arena_apply_damage(&g_pCombatOtherActors[si], damage, 0, 0,
                                                          0x200, 0);
                                g_pCombatOtherActors[si].inner->flags &= ~CAF_KNOCKBACK;
                                combatgrid_set_tile_effect(g_pCombatOtherActors[si].inner->grid_x,
                                                           g_pCombatOtherActors[si].inner->grid_y,
                                                           1, 1);
                            }

#ifdef V102CD
                            cspell_apply_damage_armor_wear(caster, 3);
#else
                            combat_arena_apply_damage(caster, 3, 0, 0, 0, 1);
#endif
                            caster->inner->flags &= ~CAF_KNOCKBACK;
                        }
                    }
                }
                si++;
            } while (si < g_nCombatOtherCount);
        }

        g_nFrameTickCountdown = 0x14;
        while (g_nFrameTickCountdown != 0) {
        }
        screen_frame_present();
    }

    audio_driver_stop(0x4e);

    si = 0;
    if (si < g_nCombatOtherCount) {
        do {
            combatgrid_set_tile_effect(g_pCombatOtherActors[si].inner->grid_x,
                                       g_pCombatOtherActors[si].inner->grid_y, 0, 1);
            si++;
        } while (si < g_nCombatOtherCount);
    }

    if (didSwap != 0) {
        combat_arena_swap_tgt_state();
    }
}

void far cspell_tile_trap_trigger(CombatActor *actor) {
    unsigned int damage;
    int slot;

    audio_play(0x1d);
    damage = combatgrid_tile_field4(actor->inner->grid_x, actor->inner->grid_y);
    combatgrid_set_tile_effect(actor->inner->grid_x, actor->inner->grid_y, 0, -1);
    g_nVfxParticleColor = 0;
    slot = cspell_status_effect_add(actor, 9, 0, 0, '\0');
    actor->inner->flags |= CAF_KNOCKBACK;
    actor->inner->knockback_value = '\x01';
    actor->inner->knockback_timer = 'd';
    worldfx_combat_damage_ptcl_burst(actor, damage + 5);
    cspell_status_effect_remove(actor, slot);
    combat_arena_apply_damage(actor, damage, 0, 1, 0x200, 0);
    return;
}

void far cspell_flash_actor_status_effect(CombatActor *actor, int effect_type) {
    int slot;
    int i;

    slot = cspell_status_effect_add(actor, effect_type, 0, 0, '\0');
    i = 0;
    do {
        world_render_with_overlay(MK_FP(0, 0xffff));
        screen_frame_present();
        i = i + 1;
    } while (i < 10);
    cspell_status_effect_remove(actor, slot);
}

void cspell_try_add_status_effect(CombatActor *actor, int stat_idx, int value) {
    int slotIdx;
    int applyOut;
    int i;
    int isNew;
    ActorStatModifier newMod;
    unsigned short *mod;

    slotIdx = actor->cParty_slot - 1;

    newMod.wMaskFlags = 0x100;
    newMod.payload.wStatMask = 1 << stat_idx;
    newMod.payload.nValue = value;
    newMod.payload.dwTApply = g_gameState.game_time;
    newMod.payload.dwTExpiry = g_gameState.game_time << 1;
    i = 0;
    isNew = 1;
    mod = (unsigned short *)&g_gameState.aActorStatModifiers[slotIdx];
    for (; i < 8;) {
        stat_apply_modifier(mod, &applyOut);
        if (*mod != 0 && mod[1] == newMod.payload.wStatMask && *mod != 0x100) {
            isNew = 0;
        }
        i++;
        mod = mod + 7;
    }
    if (isNew != 0) {
        stat_modifier_table_insert(actor, &newMod);
    }
}

static void cspell_steal_item_from_target(CombatActor *attacker, CombatActor *target) {
    int i;
    ItemSlot far *stolen;
    int hit;
    unsigned int prevCount;
    int scratch;

    stolen = (ItemSlot far *)0;
    hit = 1;
    audio_play(0x51);
    cspell_flash_actor_status_effect(target, 0xc);
    for (i = 0; attacker->actor_record->itemCount > i; i++) {
        if (ACTOR_ITEM(attacker->actor_record, i).item_id == 0x0a) {
            stolen = &ACTOR_ITEM(attacker->actor_record, i);
            break;
        }
    }
    cmbinv_actor_inv_remove_item(attacker->actor_record, stolen);
    prevCount = (unsigned int)target->actor_record->itemCount;
    combat_arena_suspend_char_screen(target, &scratch, &scratch);
    if (target->actor_record->itemCount != prevCount) {
        world_rndr_ranged_attack_anim(target, attacker, &hit, 5, 0x78, -1);
    }
    return;
}

#define SLOT(rec, i) (&ACTOR_ITEM((rec), (i)))

static void cspell_actor_mark_consum_used(CombatActor *actor) {
    Actor far *rec;
    ItemRecord far *item;
    int i;

    rec = actor->actor_record;
    audio_play(0x3a);
    for (i = 0; i < (int)(unsigned)rec->itemCount; i++) {
        if (SLOT(rec, i)->flags & 0x40) {
            item = itemtbl_record_ptr(SLOT(rec, i));
            if (item->wCategory == 1) {
                SLOT(rec, i)->flags |= 0x200;
                return;
            }
        }
    }
}

void far cspell_apply_step_tile_spell(CombatActor *mover, int spell_id, int intensity,
                                      int caster_class) {
    CombatActor castStub;
    CombatActorInner castInner;

    g_bStormAmplify = 0;
    if (spell_id != 0x2a) {
        audio_play(10);
        castStub.name = (char *)0x0;
        castStub.inner = &castInner;
        castStub.stats[0].max = '\x01';
        castStub.actor_record = (Actor far *)0x0L;
        castInner.class_id = caster_class;
        castInner.flags = CAF_DEAD;
        castInner.grid_x = (unsigned char)g_nCombatTileX;
        castInner.grid_y = (unsigned char)g_nCombatTileY;
        cspell_resolve_cast(&castStub, mover, spell_id, -intensity);
    }
    return;
}

int cspell_compute_effect_magnitude(CombatActor *actor, int level, int spell_id) {
    SpellDef *pSpell;
    int result;

    result = 0;
    pSpell = &g_pSpellDefs[spell_id];
    switch ((unsigned)(pSpell->nEffect_subkind - 1)) {
    case 0:
        if (spell_id != 5 ||
            (actor != (CombatActor *)0 && combatenc_actor_has_spell_1or4(actor) != 0)) {
            result = pSpell->nEffect_magnitude;
        }
        break;
    case 1:
        if (pSpell->nEffect_magnitude > 0) {
            goto L_multiply;
        }
        goto L_divide;
    L_divide:
        result = level /
                 (pSpell->nEffect_magnitude < 0
                      ? (pSpell->nEffect_magnitude == -0x8000 ? 0x7fff : -pSpell->nEffect_magnitude)
                      : pSpell->nEffect_magnitude);
        break;
    case 2:
        if (actor != (CombatActor *)0) {
            if (cbstat_char_bitmap_3w_test(actor->inner->class_id, spell_id) == 0) {
                result = 0;
            }
        }
        break;
    case 3:
    L_multiply:
        result = level * pSpell->nEffect_magnitude;
        break;
    case 4:
        break;
    }

    if (spell_id == 0x15) {
        result = 1000;
    }
    return result;
}

#ifdef V102CD
void far combat_ai_resolve_hit(CombatActor *attacker, CombatActor *target, int damage, int dir) {
    int hpBefore;
    int staminaBefore;
    int b;

    if ((attacker == (CombatActor *)0x0) || (cspell_stat_effect_find_type(attacker, 0x1f) == -1)) {
        hpBefore = target->stats[0].base;
        staminaBefore = target->stats[1].base;
        combat_arena_actor_set_anim_pose(target, '\x04');
        cspell_apply_damage_armor_wear(attacker, damage);
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

void cspell_apply_damage_with_recoil(CombatActor *attacker, CombatActor *target, int spell_id,
                                     int damage) {
    if (cbstat_char_bitmap_3w_test(target->inner->class_id, spell_id) == 0) {
        audio_play(0x3f);
        if ((target->inner->class_id == 0x36) && ((int)(unsigned int)target->stats[3].base <= damage)) {
            combat_arena_actor_die(target, 1);
        } else {
            if ((int)stat_actor_get(target, 3, 0) < damage) {
                damage = stat_actor_get(target, 3, 0);
            }
            if (target->cParty_slot != '\0') {
                cspell_try_add_status_effect(target, 3, -damage);
            } else {
                stat_combatant_modify(target, 3, (long)(damage * -0x100), 0);
                stat_actor_get(target, 3, 0);
            }
            if (attacker->cParty_slot != '\0') {
                cspell_try_add_status_effect(attacker, 3, damage >> 1);
            } else {
                stat_combatant_modify(attacker, 3, (long)((damage >> 1) << 7), 0);
                stat_actor_get(attacker, 3, 0);
            }
            combat_arena_actor_set_anim_pose(target, '\x01');
        }
    }
}

void cspell_resolve_cast(CombatActor *caster, CombatActor *target, int spell_id, int intensity) {
    SpellDef *pSpell;
    int magnitude;
    int hit;
    int skillBonus;
    int isNeg;
    int damage;
    int fromTileStep;
    int duration;
    int flags;

    if (caster->inner->class_id == -2) {
        caster->inner->class_id = -1;
        fromTileStep = 1;
    } else {
        fromTileStep = 0;
    }
    g_nCombatTileEffectPending = 0;
    damage = intensity;
    if (g_bStormAmplify != 0) {
        intensity += intensity >> 1;
    }
    if (intensity < 0) {
        isNeg = 1;
        intensity = -intensity;
    } else {
        isNeg = 0;
    }
    pSpell = &g_pSpellDefs[spell_id];
    if (pSpell->nSpell_kind == 8) {
        target = 0;
    }
    if (target != 0 && cbstat_char_bitmap_3w_test_170c(target->inner->class_id, spell_id) != 0) {
        intensity = intensity << 1;
    }
    if (target != 0 && target->inner->class_id == -1) {
        hit = combatgrid_tile_blockd_kind10(target);
    } else if (isNeg == 0 && pSpell->nSpell_kind == 0 && target != 0) {
        skillBonus = 0;
        hit = combatenc_skill_check_random(caster, target,
                                           stat_actor_get(caster, 7, 0) + skillBonus, -1);
    } else {
        hit = 1;
    }

    if (isNeg == 0) {

        switch (pSpell->nSpell_kind) {
        case 0:
        case 2:
        case 3:
        case 7:
        case 8:
            stat_combatant_modify(caster, 7, 1, 3);
            if (hit != 0) {
                stat_combatant_modify(caster, 7, 1, 3);
            }
            audio_play(0x12);
            combat_actor_play_ranged_windup(caster, combat_actor_heading_from_to(caster, target));
            break;
        case 1:
        case 4:
        default:
            audio_play(0x13);
            combat_actor_play_melee_swing(caster, combat_actor_heading_from_to(caster, target));
            break;
        case 5:
            combatgrid_place_tile_fx_at_cur(pSpell->nEffect_sprite_id,
                                            pSpell->nEffect_param * intensity);
            break;
        case 6:
            cspell_summon_monster(pSpell->nEffect_sprite_id, 0);
            break;
        }
    }

    magnitude = cspell_compute_effect_magnitude(target, intensity, spell_id);

    switch ((unsigned int)(pSpell->nEffect_subkind - 1)) {
    case 0:
        if (spell_id == 5 && combatenc_actor_has_spell_1or4(target) == 0) {
            pSpell = 0;
        }
        break;
    case 1:
        break;
    case 2:
        if (cbstat_char_bitmap_3w_test(target->inner->class_id, spell_id) == 0) {
            if (pSpell->nEffect_param > 0) {
                duration = intensity * pSpell->nEffect_param;
            } else {
                duration =
                    intensity /
                    (pSpell->nEffect_param < 0
                         ? (pSpell->nEffect_param == -0x8000 ? 0x7fff : -pSpell->nEffect_param)
                         : pSpell->nEffect_param);
            }
            if (((flags = (signed char)target->inner->flags) & CAF_READY) == 0) {
                duration++;
            }
            cspell_status_effect_add(target, spell_id, intensity, duration,
                                     (unsigned char)pSpell->nEffect_sprite_id);
        }
        break;
    case 3:
        combatgrid_set_tile_effect(target->inner->grid_x, target->inner->grid_y,
                                   pSpell->nEffect_magnitude, pSpell->nEffect_param * intensity);
        break;
    case 4:
        break;
    }

    if (target == 0 || cbstat_char_bitmap_3w_test(target->inner->class_id, spell_id) == 0) {

        switch (spell_id) {
        case 42:
            cspell_play_rebound_animation(caster, target);
            magnitude =
                intensity /
                (pSpell->nEffect_magnitude < 0
                     ? (pSpell->nEffect_magnitude == -0x8000 ? 0x7fff : -pSpell->nEffect_magnitude)
                     : pSpell->nEffect_magnitude);
            if (g_nCombatTileEffectPending == 0) {
                cspell_apply_damage_with_recoil(caster, target, spell_id, magnitude);
            }
            magnitude = 0;
            break;
        case 14:
            hit = 0;
            break;
        case 3:
            audio_play(0x3a);
            if (target->cParty_slot != 0) {
                cspell_try_add_status_effect(target, 5, -0x14);
                cspell_try_add_status_effect(target, 6, -0x14);
                cspell_try_add_status_effect(target, 7, -0x14);
            } else {
                stat_combatant_modify(target, 5, -0x1400, 0);
                stat_combatant_modify(target, 6, -0x1400, 0);
                stat_combatant_modify(target, 7, -0x1400, 0);
            }
            break;
        case 20:
            audio_play(0x4d);
            break;
        case 6:
            audio_play(0x3a);
            break;
        case 9:
            if (combatenc_actor_id_eq_22(target) == 0) {
                magnitude = 0;
            }
            break;
        case 13:
            if (cspell_actor_class_is_humanoid(target) != 0) {
                audio_play(0x4d);
                combat_actor_anim_mark_dirty(target, -1);
            }
            break;
        case 15:
            if (combatgrid_chebyshev_distance(target->inner->grid_x, target->inner->grid_y,
                                              caster->inner->grid_x, caster->inner->grid_y) < 2) {
                pSpell = 0;
            } else {
                combat_actor_melee_approach(caster, target);
            }
            break;
        case 27:
            cspell_perform_ranged_hit(caster, target, intensity);
            pSpell = 0;
            break;
        case 30:
            cspell_actor_charge_to_target(caster, target, intensity);
            break;
        case 12:
            cspell_steal_item_from_target(caster, target);
            break;
        case 25:
            cspell_actor_mark_consum_used(target);
            break;
        case 44:
            cspell_chain_damage(caster, target, intensity);
            magnitude = 0;
            break;
        case 21:
            cspell_aoe_storm_damage_all(caster, target);
            pSpell = 0;
            break;
        case 37:
            cspell_chance_pushback_actor(intensity);
            hit = 0;
            break;
        case 23:
            audio_play(0x3a);
            break;
        default:
            break;
        }
    }

    if (pSpell != 0) {
        cspell_invoke_effect(caster, &target, spell_id, &hit, magnitude);
        if (hit != 0) {
            switch (spell_id) {
            case 0x1c:
                magnitude = 0;
                break;
            case 0x20:
#ifdef V102CD
                combat_actor_grid_remove(target);
                if ((CombatActor *)combatgrid_tile_terrain(target->inner->grid_x,
                                                           target->inner->grid_y) == target) {
                    combatgrid_tile_set_word(target->inner->grid_x, target->inner->grid_y, 0);
                }
                target->inner->grid_x = target->inner->grid_y = -1;
                combat_arena_actor_die(target, 0);
                break;
#else
                combat_actor_grid_remove(target);
                combatgrid_tile_set_word(target->inner->grid_x, target->inner->grid_y, 0);
                target->inner->grid_x = target->inner->grid_y = -1;
                combat_arena_actor_die(target, 0);
                break;
#endif
            case 0x24:
                audio_play(0x4d);
                cspell_status_effect_add(target, 0xd, 0, intensity * pSpell->nEffect_param,
                                         (unsigned char)pSpell->nEffect_sprite_id);
                break;
            case 4:
                if (fromTileStep == 0) {
                    combat_arena_splash_dmg_near(target, magnitude);
                }
                break;
            case 0x14:
                magnitude = g_nSnowParticleSeedX;
                break;
            case 1:
                magnitude = 0;
                break;
            }
        }
        if (target != 0 &&
            cbstat_char_bitmap_3w_test_170c(target->inner->class_id, spell_id) != 0) {
            intensity = intensity >> 1;
        }
        if (target != 0 && cbstat_char_bitmap_3w_test(target->inner->class_id, spell_id) != 0) {
            audio_play(0x3b);
        }
        if (pSpell != 0) {

            switch (pSpell->nSpell_kind) {
            case 2:
                audio_play(0x3f);
                combat_ai_resolve_hit(caster, target, intensity, magnitude);
                break;
            case 0:
            case 1:
            case 3:
            case 4:
            case 7:
                if (isNeg == 0) {
                    cspell_apply_damage_armor_wear(caster, damage);
                }
                caster->inner->flags &= ~CAF_KNOCKBACK;
                if (g_nCombatTileEffectPending != 0) {
                    cspell_apply_step_tile_spell(caster, spell_id, intensity, -1);
                } else {
                    if (hit != 0 && magnitude != 0 &&
                        cbstat_char_bitmap_3w_test(target->inner->class_id, spell_id) == 0) {
                        combat_arena_apply_damage(target, magnitude, 0, 1, 0x200, 0);
                    }
                }
                break;
            case 5:
            case 6:
            case 8:
                if (isNeg == 0) {
                    cspell_apply_damage_armor_wear(caster, damage);
                }
                caster->inner->flags &= ~CAF_KNOCKBACK;
                break;
            }
        }
    }
    g_bStormAmplify = 0;
}

int cspell_count_terrain7_tiles(void) {
    int count;
    int outer;
    int inner;

    count = 0;
    outer = 0;
    do {
        inner = 0;
        do {
            if (combatgrid_tile_terrain_field((char)outer, (char)inner) == 7) {
                count = count + 1;
            }
            inner++;
        } while (inner < 0xd);
        outer++;
    } while (outer < 8);
    return count;
}

#define SLOT(rec, i) (&ACTOR_ITEM((rec), (i)))

int cspell_check_castable(int spell_id, CombatActor *actor, int param_3) {
    int power;
    int thr;
    int i;
    int band;
    int bFound;
    int castable;
    int q;
    int mask;

    castable = 1;
    if (param_3 != -1) {
        power = stat_actor_get(actor, 0x10, 0);
        if (g_gameState.nChapter == 8) {
            bFound = 0;
            for (i = 0; i < (int)(unsigned)actor->actor_record->itemCount; i++) {
                if (SLOT(actor->actor_record, i)->item_id == 1 &&
                    (SLOT(actor->actor_record, i)->flags & 0x40)) {
                    thr = (unsigned char)SLOT(actor->actor_record, i)->condition;
                    if (power > thr) {
                        power = thr;
                    }
                    bFound = 1;
                    break;
                }
            }
            if (!bFound) {
                return 0;
            }
        }

        if (g_pSpellDefs[spell_id].nCost >= power) {
            castable = 0;
        }
        if (g_pSpellDefs[spell_id].nInv_component_id != -1 &&
            itemtbl_inv_count_by_kind(actor->actor_record,
                                      g_pSpellDefs[spell_id].nInv_component_id) == 0) {
            castable = 0;
        }

        if (g_game_mode == 2) {
            if (spell_id == 5 || spell_id == 0x1a || spell_id == 0x15) {
                return 0;
            }
        } else {
            if (spell_id == 2) {
                return 0;
            }
            if (spell_id == 0x1a) {
                band = (int)((g_gameState.game_time % 0xa8c0) / 0x708);
                if (band >= 8 && band < 0x11) {
                    return 0;
                }
            }
        }

        if ((g_pSpellDefs[spell_id].nSpell_kind == 6 || spell_id == 1) && g_combat_count_A == 7) {
            castable = 0;
        }
    }

    q = spell_id / 0x10;
    mask = 1 << (spell_id % 0x10);
    if ((actor->pSpellsKnown[q] & mask) == 0) {
        castable = 0;
    }
    return castable;
}

int far cspell_collect_castable(CombatActor *caster, int category) {
    int spell_id;
    int count;

    count = 0;
    spell_id = 0;
    while (spell_id < g_nSpellCount) {
        if ((g_pSpellDefs[spell_id].nSchool == category) || (category == -1)) {
            if (cspell_check_castable(spell_id, caster, category) != 0) {
                g_pSpellCastableScratch[count] = (unsigned short)g_pSpellDefs[spell_id].pName;
                count = count + 1;
            }
        }
        spell_id = spell_id + 1;
    }
    return count;
}

void cspell_draw_panel_text_list(MenuPage *panel, char **strings, int count, int first_visible,
                                 int row_count) {
    int x;
    int y;
    int sum;
    int h10;
    int height;
    int width;
    int i;

    width = (panel->rect.width > 0xb4) ? 0xa0 : panel->rect.width + (-0x19);
    height = panel->pEntries->rect.height;
    sum = width + panel->pEntries->rect.width;
    x = ((panel->rect.x + (panel->rect.width >> 1)) - (sum >> 1)) + (width == 0xa0 ? 0x14 : 0);
    y = panel->rect.y + 5;
    h10 = height / 10;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage =
        g_graphics_context.wVgaPage2Base;
    uiwidget_panel_draw_inset(x, y, width, height, 0xaa);
    if (count != 0) {
        uiwidget_panel_draw_inset(x + 1, y + row_count * 10 + 1, width - 2, 0xb, 0xa9);
    }
    g_graphics_context.clip.xmin = g_graphics_context.clip.ymin = 0;
    g_graphics_context.clip.xmax = x + width - 2;
    g_graphics_context.clip.ymax = 200;
    g_graphics_context.bClip_enabled = 1;
    for (i = 0; (i + first_visible < count) && (i < h10); i++) {
        uiwidget_draw_text_shadowed_dflt(strings[i + first_visible], 0xffff, -1, x + 3,
                                         y + i * 10 + 3);
    }
    g_graphics_context.bClip_enabled = 0;
}

static void far cspell_menu_toggle_word7_by_id(int id, MenuPage *menu) {
    int i;

    for (i = 0; i < (int)menu->wEntry_count; i++) {
        if (menu->pEntries[i].wAction_id == id) {
            menu->pEntries[i].wEnable_gate = ~menu->pEntries[i].wEnable_gate;
            return;
        }
    }
}

int cspell_paged_record_lookup_by_id(int slot) {
    int i;

    for (i = g_nSpellCount; i > -1; i--) {
        if ((char *)g_pSpellCastableScratch[slot] == g_pSpellDefs[i].pName) {
            break;
        }
    }
    return i;
}

void cspell_scroll_clamp_cursor(int *cursor, int *scroll, int visible_rows, int total_rows) {
    int cur;
    int scr;

    cur = *cursor;
    scr = *scroll;
    if (cur < 0) {
        scr = scr + -1;
        cur = 0;
    }
    if (cur > visible_rows) {
        scr = scr + 1;
        cur = visible_rows;
    }
    if (total_rows + -1 < cur) {
        cur = total_rows + -1;
    }
    if ((scr != 0) && (total_rows - (visible_rows + 1) < scr)) {
        scr = total_rows - (visible_rows + 1);
        cur = visible_rows;
    }
    if (scr < 0) {
        scr = 0;
        cur = 0;
    }
    *cursor = cur;
    *scroll = scr;
    return;
}

void far cspell_symbol_resources_load(int chapter) {
    IoFile *f;
    char *szFile = "symbolx.dat";
    int i;

    szFile[6] = chapter + '1';
    f = bak_fopen(szFile, "rb");
    bak_fread(&g_nSpellSymbolCount, 2, 1, f);
    g_pSpellSymbolRecords = galloc_safe_zcalloc(g_nSpellSymbolCount * sizeof(SpellSymbolRecord));
    bak_fread(g_pSpellSymbolRecords, sizeof(SpellSymbolRecord), g_nSpellSymbolCount, f);
    bak_fclose(f);
    i = 0;
    if (i < g_nSpellSymbolCount) {
        do {
            g_pSpellSymbolRecords[i].cHotkeyLetter =
                g_pSpellSymbolRecords[i].cHotkeyLetter + '\x01';
            i++;
        } while (i < g_nSpellSymbolCount);
    }
    g_pSpellSymbolX = galloc_safe_zcalloc(0x3c);
    g_pSpellSymbolY = galloc_safe_zcalloc(0x3c);
    f = bak_fopen("ring.dat", "rb");
    bak_fread(g_pSpellSymbolX, 2, 0x1e, f);
    bak_fread(g_pSpellSymbolY, 2, 0x1e, f);
    bak_fclose(f);
}

static void cspell_symbol_resources_free(void) {
    galloc_zfree(g_pSpellSymbolY);
    galloc_zfree(g_pSpellSymbolX);
    galloc_zfree(g_pSpellSymbolRecords);
    g_pSpellSymbolRecords = (SpellSymbolRecord *)0x0;
    return;
}

static void far cspell_draw_spr_path_5th_off(int sprite_idx, int start, int end, int mark_5th) {
    for (; start < end; start++) {
        if (mark_5th && (start + 1) % 5 == 0) {
            emsimg_map_then_call_180c((unsigned int *)g_pCastfaceSpriteTable[sprite_idx + 2],
                                      g_pSpellSymbolX[start] - 1, g_pSpellSymbolY[start] - 1, 0);
        } else {
            emsimg_map_then_call_180c((unsigned int *)g_pCastfaceSpriteTable[sprite_idx],
                                      g_pSpellSymbolX[start] - 1, g_pSpellSymbolY[start] - 1, 0);
        }
    }
}

static int far cspell_hotspot_hittest_at_cursor(CombatActor *actor) {
    short cx;
    short cy;
    int xbox;
    int ybox;
    int result;
    int i;
    int lo_x;
    int lo_y;

    xbox = 10;
    ybox = 10;
    result = -1;
    screen_cursor_get_position(&cx, &cy);
    i = 0;
    if (i < g_nSpellSymbolCount) {
        do {
            lo_x = g_pSpellSymbolRecords[i].nHotspotX - (xbox >> 1);
            lo_y = g_pSpellSymbolRecords[i].nHotspotY - (ybox >> 1);
            if (cx > lo_x && cx < lo_x + xbox && cy > lo_y && cy < lo_y + ybox &&
                cspell_check_castable(g_pSpellSymbolRecords[i].wSpellId, actor,
                                      g_pSpellDefs[g_pSpellSymbolRecords[i].wSpellId].nSchool) !=
                    0) {
                result = i;
                break;
            }
            i++;
        } while (i < g_nSpellSymbolCount);
    }
    return result;
}

static void far cspell_menu_animate_hilite(int base_color, int step, int selected,
                                           CombatActor *actor) {
    int textW;
    int j;
    int i;
    int iHeight;
    char *pBuf;

    iHeight = 10;
    pBuf = "x";
    if (g_nSpellSymbolCount != 0) {
        font_activate(g_nSpellFontSlot);
        g_graphics_context.bText_bg_color = '\0';
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        i = 0;
        while ((i < 7 && (step != 0))) {
            g_nFrameTickCountdown = 7;
            g_graphics_context.bText_fg_color = base_color + i * step;
            j = 0;
            if (j < g_nSpellSymbolCount) {
                do {
                    if (cspell_check_castable(
                            g_pSpellSymbolRecords[j].wSpellId, actor,
                            g_pSpellDefs[g_pSpellSymbolRecords[j].wSpellId].nSchool) != 0) {
                        *pBuf = g_pSpellSymbolRecords[j].cHotkeyLetter;
                        textW = font_text_width_ds(pBuf);
                        font_draw_text_ds(pBuf, g_pSpellSymbolRecords[j].nHotspotX - (textW >> 1),
                                          g_pSpellSymbolRecords[j].nHotspotY - (iHeight >> 1));
                    }
                    j = j + 1;
                } while (j < g_nSpellSymbolCount);
            }
            screen_frame_present();
            do {
            } while (g_nFrameTickCountdown != 0);
            i++;
        }
        j = 0;
        if (j < g_nSpellSymbolCount) {
            do {
                if (cspell_check_castable(
                        g_pSpellSymbolRecords[j].wSpellId, actor,
                        g_pSpellDefs[g_pSpellSymbolRecords[j].wSpellId].nSchool) != 0) {
                    if (j == selected) {
                        g_graphics_context.bText_fg_color =
                            (char)(((int)g_nSpellSymbolAnimFrame >> 2) % 8) + 0xd0;
                        g_nSpellSymbolAnimFrame++;
                    } else {
                        g_graphics_context.bText_fg_color = base_color + step * '\f';
                    }
                    *pBuf = g_pSpellSymbolRecords[j].cHotkeyLetter;
                    textW = font_text_width_ds(pBuf);
                    font_draw_text_ds(pBuf, g_pSpellSymbolRecords[j].nHotspotX - (textW >> 1),
                                      g_pSpellSymbolRecords[j].nHotspotY - (iHeight >> 1));
                }
                j = j + 1;
            } while (j < g_nSpellSymbolCount);
        }
        font_activate(g_wGameFontSlot);
    }
    return;
}

static void cspell_menu_present_panel(void) {
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    gfx_present_dispatch(0x86, 0x10, 0xa7, 0x59);
}

static void far cspell_list_draw_castable(CombatActor *caster) {
    int x;
    int textW;
    char *text;
    int i;
    int y;

    cspell_menu_present_panel();
    y = 0x1a;
    g_graphics_context.bText_fg_color = '\0';
    i = 0;
    while (i < g_nSpellSymbolCount) {
        if (cspell_check_castable(g_pSpellSymbolRecords[i].wSpellId, caster,
                                  g_pSpellDefs[g_pSpellSymbolRecords[i].wSpellId].nSchool) != 0) {
            text = g_pSpellDefs[g_pSpellSymbolRecords[i].wSpellId].pName;
            textW = font_text_width_ds(text);
            x = 0xd9 - (textW >> 1);
            font_draw_text_ds(text, x, y);
            y = y + 10;
        }
        i = i + 1;
    }
    return;
}

static void cspell_strcpy_far_src(char *dst, char far *src) {
    int i;

    for (i = 0; src[i] != '\0'; i++) {
        dst[i] = src[i];
    }
    dst[i] = '\0';
}

static void cspell_info_panel_show(int spell_index, int has_cost, CombatActor *actor) {
    char line_buf[60];
    int spell_row;
    int line;
    int damage;
    int x;
    int y;
    unsigned hp_cur;
    unsigned hp_max;

    line = 1;
    damage = cspell_compute_effect_magnitude((CombatActor *)0, has_cost, spell_index);
    cspell_menu_present_panel();
    g_graphics_context.bText_fg_color = 0;
    spell_row = spell_index * 7;

    cspell_strcpy_far_src(line_buf, ((char far **)g_pSpellDocRows)[spell_row]);
    x = 0x53 - (font_text_width_ds(line_buf) >> 1) + 0x86;
    y = 0x1a;
    font_draw_text_ds(line_buf, x, y);

    y += 0xd;
    x = 0x8d;
    while (line < 7) {
        if (line == 1 && has_cost != 0) {
            sprintf(line_buf, "Cost: %d Health+Stamina", has_cost);
            font_draw_text_ds(line_buf, x, y);
            y += 0xb;
        } else if (line == 2 && damage != 0 && damage != 1000) {
            sprintf(line_buf, "Damage: %d", damage);
            font_draw_text_ds(line_buf, x, y);
            y += 0xb;
        } else {
            cspell_strcpy_far_src(line_buf, ((char far **)g_pSpellDocRows)[spell_row + line]);
            if (line_buf[0] != '\0') {
                font_draw_text_ds(line_buf, x, y);
                y += 0xb;
            }
        }
        line++;
    }

    switch (spell_index) {
    case 0:
    case 2:
    case 8:
    case 11:
    case 17:
    case 18:
    case 26:
    case 34:
    case 35:
        y = 0x5e;
        x = 0x8d;
        hp_cur = stat_actor_get(actor, 0x10, 0);
        hp_max = stat_actor_get(actor, 0x10, 1);
        sprintf(line_buf, "Health/Stamina:  %d of %d", hp_cur, hp_max);
        font_draw_text_ds(line_buf, x, y);
        break;
    }
}

static int far cspell_hotspot_cursor_in_range(int min_index, int max_index) {
    int x_lo;
    short cursor_x;
    short cursor_y;
    int hit;
    register int box_w;
    register int box_h;
    int i;
    int y_lo;

    box_w = 10;
    box_h = 10;
    hit = -1;
    screen_cursor_get_position(&cursor_x, &cursor_y);
    for (i = 0; i < 30; i++) {
        x_lo = g_pSpellSymbolX[i] - (box_w >> 1);
        y_lo = g_pSpellSymbolY[i] - (box_h >> 1);
        if (cursor_x > x_lo && x_lo + box_w > cursor_x && cursor_y > y_lo &&
            y_lo + box_h > cursor_y && i >= min_index && i <= max_index) {
            hit = i;
            break;
        }
    }
    return hit;
}

static void far cspell_select_power(int *out_result, int spell_index, int hotspot,
                                    CombatActor *actor) {
    int maxPower;
    int baseCost;
    int done;
    int idx;
    unsigned int power;

    done = 0;
    maxPower = g_pSpellDefs[spell_index].nCost_max;
    baseCost = g_pSpellDefs[spell_index].nCost;
    power = stat_actor_get(actor, 0x10, 0);
    if (itemtbl_inv_count_by_kind(actor->actor_record, 1) != 0 && g_gameState.nChapter == 8) {
        for (idx = 0; idx < (int)(unsigned int)actor->actor_record->itemCount; idx = idx + 1) {
            if (ACTOR_ITEM(actor->actor_record, idx).item_id == 1) {
                unsigned int cond = (unsigned int)ACTOR_ITEM(actor->actor_record, idx).condition;
                if ((int)power > (int)cond) {
                    power = cond;
                }
                break;
            }
        }
    }
    if (maxPower >= (int)power) {
        maxPower = power - 1;
    }
    if (maxPower == baseCost) {
        *out_result = baseCost;
    } else {
        for (idx = 1; idx < 0x1e; idx = idx + 1) {
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            cspell_draw_spr_path_5th_off(2, 0x1e - idx, 0x1e, 1);
            cspell_draw_spr_path_5th_off(1, 0, 0x1e - idx, 0);
            screen_frame_present();
        }
        for (idx = 1; idx <= maxPower; idx = idx + 1) {
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            cspell_draw_spr_path_5th_off(2, 0, 0x1e, 1);
            cspell_draw_spr_path_5th_off(1, baseCost - 1, idx, 1);
            screen_frame_present();
        }
        while (!done) {
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            cspell_draw_spr_path_5th_off(2, 0, 0x1e, 1);
            cspell_draw_spr_path_5th_off(1, baseCost - 1, maxPower, 1);
            idx = cspell_hotspot_cursor_in_range(baseCost - 1, maxPower - 1);
            cspell_menu_animate_hilite(0x85, 0, hotspot, actor);
            if (idx != -1) {
                cspell_info_panel_show(spell_index, idx + 1, actor);
                cspell_draw_spr_path_5th_off(5, idx, idx + 1, 0);
                if (combat_arena_wait_confirm_cancel() != 0) {
                    done = 1;
                    *out_result = idx + 1;
                }
            } else {
                cspell_info_panel_show(spell_index, 0, actor);
            }
            screen_frame_present();
            if (key_is_down(1) != 0) {
                done = 1;
                *out_result = -1;
                do {
                    do {
                    } while (kbhit_read() >> 8 == 1);
                } while (key_is_down(1) != 0);
            }
        }
    }
    return;
}

void far cspell_gfx_wipe_horizontal_split(int x, int y, int w, int h) {
    int center;
    int left;
    int step;

    g_graphics_context.clip.xmax = x + w;
    g_graphics_context.clip.ymax = y + h;
    g_graphics_context.clip.xmin = x;
    g_graphics_context.clip.ymin = y;
    g_graphics_context.bClip_enabled = '\x01';
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaFrontPageBase;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;
    step = w / 0x4c;
    center = x + (w >> 1);
    left = center - step;
    while (left >= x) {
        g_nFrameTickCountdown = 1;
        gfx_present_dispatch(left, y, step, h);
        gfx_present_dispatch(center + (center - left) - step, y, step, h);
        do {
        } while (g_nFrameTickCountdown != 0);
        left -= step;
    }
    screen_frame_present();
    return;
}

static void far cspell_cast_menu_open_transition(void) {
    int nSize;

    screen_cursor_hide();
    vsync_hook(1);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
    gfx_present_dispatch(0, 0, 0x140, 200);
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
    gfx_present_dispatch(0xd, 0xb, 0x125, 0x65);
    cspell_gfx_wipe_horizontal_split(0xd, 0xb, 0x128, 0x66);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
    gfx_present_dispatch(0xd, 0xb, 0x125, 0x65);
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;
    rect_byte_size(0xa7, 0x59);
    nSize = (int)rect_byte_size(0x6f, 0x5d);
    g_pSpellScreenBuffer = alloc_far((long)nSize, 0);
    cga_save_rect_to_buffer(g_pSpellScreenBuffer, 0x12, 0xf, 0x6f, 0x5d);
    return;
}

#define CASTFACE_FRAME(slot)                                                                       \
    (*(unsigned short *)((char *)&g_nSpellSymbolAnimFrame + 4 + (slot) * 4))
#define CASTFACE_SPRITE(slot) (*(unsigned short *)((char *)__dat_15dc + 0x82 + (slot) * 4))

int cspell_cast_menu_loop(CombatActor *caster, int *out_result, int *preferred_caster_slot,
                          int *preselect_spell) {
    CombatActor *pCaster;
    MenuPage *page;
    unsigned school;
    int prevSchool;
    unsigned action;
    unsigned short done_flag;
    int redrawCount;
    int done;
    int spell_index;
    int hotspot;
    int prevHotspot;
    int state;
    int saved_palblend;
    unsigned short can_cast[3];
    int casterSlot;
    int save_flag;
    unsigned char far *pDest;
    int party_slot;
    int i;

    pCaster = caster;
    prevSchool = -1;
    done_flag = 0;
    redrawCount = 3;
    done = 0;
    spell_index = -1;
    hotspot = -1;
    prevHotspot = -1;
    casterSlot = -1;
    save_flag = 0;
    pDest = (unsigned char far *)0;

    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    resblit_load_pal_or_stream("cast.scx");
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;

    if (pCaster->inner != (CombatActorInner *)0) {
        page = menupage_load("spell.dat");
        school = (int)(char)pCaster->inner->pad_e[5];
    } else {
        page = menupage_load("req_cast.dat");
        if (preselect_spell != (int *)0 && *preselect_spell != -1) {
            school = *preselect_spell;
        } else {
            school = 5;
        }
        prevSchool = -1;
        for (i = 0; i < 3; i++) {
            if (i < g_gameState.party_count) {
                can_cast[i] = stat_actor_get(
                    &g_gameState.party_members[(char)g_gameState.party_roster[i]], 7, 1);
                if (can_cast[i] != 0 && casterSlot == -1) {
                    casterSlot = i;
                }
            } else {
                can_cast[i] = 0;
            }
        }
        if (preferred_caster_slot != (int *)0 && *preferred_caster_slot != -1 &&
            can_cast[*preferred_caster_slot] != 0) {
            casterSlot = *preferred_caster_slot;
        }
        pCaster = &g_gameState.party_members[(char)g_gameState.party_roster[casterSlot]];
        pDest = alloc_far((unsigned long)(unsigned)rect_byte_size(0xa8, 0x2d), 0);
        cga_save_rect_to_buffer(pDest, 0xf, 0x8e, 0xa8, 0x2d);
        save_flag = 1;
    }

    menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x, page->rect.y);
    if (save_flag != 0) {
        emsimg_map_then_call_180c(&g_pCastfaceSpriteTable[6]->wImageData,
                                  CASTFACE_SPRITE(casterSlot), CASTFACE_FRAME(casterSlot), 0);
    }
    screen_frame_present();
    menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x, page->rect.y);
    if (save_flag != 0) {
        emsimg_map_then_call_180c(&g_pCastfaceSpriteTable[6]->wImageData,
                                  CASTFACE_SPRITE(casterSlot), CASTFACE_FRAME(casterSlot), 0);
        save_flag = 0;
    }
    saved_palblend = g_nPalBlendMode;
    g_nPalBlendMode = 0;
    g_pPalQueuedForFlip = palette_set((unsigned char far *)0);
    *out_result = 0xa;
    cspell_symbol_resources_load(school);
    g_nSpellSymbolCount = 0;
    cspell_cast_menu_open_transition();

    while (done == 0) {
        action = menupage_run(page, &done_flag);
        if (done_flag != 0) {
            redrawCount = 3;
        }
        hotspot = cspell_hotspot_hittest_at_cursor(pCaster);
        if (action != 0) {
            state = (menupage_state_0e7c() == 2) ? 1 : 0;
        }

        switch (action) {
        case 2:
            if (state != 0) {
                dialog_play_record(0x137, 1);
                goto post_switch;
            }
            school = 0;
            goto post_switch;
        case 3:
            if (state != 0) {
                dialog_play_record(0x137, 1);
                goto post_switch;
            }
            school = 1;
            goto post_switch;
        case 4:
            if (state != 0) {
                dialog_play_record(0x137, 1);
                goto post_switch;
            }
            school = 2;
            goto post_switch;
        case 5:
            if (state != 0) {
                dialog_play_record(0x137, 1);
                goto post_switch;
            }
            school = 3;
            goto post_switch;
        case 6:
            if (state != 0) {
                dialog_play_record(0x137, 1);
                goto post_switch;
            }
            school = 4;
            goto post_switch;
        case 7:
            if (state != 0) {
                dialog_play_record(0x137, 1);
                goto post_switch;
            }
            school = 5;
            goto post_switch;
        case 1:
            if (state != 0) {
                dialog_play_record(0x138, 1);
                goto post_switch;
            }
            spell_index = -1;

        case 0x32:
            done = 1;
            goto post_switch;
        case 0x80:
        case 0x81:
        case 0x82:
            party_slot = (int)action - 0x80;
            if (can_cast[party_slot] != 0) {
                if (casterSlot != party_slot) {
                    casterSlot = party_slot;
                    pCaster =
                        &g_gameState.party_members[(char)g_gameState.party_roster[casterSlot]];
                    save_flag = 1;
                }
                goto post_switch;
            }
            cspell_menu_present_panel();
            screen_frame_present();
            cspell_menu_present_panel();
            dialog_play_record(0xd8, 1);
            goto post_switch;
        default:
            goto post_switch;
        }

    post_switch:
        if (hotspot != prevHotspot) {
            prevHotspot = hotspot;
            redrawCount = 2;
        }
        if (done == 0) {
            if (combat_arena_wait_confirm_cancel() != 0 && hotspot != -1) {
                spell_index = g_pSpellSymbolRecords[hotspot].wSpellId;
                done = 1;
            }
        }
        if (redrawCount != 0 && done == 0 && save_flag == 0) {
            menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x, page->rect.y);
            if (hotspot != -1) {
                cspell_info_panel_show(g_pSpellSymbolRecords[hotspot].wSpellId, 0, pCaster);
            } else {
                cspell_list_draw_castable(pCaster);
            }
            redrawCount--;
        }

        if (school != prevSchool) {
            if (prevSchool == -1) {
                prevSchool = school;
            }
            menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x, page->rect.y);
            screen_frame_present();
            menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x, page->rect.y);
            cspell_menu_present_panel();
            screen_frame_present();
            cspell_menu_present_panel();
            cspell_menu_animate_hilite(0x85, 1, hotspot, pCaster);
            cspell_symbol_resources_free();
            cspell_symbol_resources_load(school);
            if (school != prevSchool) {
                audio_play(0x1b);
            }
            hexanim_move_tiles(prevSchool, school);
            cspell_menu_animate_hilite(0x8d, -1, hotspot, pCaster);
            prevSchool = school;
        } else if (save_flag != 0) {
            menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x, page->rect.y);
            if (save_flag != 0) {
                cga_rect_paste_from_buffer(pDest, 0xf, 0x8e, 0xa8, 0x2d);
                emsimg_map_then_call_180c(&g_pCastfaceSpriteTable[6]->wImageData,
                                          CASTFACE_SPRITE(casterSlot), CASTFACE_FRAME(casterSlot),
                                          0);
            }
            screen_frame_present();
            menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x, page->rect.y);
            if (save_flag != 0) {
                cga_rect_paste_from_buffer(pDest, 0xf, 0x8e, 0xa8, 0x2d);
                emsimg_map_then_call_180c(&g_pCastfaceSpriteTable[6]->wImageData,
                                          CASTFACE_SPRITE(casterSlot), CASTFACE_FRAME(casterSlot),
                                          0);
                save_flag = 0;
            }
            cspell_menu_present_panel();
            screen_frame_present();
            cspell_menu_present_panel();
            hexanim_move_tiles(prevSchool, school);
            cspell_menu_animate_hilite(0x8d, -1, hotspot, pCaster);
        }
        cspell_menu_animate_hilite(0x85, 0, hotspot, pCaster);
        screen_frame_present();
    }

    while (combat_arena_wait_confirm_cancel() != 0) {
    }
    if (spell_index != -1) {
        cspell_select_power(out_result, spell_index, hotspot, pCaster);
        if (*out_result != -1) {
            goto close;
        }
        spell_index = -1;
    }
    *out_result = 0;

close:
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage =
        g_graphics_context.wVgaPage2Base;
    cga_rect_paste_from_buffer(g_pSpellScreenBuffer, 0x12, 0xf, 0x6f, 0x5d);
    cspell_menu_present_panel();
    g_nPalBlendMode = saved_palblend;
    g_pPalQueuedForFlip = palette_set((unsigned char far *)0);
    screen_frame_present();
    if (MK_FP(FP_SEG(pDest), FP_OFF(pDest))) {
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        gfx_present_dispatch(0, 0, 0x140, 0x78);
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        cga_rect_paste_from_buffer(pDest, 0xf, 0x8e, 0xa8, 0x2d);
        screen_frame_present();
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        cga_rect_paste_from_buffer(pDest, 0xf, 0x8e, 0xa8, 0x2d);
        _freemem(pDest);
    }
    menupage_end(page);
    menupage_free(page);
    cspell_symbol_resources_free();
    _freemem(g_pSpellScreenBuffer);
    if (pCaster->inner != (CombatActorInner *)0) {
        pCaster->inner->pad_e[5] = (unsigned char)school;
    } else {
        if (preferred_caster_slot != (int *)0) {
            *preferred_caster_slot = casterSlot;
        }
        if (preselect_spell != (int *)0) {
            *preselect_spell = school;
        }
    }
    return spell_index;
}

#pragma option -O-l
void cspell_tick_damage_terrain(void) {
    int x, y;
    register unsigned int field;
    register unsigned int actor;

    for (x = 0; x < 8; x++) {
        for (y = 0; y < 13; y++) {
            field = combatgrid_tile_terrain_field((char)x, (char)y);
            if (field != 0 && field != 2) {
                combatgrid_tick_tile_effect((char)x, (char)y);
            }
            actor = combatgrid_tile_terrain((char)x, (char)y);
            if (field != 0 && actor != 0) {
                switch (field) {
                case 1:
                    if (cbstat_char_bitmap_3w_test(((CombatActor *)actor)->inner->class_id, 0x13) ==
                        0) {
                        combat_arena_apply_damage((CombatActor *)actor, (int)RNDR(10, 19), 0, 1,
                                                  0x200, 0);
                    }
                }
            }
        }
    }
}
#pragma option -Ol

static void far cspell_actor_tick_status_effects(CombatActor *actor) {
    int chainFlag;
    int type;
    int next;
    int slot;

    chainFlag = 1;
    slot = actor->inner->status_head;
    while (slot != -1) {
        g_pStatusEffectPool[slot].nDuration_or_hp -= 1;
        next = g_pStatusEffectPool[slot].nNext;
        if (g_pStatusEffectPool[slot].nDuration_or_hp <= 0) {
            type = g_pStatusEffectPool[slot].nType;
            cspell_status_effect_remove(actor, slot);
            switch (type) {
            case 1:
                cspell_invoke_effect(actor, &actor, 0x20, &chainFlag, 0);
                combatgrid_tile_set_word(actor->inner->grid_x, actor->inner->grid_y, 0);
#ifdef V102CD
                actor = combat_actor_remove(actor);
#else
                combat_actor_remove(actor);
#endif
            }
        }
        slot = next;
    }
    return;
}

void far cspell_tick_actor_stat_fx(void) {
    int i;

    i = 0;
    if (i < g_nCombatActiveCount) {
        do {
            cspell_actor_tick_status_effects(&g_pCombatActiveActors[i]);
            i = i + 1;
        } while (i < g_nCombatActiveCount);
    }
    i = 0;
    if (i < g_nCombatOtherCount) {
        do {
            cspell_actor_tick_status_effects(&g_pCombatOtherActors[i]);
            i = i + 1;
        } while (i < g_nCombatOtherCount);
    }
    return;
}
