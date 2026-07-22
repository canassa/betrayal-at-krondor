#include <dos.h>
#include "structs.h"
#include "globals.h"
#include "SRC/SCREENS/ITEMUSE.H"
#include "SRC/SYS/RAND.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/GAME/TIMERPL.H"
#include "SRC/R3D/VIS/PROXSCAN.H"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/WORLD/ACTOR/ACTSPAWN.H"
#include "SRC/COMBAT/ACTOR/CACTOR.H"
#include "SRC/WORLD/LOOP/EXPLORE.H"

#include "defines.h"

void far itemuse_view_look_south_modal(void) {
    long savedInsetZ;
    long savedZ;
    short savedYaw;
    unsigned short savedRedraw;
    short savedViewX;
    short savedViewY;
    short savedViewW;
    short savedViewH;

    savedRedraw = g_full_redraw_needed;
    savedInsetZ = g_gameState.lInsetCameraPosZ;
    savedViewX = g_world_widget->viewport.x;
    savedViewY = g_world_widget->viewport.y;
    savedViewW = g_world_widget->viewport.width;
    savedViewH = g_world_widget->viewport.height;
    g_world_widget->viewport.x = 0xd;
    g_world_widget->viewport.y = 0xb;
    g_world_widget->viewport.width = 0x126;
    g_world_widget->viewport.height = 0x79;
    explore_camera_snap_face_south(&savedZ, &savedYaw);
    g_world_camera->base.pos.nWorld_z = (g_lWorldZMax * 0x62L) / 100L;
    g_full_redraw_needed = 1;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    world_render_scene_dispatch(0);
    g_graphics_context.bClip_enabled = '\x01';
    g_graphics_context.clip.xmin = 0xd;
    g_graphics_context.clip.ymin = 0xb;
    g_graphics_context.clip.xmax = 0x132;
    g_graphics_context.clip.ymax = 0x83;
    proxscan_paged_dispatch_all();
    screen_frame_present();
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    screen_frame_sync_buffers_rect(0xb, 0x80);
    dialog_input_wait_release(0, 1);
    audio_sfx_play_n_times(0x3b, 0, 1);
    while (dialog_poll_arrow_or_button() == 0) {
        screen_frame_present();
    }
    g_full_redraw_needed = savedRedraw;
    explore_camera_restore_z_yaw(savedZ, savedYaw);
    g_world_widget->viewport.x = savedViewX;
    g_world_widget->viewport.y = savedViewY;
    g_world_widget->viewport.width = savedViewW;
    g_world_widget->viewport.height = savedViewH;
    g_gameState.lInsetCameraPosZ = savedInsetZ;
}

