#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "structs.h"
#include "SRC/COMBAT/SPELL/SPELLFX.H"
#include "SRC/SYS/RAND.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/GAME/TIMERPL.H"
#include "SRC/R3D/VIS/PROXSCAN.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/WORLD/ACTOR/ACTSPAWN.H"
#include "SRC/COMBAT/SPELL/CSPELL.H"
#include "SRC/WORLD/LOOP/MAP.H"

unsigned short g_aPalEventBitMask[9] = {0x0001, 0x0002, 0x0004, 0x0008, 0x0010,
                                        0x0020, 0x0040, 0x0080, 0x0100};
unsigned char g_event_caption_glyph_table[9] = {0x1d, 0x1e, 0x1f, 0x21, 0x20,
                                                0x22, 0x23, 0x24, 0x25};
ImageRecord **g_pCastBmp = {0};

void far spellfx_cast_and_dispatch(void) {
    int nSpellId;
    short nEffectParam;
    short nDamage;

    cspell_subsystem_load();
    nSpellId =
        cspell_cast_menu_loop(&g_gameState.party_members[g_gameState.party_roster[0]], &nDamage,
                              &g_gameState.nSpellMenuCasterSlot, &g_gameState.nSpellMenuPreselect);

    if ((-1 < nSpellId) && (nSpellId < 0x2d)) {
        nEffectParam = g_pSpellDefs[nSpellId].nEffect_param;
    }
    cspell_subsystem_unload();

    switch (nSpellId) {
    case 0x00:
        spellfx_palette_fade_slot0(g_gameState.nSpellMenuCasterSlot, nDamage, nEffectParam);
        return;
    case 0x02:
        spellfx_combat_play_hit_effect(g_gameState.nSpellMenuCasterSlot, nDamage, nEffectParam);
        return;
    case 0x1a:
        spellfx_overworld_pal_fade_slot2(g_gameState.nSpellMenuCasterSlot, nDamage, nEffectParam);
        return;
    case 0x23:
        spellfx_combat_damage_flash_sfx(g_gameState.nSpellMenuCasterSlot, nDamage, nEffectParam);
        return;
    case 0x22:
        spellfx_palette_event_with_sound(g_gameState.nSpellMenuCasterSlot, nDamage, nEffectParam);
        return;
    case 0x08:
        spellfx_show_msg_pal_fade(g_gameState.nSpellMenuCasterSlot, nDamage, nEffectParam);
        return;
    case 0x0b:
        spellfx_save_then_cmap_recs(g_gameState.nSpellMenuCasterSlot, nDamage);
        return;
    case 0x11:
        spellfx_combat_roll_outcome(g_gameState.nSpellMenuCasterSlot, nDamage);
        return;
    case 0x12:
        spellfx_save_cmap_scene_events(g_gameState.nSpellMenuCasterSlot, nDamage);
        return;
    }
}

void far spellfx_palette_fade_slot0(short caster_slot, short damage, int effect_param) {
    unsigned long duration;

    audio_play(0x3a);
    dialog_play_record(199, 0);
    duration = (long)effect_param * (long)damage * 0x1e;
    if (duration != 0) {
        spellfx_pal_event_mask_upd(spellfx_pal_event_timer_upsert(0, duration));
        palette_fade_run_scheduled(palette_fade_schedule(1, duration));
        palette_apply_pending_load();
    }
    spellfx_party_member_take_damage(caster_slot, damage);
    return;
}

void far spellfx_combat_play_hit_effect(short caster_slot, short damage, int effect_param) {
    unsigned long duration;

    if (g_game_mode == 2) {
        audio_play(0x3a);
        dialog_play_record(200, 0);
        duration = (long)effect_param * (long)damage * 0x1e;
        if (duration != 0) {
            spellfx_pal_event_mask_upd(spellfx_pal_event_timer_upsert(1, duration));
            palette_fade_run_scheduled(palette_fade_schedule(2, duration));
            palette_apply_pending_load();
        }
        spellfx_party_member_take_damage(caster_slot, damage);
    }
    return;
}

void far spellfx_overworld_pal_fade_slot2(short caster_slot, short damage, int effect_param) {
    unsigned long duration;

    if (g_game_mode != 2) {
        audio_play(0x3a);
        dialog_play_record(0xc9, 0);
        duration = (long)effect_param * (long)damage * 0x1e;
        if (duration != 0) {
            spellfx_pal_event_mask_upd(spellfx_pal_event_timer_upsert(2, duration));
            palette_fade_run_scheduled(palette_fade_schedule(3, duration));
            palette_apply_pending_load();
        }
        spellfx_party_member_take_damage(caster_slot, damage);
    }
    return;
}