int itemuse_dispatch_on_target(Actor far *actor, ItemSlot far *item, ItemSlot far *target,
                               int memberIdx) {
    ItemRecord far *rec;
    int result;
    int combat_result;
    unsigned int flags;
    unsigned short category;
    CombatActor *member;
    int outcome;
    int i;

    rec = itemtbl_record_ptr(item);
    result = -1;
    combat_result = -1;
    outcome = 0;
    flags = rec->wFlags;
    category = rec->wCategory;
    member = gstate_party_member_record(memberIdx - 1);

    if ((flags & 0x80) != 0 && member->stats[7].max == '\0') {
        dialog_play_record(0x1b7745, 0);
        return -1;
    }
    if ((flags & 0x200) != 0 && member->stats[7].max != '\0') {
        dialog_play_record(0x1b7771, 0);
        return -1;
    }
    if ((flags & 0x40) != 0 && g_wInCombatMode == 0) {
        dialog_play_record(0x1b7746, 0);
        return -1;
    }
    if ((flags & 0x100) != 0 && g_wInCombatMode != 0) {
        dialog_play_record(0x1b7747, 0);
        return -1;
    }
    if ((flags & 0x2000) != 0 && item->condition == '\0') {
        if ((item->flags & 0x40) != 0 || (flags & 2) != 0) {
            g_gameState.nEvtArgCount = 1;
            goto play_776c;
        }
        g_gameState.nEvtArgCount = 0;
        goto play_776c;
    }
    if (item->item_id == '\x01' && item->condition == '\0') {
        g_gameState.nEvtArgCount = 2;
    play_776c:
        dialog_play_record(0x1b776c, 0);
        return -1;
    }

    g_gameState.nEvtArgCount = (short)item->item_id;
    actor->needsFlush = TRUE;

    if (category != 0 && (int)category <= 4) {

        if (category == 4 && g_wInCombatMode != 0) {
            dialog_play_record(0x1b7747, 0);
            return -1;
        }
        if (category == 3 && g_wInCombatMode != 0 && (item->flags & 0x40) != 0 &&
            item->condition != '\0') {
            if (item->item_id == '\x02' && g_game_mode == 2) {
                dialog_play_record(0x1b7770, 0);
                goto done;
            }
            if (item->item_id != '\x02' && item->item_id != '\x04') {
                goto done;
            }
            if (g_gameState.nChapter == 8) {
                dialog_play_record(0x1b7773, 0);
                goto done;
            }

            combat_result = (unsigned int)item->item_id;
            outcome = 1;
            goto done;
        } else if (memberIdx != 0 && cmbinv_member_can_equip_cat(memberIdx, item) != 0) {
            for (i = 0; i < (int)(unsigned int)actor->itemCount; i++) {
                if (itemtbl_record_ptr(ACTOR_ITEMS(actor) + i)->wCategory == category) {
                    ACTOR_ITEM(actor, i).flags &= ~0x40;
                }
            }
            item->flags |= 0x40;
            outcome = -2;
        }
    } else if (category == 9) {

        if (target != (ItemSlot far *)0) {
            ItemRecord far *trec = itemtbl_record_ptr(target);
            if (item->item_id == 'i') {
                if (trec->wCategory == 0x17) {
                    outcome = -1;
                    target->item_id = 'I';
                }
            } else if ((rec->wEffect_arg_a & 0x80) != 0 && target->item_id >= 0x24 &&
                       target->item_id <= 0x26) {
                outcome = -1;
                target->item_id = target->item_id + '\x03';
            } else if (trec->wCategory == 1) {
                target->flags &= rec->wEffect_arg_b;
                target->flags |= rec->wEffect_arg_a;
                outcome = 1;
            }
        }
    } else if (category == 10) {

        int slot_idx = member->cParty_slot + -1;
        if (item->item_id == 'q' && (char)g_gameState.abActorStatusRanks[slot_idx][2] != '\0' &&
            target == (ItemSlot far *)0) {
            outcome = -1;
            stat_combatant_apply_delta(member, 2, -100);
            if (g_wInCombatMode != 0) {
                g_current_actor->inner->flags &= ~CAF_POISON;
            }
            dialog_play_record(0x1b776f, 0);
        } else if (target != (ItemSlot far *)0) {
            ItemRecord far *trec = itemtbl_record_ptr(target);
            if (trec->wCategory == 4) {
                target->flags &= rec->wEffect_arg_b;
                target->flags |= rec->wEffect_arg_a;
                outcome = 1;
            }
        }
    } else if (category == 0xb) {

        if (target != (ItemSlot far *)0) {
            ItemRecord far *trec = itemtbl_record_ptr(target);
            if (trec->wCategory == 1 || trec->wCategory == 4) {
                target->flags &= rec->wEffect_arg_b;
                target->flags |= rec->wEffect_arg_a;
                outcome = 1;
            }
        }
    } else if (category == 8) {

        if (target != (ItemSlot far *)0) {
            ItemRecord far *trec = itemtbl_record_ptr(target);
            if (trec->wCategory == rec->wEffect_arg_a && (target->flags & 0x10) == 0) {
                if ((target->flags & 0x20) != 0) {
                    int stat_idx = (rec->wEffect_arg_a == 4) ? 9 : 10;
                    unsigned int skill = stat_actor_get(member, stat_idx, 0);
                    stat_combatant_modify(member, stat_idx, 1, 3);
                    target->condition =
                        target->condition +
                        (char)((int)((100 - (unsigned int)target->condition) * (int)skill) / 100);
                    target->flags &= ~0x20;
                    outcome = 1;
                } else {
                    g_gameState.nEvtArgItemId = (short)target->item_id;
                    dialog_play_record(0x1b775e, 0);
                    g_gameState.nEvtArgItemId = (unsigned int)item->item_id;
                    return -1;
                }
            }
        }
    } else if (category == 0xc) {

        if (target != (ItemSlot far *)0) {
            ItemRecord far *trec = itemtbl_record_ptr(target);
            if (trec->wCategory == 2) {
                if (item->item_id == 'M') {
                    if (target->item_id != ' ' && target->item_id != '\"') {
                        target->condition = 'd';
                        target->flags &= ~0x30;
                        outcome = 1;
                    }
                } else if (target->item_id == ' ' || target->item_id == '\"') {
                    target->condition = 'd';
                    target->flags &= ~0x30;
                    outcome = 1;
                }
            }
        }
    } else if (category == 0x14) {

        stat_combatant_apply_delta(member, rec->wEffect_arg_a, rec->wEffect_arg_b);
        outcome = 1;
    } else if (category == 0xd) {

        outcome = combat_actor_bitmap_set_bit((int)member, (unsigned int)item->condition);
    } else if (category == 0x11) {

        itemuse_apply_stat_effects(member, item, rec);
        outcome = 1;
    } else if (category == 0x10) {

        if (item->item_id == 'x') {
            g_gameState.nEvtArgCount = (short)item->condition;
            if (item->condition == ' ') {
                long map_x = (g_world_camera->base.pos.xy.nWorld_x + -640000) / 0x8f7 + 0x90;
                long map_y = 0xc0 - (g_world_camera->base.pos.xy.nWorld_y + -640000) / 0x92a;

                if (gstate_event_read(MAP_VIEWED(' ')) == 0) {
                    dialog_play_record(0x1b7753, 0);
                }
                g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage =
                    g_graphics_context.wVgaPage1Base;
                resblit_load_pal_or_stream("RIFTMAP.SCR");
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                screen_clear_both_pages();
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                if ((g_gameState.nEvtArgCount = (short)g_gameState.nZoneId) == 9) {
                    g_graphics_context.bGfx_outline_color = 'l';
                    g_graphics_context.bClip_enabled = g_graphics_context.bGfx_fill_enabled = '\0';
                    draw_rect_filled((int)map_x + -6, (int)map_y + -5, 0xc, 10);
                }
                dialog_play_record(0x1b7772, 0);
            } else {
                dialog_play_record(0x1b7753, 0);
            }

            gstate_event_write(MAP_VIEWED(item->condition), 1);
        } else {
            dialog_play_record(0x1b7742, 0);
        }
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
        resblit_load_pal_or_stream("INVENTOR.SCR");
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        outcome = -2;
    } else if (category == 0x12) {

        ActorStatModifier modifier;
        ActorStatModifier *slot_mods;
        int slot_idx = member->cParty_slot + -1;
        int stat_out;
        modifier.wMaskFlags = rec->wEffect_arg_a;
        modifier.payload.wStatMask = rec->wEffect_arg_b;
        modifier.payload.nValue = rec->wEffect_chance_pct;
        modifier.payload.dwTApply = g_gameState.game_time;
        modifier.payload.dwTExpiry = g_gameState.game_time + (unsigned long)rec->wEffect_stat_value * 0x708;
        i = 0;
        outcome = 1;
        slot_mods = g_gameState.aActorStatModifiers[slot_idx];
        while (i < 8) {
            stat_apply_modifier((unsigned short *)slot_mods, &stat_out);
            if (slot_mods->wMaskFlags != 0 &&
                slot_mods->payload.wStatMask == modifier.payload.wStatMask) {
                outcome = 0;
            }
            i++;
            slot_mods++;
        }
        if (outcome != 0) {
            stat_modifier_table_insert(member, &modifier);
        } else {
            dialog_play_record(0x1b7760, 0);
        }
    } else if (category == 0x13) {

        dialog_play_record(0x1b7742, 0);
        do {
            int heal_amt = rec->wEffect_arg_a;
            int arg_b = rec->wEffect_arg_b;
            if (arg_b > 1) {
                heal_amt = heal_amt + (int)RND(arg_b);
            }
            for (i = 0; i < 7; i++) {
                if (i != 4) {
                    stat_combatant_apply_delta(member, i, -5);
                }
            }
            stat_combatant_modify(member, 0x10, (long)((short)heal_amt << 8), 100);
            g_gameState.lEvtArgGoldCost = (long)(int)stat_actor_get(member, 0x10, 0);
            g_gameState.lEvtArgValue = (long)(int)stat_actor_get(member, 0x10, 1);
            g_gameState.lEvtArgGoldCost = (long)(int)stat_actor_get(member, 0x10, 0);
            g_gameState.lEvtArgValue = (long)(int)stat_actor_get(member, 0x10, 1);
            g_gameState.lEvtArgAuxValue = (long)(short)heal_amt;
            if ((item->condition += 0xff) == '\0') {
                cmbinv_actor_inv_remove_item(actor, item);
                return -1;
            }
        } while (dialog_play_record(0x1b7744, 0) == 0);
        return -1;
    } else if (category == 0x15) {

        if ((item->flags & 1) != 0) {
            for (i = 0; i < g_gameState.nTimerEventPoolCount; i++) {
                if (g_gameState.aTimerEventPool[i].bKind == '\x01' &&
                    g_gameState.aTimerEventPool[i].wSub_id == 0) {
                    g_gameState.aTimerEventPool[i].nValue = 0;
                }
            }
            timerpool_tick(0);
            itemuse_party_tick_temporary();
            return -1;
        }
        if (timerpool_contains(1, 0) == 0) {
            if (item->item_id == 'T' && g_gameState.nChapter == 4 && g_gameState.nZoneId == '\v') {
                if (g_wInCombatMode != 0) {
                    dialog_play_record(0x1b7770, 0);
                    return -1;
                }
                dialog_play_record(0x1b776e, 0);
                return 0x54;
            }
            outcome = -2;
            item->flags |= 1;
            palette_fade_run_scheduled(palette_fade_schedule(0, (unsigned long)rec->wEffect_arg_a * 0x708));
        }
    } else if (category == 0x16 && g_wInCombatMode != 0) {

        combat_result = (unsigned int)item->item_id;
        outcome = 1;
    } else if (category == 0x19) {

        switch ((unsigned int)item->item_id) {
        case 0x66:
            if (g_dialog_in_scene == 0 && g_wInCombatMode == 0 && g_game_mode != 2 &&
                g_full_redraw_needed == 0) {
                outcome = 1;
                result = 0x66;
                break;
            }
            dialog_play_record(0x1b7770, 0);
            break;
        case 7:
            if (g_dialog_in_scene == 0 && g_wInCombatMode == 0) {
                dialog_play_record(0x1b7742, 0);
                itemuse_view_look_south_modal();
                return -1;
            }
            dialog_play_record(0x1b7770, 0);
            break;
        case 0x51: {

            /* One 4-byte scratch slot (`music`): its HIGH word holds the chosen
             * track id, its LOW word the previously-playing track that
             * audio_music_play() returns (replayed after the dialog).  The track
             * id is a nested ternary INSIDE the call argument, chained through
             * the high-word store: the ternary joins its arms in AX (each arm a
             * bare `mov ax,imm`), the chained assignment commits the high word
             * from that same AX, and the argument push reads it too
             * (`mov [bp-0x12],ax; push ax`).  A named `int track` instead homes
             * the value in DX and breaks both the store and the push. */
            unsigned long music;
            int hp = stat_actor_get(member, 0xb, 0);

            ((int *)&music)[0] = audio_music_play(((int *)&music)[1] = (hp > 0x50   ? 0x3ef
                                                                        : hp > 0x41 ? 0x40f
                                                                        : hp > 0x2d ? 0x410
                                                                                    : 0x3f0));
            dialog_play_record(0x1b7742, 0);
            audio_music_play((int)music);
            stat_combatant_modify(member, 0xb, (unsigned long)RNDR(0x28, 0x9f), 0);
            outcome = -1;
            break;
        }
        case 0xe:

            if (target != (ItemSlot far *)0 && target->item_id == '\x01') {
                if (target->condition != 'd') {
                    if (item->condition + target->condition > 0x64) {
                        item->condition = item->condition - ('d' - target->condition);
                        target->condition = 'd';
                    } else {
                        target->condition += item->condition;
                        cmbinv_actor_inv_remove_item(actor, item);
                    }
                    dialog_play_record(0x1b7742, 0);
                }
                return -1;
            }
            break;
        case 0x10:
            if (target->item_id != '\x17') {
                if (itemtbl_inv_count_by_kind(actor, 0x17) == 0) {
                    break;
                }
            }
            i = 0;
            outcome = 1;
            for (; i < (int)(unsigned int)actor->itemCount; i++) {
                if (ACTOR_ITEM(actor, i).item_id == '\x17') {
                    ACTOR_ITEM(actor, i).item_id = '\x16';
                }
            }
            break;
        case 8:
            if (gstate_is_party_member(3) != 0) {
                unsigned int bits;
                g_gameState.lEvtArgGoldCost = 0;
                g_gameState.lEvtArgGoldCost = (long)combat_actor_bitmap_set_bit(
                    (int)&g_gameState.party_members[CHR_PUG], RND(0x2d));
                if (g_gameState.lEvtArgGoldCost == 0) {
                    g_gameState.lEvtArgGoldCost = (long)combat_actor_bitmap_set_bit(
                        (int)&g_gameState.party_members[CHR_PUG], RND(0x2d));
                }
                i = 0;
                outcome = 1;
                for (; i < 3; i++) {
                    bits = g_gameState.party_members[CHR_OWYN].pSpellsKnown[i] |
                           g_gameState.party_members[CHR_PUG].pSpellsKnown[i];
                    g_gameState.party_members[CHR_OWYN].pSpellsKnown[i] = bits;
                    g_gameState.party_members[CHR_PUG].pSpellsKnown[i] = bits;
                }
            }
            break;
        }
    }

done:
    if (outcome == 0) {
        dialog_play_record(0x1b7743, 0);
        return result;
    }
    if (outcome == 1) {
        dialog_play_record(0x1b7742, 0);
    }
    if (rec->wUse_sfx != 0) {
        audio_sfx_play_n_times(rec->wUse_sfx & 0xff, rec->wUse_sfx >> 8, 1);
    }
    if ((outcome == 1 || outcome == -1) && combat_result < 0) {
        if ((flags & 0x20) != 0) {
            cmbinv_actor_inv_remove_item(actor, item);
        } else if ((flags & 0xa000) != 0) {
            if (item->condition > 1) {
                item->condition--;
            } else if ((flags & 0x10) != 0) {
                cmbinv_actor_inv_remove_item(actor, item);
            } else {
                item->condition = '\0';
            }
        }
    }
    if (g_wInCombatMode != 0) {
        return combat_result;
    }
    return result;
}

void far itemuse_apply_stat_effects(CombatActor *actor, ItemSlot far *item,
                                    ItemRecord far *record) {
    int slotIdx;
    unsigned short event_idx;
    int i;

    slotIdx = actor->cParty_slot - 1;

    event_idx = ITEM_USED(slotIdx * 0x14 + item->item_id);

    if (slotIdx < 0)
        return;
    if (record->wEffect_arg_a == 0)
        return;
    if (item->condition == 0)
        return;

    if (gstate_event_read(event_idx) != 0)
        goto rand_path;

    gstate_event_write(event_idx, 1);
    i = 0;
    do {
        if (record->wEffect_arg_a & (1 << i)) {
            stat_combatant_modify(actor, i, (long)((unsigned long)(record->wEffect_arg_b << 8)), 0);
        }
        i++;
    } while (i < 0x10);
    return;

rand_path:
    if (RND(100) >= record->wEffect_chance_pct)
        return;
    i = 0;
    do {
        if (record->wEffect_arg_a & (1 << i)) {
            stat_combatant_modify(actor, i, (long)(unsigned long)record->wEffect_stat_value, 2);
        }
        i++;
    } while (i < 0x10);
}

void far itemuse_actor_spawn_clone_inv(Actor far *src_actor, unsigned int kind, long world_x,
                                       long world_y) {
    Actor far *new_actor;
    int i;

    new_actor = actorspawn_objfixed(kind, world_x, world_y);
    new_actor->needsFlush = TRUE;
    new_actor->itemCount = src_actor->itemCount;
    for (i = 0; i < (int)(unsigned)src_actor->itemCount; i++) {
        ACTOR_ITEM(new_actor, i) = ACTOR_ITEM(src_actor, i);
        (ACTOR_ITEMS(new_actor) + i)->flags &= 0xffbf;
    }
    actorspawn_destroy_and_persist(new_actor);
}