void far spellfx_combat_damage_flash_sfx(short caster_slot, short damage, int effect_param) {
    long duration;

    audio_play(0x51);
    dialog_play_record(0xca, 0);
    duration = (long)effect_param * 0x1e;
    if (duration != 0) {
        spellfx_pal_event_mask_upd(spellfx_pal_event_timer_upsert(3, duration));
    }
    spellfx_party_member_take_damage(caster_slot, damage);
    return;
}

void far spellfx_palette_event_with_sound(short caster_slot, short damage, int effect_param) {
    long duration;

    audio_play(0x51);
    dialog_play_record(0xcb, 0);
    duration = (long)effect_param * 0x1e;
    if (duration != 0) {
        spellfx_pal_event_mask_upd(spellfx_pal_event_timer_upsert(4, duration));
    }
    spellfx_party_member_take_damage(caster_slot, damage);
    return;
}

void far spellfx_show_msg_pal_fade(short caster_slot, short damage, int effect_param) {
    unsigned long duration;

    audio_play(0xc);
    dialog_play_record(0xcc, 0);
    duration = (long)effect_param * 0x1e;
    if (duration != 0) {
        spellfx_pal_event_mask_upd(spellfx_pal_event_timer_upsert(5, duration));
    }
    spellfx_party_member_take_damage(caster_slot, damage);
    return;
}

void far spellfx_save_then_cmap_recs(short target, short damage) {
    spellfx_party_member_take_damage(target, damage);
    if (RND(100) <= (unsigned)(damage * 10)) {
        audio_play(0xc);
        spellfx_run_request_cmap_dialog(0xb);
    } else {
        dialog_play_record(0xd1, 0);
    }
}

void far spellfx_combat_roll_outcome(short casterSlot, short damage) {
    spellfx_party_member_take_damage(casterSlot, damage);
    if (RND(100) <= (unsigned)(damage * 10)) {
        audio_play(0xd);
        spellfx_run_request_cmap_dialog(0x11);
    } else {
        dialog_play_record(0xd4, 0);
    }
}

void far spellfx_save_cmap_scene_events(short target, short damage) {
    spellfx_party_member_take_damage(target, damage);
    if (RND(100) <= (unsigned)((damage - 4) * 10)) {
        audio_play(0xd);
        spellfx_run_request_cmap_dialog(0x12);
    } else {
        dialog_play_record(0xd7, 0);
    }
}

TimerEventEntry *far spellfx_pal_event_timer_upsert(unsigned short subId, long value) {
    return timerpool_upsert(2, subId, 0x80, value);
}

void spellfx_pal_event_mask_upd(TimerEventEntry *entry) {
    if ((entry != 0) && (entry->wSub_id < 9)) {
        if (entry->nValue != 0) {
            g_gameState.wPalEventMask |= g_aPalEventBitMask[entry->wSub_id];
        } else {
            g_gameState.wPalEventMask &= ~g_aPalEventBitMask[entry->wSub_id];
        }
    }
    return;
}

int spellfx_event_mask_test_bit(int bitIndex) {
    return g_gameState.wPalEventMask & g_aPalEventBitMask[bitIndex];
}

short far spellfx_actor_has_ration(WorldObject far *entry) {
    register short result;
    Actor far *actor;
    int i;

    result = 0;
    actor = actorspawn_objfixed((unsigned int)g_gameState.nZoneId, entry->pos.xy.nWorld_x,
                                entry->pos.xy.nWorld_y);
    if (actor != 0) {
        for (i = 0; i < (int)(unsigned int)actor->itemCount; i++) {
            switch (ACTOR_ITEM(actor, i).item_id) {
            case 0x48:
            case 0x49:
            case 0x4a:
                result = 1;
            }
        }
        actorspawn_destroy_and_persist(actor);
    }
    return result;
}

short far spellfx_actor_has_special_item(WorldObject far *entry) {
    short result;
    Actor far *actor;
    int i;

    result = 0;
    actor = actorspawn_objfixed((unsigned int)g_gameState.nZoneId, entry->pos.xy.nWorld_x,
                                entry->pos.xy.nWorld_y);
    if (actor != 0) {
        for (i = 0; i < actor->itemCount; i++) {
            switch ((unsigned int)ACTOR_ITEM(actor, i).item_id) {
            case 1:
            case 2:
            case 4:
            case 5:
            case 6:
            case 7:
            case 8:
            case 9:
            case 10:
            case 11:
            case 12:
            case 13:
            case 14:
            case 15:
            case 16:
            case 17:
            case 0x2b:
            case 0x58:
            case 0x5a:
            case 0x77:
            case 0x85:
                result = 1;
                break;
            }
        }
        actorspawn_destroy_and_persist(actor);
    }
    return result;
}