void far itemuse_ground_pile_open_inv(void) {
    Actor far *actor;
    int i;

    if ((actor =
             actorspawn_objfixed((unsigned int)g_gameState.nZoneId, g_world_camera->base.pos.xy.nWorld_x,
                                 g_world_camera->base.pos.xy.nWorld_y)) == 0) {
        actor =
            actorspawn_enc_location((unsigned int)g_gameState.nZoneId, g_world_camera->base.pos.xy.nWorld_x,
                                    g_world_camera->base.pos.xy.nWorld_y);
    }
    actor->needsFlush = TRUE;
    g_gameState.ground_pile->needsFlush = TRUE;
    for (i = 0; i < (int)(unsigned)g_gameState.ground_pile->itemCount; i++) {
        ACTOR_ITEM(actor, i) = ACTOR_ITEM(g_gameState.ground_pile, i);
    }
    actor->itemCount = g_gameState.ground_pile->itemCount;
    g_gameState.ground_pile->itemCount = 0;
    dialog_play_record(0x1b775b, 0);
    cmbinv_inventory_screen_run(actor, 0, 0);
    actorspawn_destroy_and_persist(actor);
}

void far itemuse_party_tick_temporary(void) {
    int slot;
    int i;
    Actor far *actor;
    ItemSlot far *item;

    for (slot = 0; slot < g_gameState.party_count; slot++) {
        actor = gstate_party_member_record(slot)->actor_record;
        for (i = 0, item = ACTOR_ITEMS(actor); i < actor->itemCount; i++, item++) {
            if (item->item_id == 'T' && (item->flags & 1)) {
                item->flags &= ~1;
                if (item->condition-- <= 1) {
                    cmbinv_actor_inv_remove_item(actor, item);
                }
            } else if (item->item_id == 6 && (item->flags & 1)) {
                item->flags &= ~1;
                if (item->condition != 0) {
                    item->condition--;
                }
            }
        }
    }
}

void far itemuse_cam_vert_raise_anim(long amplitude_z, int apex_hold_frames) {
    unsigned short menuRedraw;
    int sfxStarted;
    WorldEntity savedCamera;
    long zOffset;
    int angle;
    unsigned int key;

    menuRedraw = 1;
    sfxStarted = audio_sfx_play_n_times(0xc, 0, 0);

    angle = 0x400;
    savedCamera = *g_world_camera;
    g_wZoneFlags |= 8;
    while (angle != 0) {
        zOffset = (long)r3d_tbl_cos(angle) * amplitude_z / 2L >> 0xe;
        g_world_camera->base.pos.nWorld_z =
            savedCamera.base.pos.nWorld_z + amplitude_z / 2L - zOffset;
        if (angle != -32768 || apex_hold_frames-- < 0) {
            angle += 0x400;
        }
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        audio_ambient_tick();
        if (menuRedraw != 0) {
            menupage_draw(g_pReqMainPage);
        }
        world_render_scene_dispatch(0);
        uiwidget_compass_draw();
        screen_frame_present();
        if ((key = menupage_run(g_pReqMainPage, &menuRedraw)) != 0) {
            if (menupage_state_0e7c() == 1) {
                if (key == 0x4b) {
                    g_world_camera->base.orientation.yaw += 0x140;
                } else if (key == 0x4d) {
                    g_world_camera->base.orientation.yaw -= 0x140;
                } else if (key == 0x48) {
                    g_world_camera->base.orientation.pitch -=
                        (g_world_camera->base.orientation.pitch > -0x17c) ? 0x40 : 0;
                } else if (key == 0x50) {
                    g_world_camera->base.orientation.pitch +=
                        (g_world_camera->base.orientation.pitch < 0x1c2) ? 0x40 : 0;
                }
            }
        }
    }
    if (sfxStarted != 0) {
        audio_sfx_stop(0xc);
    }
    *g_world_camera = savedCamera;
    g_wZoneFlags &= ~8;
}