void far spellfx_run_request_cmap_dialog(int request_type) {
    register int running;
    register MenuPage *page;
    long saved_lInsetCameraPosZ;
    long saved_z;
    short saved_yaw;
    short saved_viewport_x;
    short saved_viewport_y;
    short saved_viewport_w;
    short saved_viewport_h;
    unsigned short redrawMenu;
    int renderScene;

    running = 1;
    redrawMenu = 1;
    renderScene = 1;
    saved_lInsetCameraPosZ = g_gameState.lInsetCameraPosZ;
    saved_viewport_x = g_world_widget->viewport.x;
    saved_viewport_y = g_world_widget->viewport.y;
    saved_viewport_w = g_world_widget->viewport.width;
    saved_viewport_h = g_world_widget->viewport.height;
    g_world_widget->viewport.x = 0x86;
    g_world_widget->viewport.y = 0x10;
    g_world_widget->viewport.width = 0xa7;
    g_world_widget->viewport.height = 0x59;
    map_camera_snap_face_south(&saved_z, &saved_yaw);
    g_world_camera->base.pos.nWorld_z = g_lWorldZMax;
    g_full_redraw_needed = 1;
    page = menupage_load("req_cmap.dat");
    menupage_begin(page);

    while (running) {
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        if (redrawMenu != 0) {
            menupage_draw(page);
        }
        if (renderScene) {
            world_render_scene_dispatch(0);
            g_graphics_context.bClip_enabled = '\x01';
            g_graphics_context.clip.xmin = 0x86;
            g_graphics_context.clip.ymin = 0x10;

            g_graphics_context.clip.xmax = 300;
            g_graphics_context.clip.ymax = 0x68;
            switch (request_type) {
            case 0xb:
                proxscan_paged_dispatch_all();
                break;
            case 0x11:
                proxscan_draw_cmap_inset_markers();
                break;
            case 0x12:
                proxscan_broadcast_scene_events();
                break;
            }
        }
        screen_frame_present();
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        if (redrawMenu != 0) {
            menupage_draw(page);
            redrawMenu = 0;
        }
        if (renderScene) {
            screen_frame_sync_buffers_rect(0xb, 0x80);
            renderScene = 0;
        }
        switch (menupage_run(page, &redrawMenu)) {
        case 0x12:
            if (menupage_state_0e7c() == 2) {
                dialog_play_record(0xecL, 1);
            } else {
                running = 0;
            }
            break;
        case 1:
            running = 0;
            break;
        }
    }
    menupage_end(page);
    menupage_free(page);
    g_full_redraw_needed = 0;
    map_camera_restore_z_yaw(saved_z, saved_yaw);
    g_world_widget->viewport.x = saved_viewport_x;
    g_world_widget->viewport.y = saved_viewport_y;
    g_world_widget->viewport.width = saved_viewport_w;
    g_world_widget->viewport.height = saved_viewport_h;
    g_gameState.lInsetCameraPosZ = saved_lInsetCameraPosZ;
}

void spellfx_cast_bmp_load(void) {
    g_pCastBmp = resblit_load_asset_table("cast.bmp", 0);
    return;
}

void spellfx_cast_bmp_free(void) {
    free_image_record(g_pCastBmp);
    g_pCastBmp = 0;
    return;
}

void spellfx_draw_events_caption(void) {
    int prev_slot;
    int x;
    char buf[10];
    int i;
    int n;

    g_graphics_context.bClip_enabled = 0;
    g_graphics_context.bText_style_flags = 1;

    blit_sprite_indirect((unsigned short)*g_pCastBmp, 0x80, 2, 0);

    prev_slot = font_activate(0);
    font_activate(g_nSpellFontSlot);

    for (i = 0, n = 0; i < 9; i++) {
        if (spellfx_event_mask_test_bit(i) != 0) {
            buf[n] = g_event_caption_glyph_table[i] + 1;
            n++;
        }
    }
    buf[n] = 0;

    x = 0xA0 - (font_text_width_ds(buf) >> 1);
    font_draw_text_ds(buf, x, 1);

    font_activate(prev_slot);
}

void far spellfx_party_member_take_damage(short roster_slot, short damage) {
    CombatActor *member;
    int i;

    member = &g_gameState.party_members[g_gameState.party_roster[roster_slot]];
    stat_combatant_modify(member, 0x10, (long)(short)(-damage << 8), 100);

    if (g_gameState.nChapter == 8) {
        for (i = 0; i < member->actor_record->itemCount; i++) {
            if (ACTOR_ITEM(member->actor_record, i).item_id == 1 &&
                (ACTOR_ITEM(member->actor_record, i).flags & 0x40) != 0) {
                if (ACTOR_ITEM(member->actor_record, i).condition < damage) {
                    ACTOR_ITEM(member->actor_record, i).condition = 0;
                    return;
                }
                ACTOR_ITEM(member->actor_record, i).condition =
                    ACTOR_ITEM(member->actor_record, i).condition - (char)damage;
                return;
            }
        }
    }
}
