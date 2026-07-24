#include <stdio.h>
#include <stdlib.h>

#include "structs.h"
#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/GAME/MAINDATA.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/UI/MODALSCR.H"
#include "SRC/IO/IO.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/GFX/RASTER/DRAWLINE.H"
#include "SRC/GFX/RASTER/PIXEL.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/TOWNSCN.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/SCREENS/INVENTOR.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/CHAR/CHARSCRN.H"
#include "SRC/SCREENS/INVINSP.H"
#include "SRC/WORLD/ACTOR/ACTORREC.H"
#include "SRC/SCREENS/ENCAMP.H"
#include "SRC/WORLD/ZONE/ZONE.H"


void modalscreen_teleport_dat_load(int n_index) {
    IoFile *stream;

    stream = bak_fopen("TELEPORT.DAT", "rb");
    bak_fseek(stream, n_index * sizeof(g_gameState.abTeleportRecord), 0);
    bak_fread(g_gameState.abTeleportRecord, sizeof(g_gameState.abTeleportRecord), 1, stream);
    bak_fclose(stream);
}

int far modalscreen_pending_scene_trans(void) {
    PlayerSpawnRecord spawn;
    unsigned short scene_kind;
    int hadPending;

    spawn = *(PlayerSpawnRecord *)g_gameState.abTeleportRecord;
    hadPending = 0;
    g_gameState.abTeleportRecord[0] = '\0';
    if (spawn.bZoneId != 0) {
        hadPending = 1;
        if (spawn.bZoneId == 0xff) {
            g_graphics_context.bClip_enabled = '\0';
            g_graphics_context.bGfx_fill_enabled = '\x01';
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_outline_color = '\0';
            draw_rect_filled(0, 0, 0x140, 200);
            vsync_hook(1);
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            draw_rect_filled(0, 0, 0x140, 200);
        }
        while (*(unsigned short *)&g_gameState.abTeleportRecord[7] != 0) {
            scene_kind = *(unsigned short *)&g_gameState.abTeleportRecord[7];
            *(unsigned short *)&g_gameState.abTeleportRecord[7] = 0;
            townscene_main_loop(scene_kind, *(unsigned short *)&g_gameState.abTeleportRecord[9]);
        }
        if (g_gameState.abTeleportRecord[0] != '\0') {
            spawn = *(PlayerSpawnRecord *)g_gameState.abTeleportRecord;
            g_gameState.abTeleportRecord[0] = '\0';
        }
        if ((spawn.bZoneId != 0xff) &&
            ((((spawn.bZoneId != g_gameState.nZoneId ||
                (spawn.bTileX != g_gameState.nPlayerTileX)) ||
               (spawn.bTileY == g_gameState.nPlayerTileY)) ||
              (spawn.wCameraHeading != g_gameState.wZoneDefaultCameraHeading)))) {
            if (spawn.bZoneId != g_gameState.nZoneId) {
                zone_world_scene_teardown();
                zone_set_plr_pos_rec(&spawn);
                zone_load();
            } else {
                zone_combat_camera_set_world_pos(&spawn);
            }
            dialog_input_wait_with_cooldown(2);
        }
    }
    return hadPending;
}

static void far modalscreen_teleport_dest_sel(MenuPage *page, ImageRecord **asset_tbl,
                                              int hover_city, int sel_city, int cost) {
    int i;
    int x;
    int y;
    char buf[20];
    ImageRecord *sprite;
    MenuEntry *entry;

    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    menupage_draw(page);
    invui_draw_text_aligned_shadow((unsigned char far *)page->pEntries[hover_city - 1].pPrimary_label, 0x3c,
                                   0x2c, 1, 10, 1);
    resblit_sprite(asset_tbl[hover_city - 1], 0x3c - asset_tbl[hover_city - 1]->nWidth / 2, 0x37);
    if (sel_city != 0) {
        invui_draw_text_aligned_shadow((unsigned char far *)page->pEntries[sel_city - 1].pPrimary_label,
                                       0x3c, 0x74, 1, 10, 1);
        resblit_sprite(asset_tbl[sel_city - 1], 0x3c - asset_tbl[sel_city - 1]->nWidth / 2, 0x7f);
        sprintf(buf, "%d sovereigns", cost / 10);
        invui_draw_text_aligned_shadow((unsigned char far *)buf, 0x26, 0xb4, 0, 10, 1);
    }
    i = 0;
    entry = page->pEntries;
    while (i < 12) {
        sprite = asset_tbl[0xf];
        if (hover_city - 1 == i) {
            sprite = asset_tbl[0xd];
        } else {
            if (sel_city - 1 == i) {
                sprite = asset_tbl[0xe];
            } else {
                if (entry->wEnable_gate != 0)
                    goto next;
            }
        }
        x = entry->rect.x + (entry->rect.width - sprite->nWidth) / 2;
        y = entry->rect.y + (entry->rect.height - sprite->nHeight) / 2;
        resblit_sprite(sprite, x, y);
    next:
        i++;
        entry++;
    }
}

int modalscreen_teleport_spell_run(int current_city, long cost_base, int cost_per_unit) {
    unsigned short savedBlend;
    unsigned char far *savedPal;
    unsigned char far *palChunk;
    MenuPage *page;
    MenuEntry *destEntry;
    ImageRecord **assetTbl;
    unsigned short redraw;
    int hoverCity;
    int prevHoverCity;
    int result;
    long cost;
    int abx;
    int err;
    int frame;
    int curX;
    int curY;
    unsigned int action;
    MenuEntry *entry;
    int i;
    int dx, dy, aby;
    int tx, ty, sgnx, sgny, adx, ady, sfx_handle;

    savedBlend = g_nPalBlendMode;
    savedPal = palette_set((unsigned char far *)0);
    redraw = 1;
    hoverCity = 0;
    prevHoverCity = 0;

    if (current_city == 0xc && g_gameState.nChapter == 6 && gstate_event_read(0x1ed4) == 0) {
        dialog_play_record(0x493feL, 0);
        return 0;
    }

    dialog_play_record(0x13d65dL, 0);

    i = 1;
    result = 1;
    for (; i < 0xd; i++) {
        if (i != current_city && gstate_event_read(TOWN_VISITED(i)) != 0)
            result = 0;
    }
    if (result != 0) {
        dialog_play_record(0x13d65fL, 0);
        return 0;
    }

    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage =
        g_graphics_context.wVgaPage2Base;
    resblit_load_pal_or_stream("C42.SCX");
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_fill_enabled = 0;
    g_graphics_context.bGfx_outline_color = 'I';
    draw_rect_filled(0x7c, 0xc, 0xb0, 0xa4);
    g_graphics_context.bGfx_outline_color = '6';
    draw_rect_filled(0x7d, 0xc, 0xaf, 0xa3);
    g_graphics_context.bGfx_outline_color = '=';
    draw_rect_filled(0x7d, 0xd, 0xae, 0xa2);
    g_graphics_context.bGfx_outline_color = 0xd8;
    draw_rect_filled(0x7e, 0xd, 0xad, 0xa1);
    g_graphics_context.bGfx_outline_color = 0x0f;
    draw_line(0x7c, 0xc, 300, 0xb0);
    for (i = 10; i < 0xaa; i++) {
        cga_save_rect_to_buffer(g_pMainScratchBuf, 100, i, 0xac, 1);
        cga_rect_paste_from_buffer(g_pMainScratchBuf, 0x7e, i + 4, 0xac, 1);
    }

    g_pPalQueuedForFlip = palChunk = chunk_load_into_slot("TELEPORT.PAL");
    assetTbl = resblit_load_asset_table("TELEPORT.BMX", 0);
    page = menupage_load("req_tele.dat");
    menupage_begin(page);
    g_graphics_context.bGfx_fill_enabled = 1;
    resblit_sprite(assetTbl[0xc], 0x3c - assetTbl[0xc]->nWidth / 2, 10);
    invui_draw_text_aligned_shadow((unsigned char far *)"From:", 0x3c, 0x23, 1, 0, -2);
    invui_draw_text_aligned_shadow((unsigned char far *)"To:", 0x3c, 0x6b, 1, 0, -2);
    invui_draw_text_aligned_shadow((unsigned char far *)"Cost:", 0x18, 0xb4, 1, 0, -2);

    for (i = 1; i < 0xd; i++) {
        if (i == current_city || gstate_event_read(TOWN_VISITED(i)) == 0)
            page->pEntries[i - 1].wEnable_gate = 1;
    }

    while (result == 0) {
        if (redraw != 0 || hoverCity != prevHoverCity) {
            if (hoverCity != 0) {
                entry = &page->pEntries[current_city - 1];
                destEntry = &page->pEntries[hoverCity - 1];
                abx = abs(entry->rect.x - destEntry->rect.x);
                aby = abs(entry->rect.y - destEntry->rect.y);

                /* Travel cost from the octagonal distance approximation
                 * max + min*3/8. */
                if (abx < aby) {
                    cost = (cost_base + (long)(aby + abx * 3 / 8) * (long)cost_per_unit) * 10;
                } else {
                    cost = (cost_base + (long)(abx + aby * 3 / 8) * (long)cost_per_unit) * 10;
                }
                cost = (cost + 5) / 10;
            } else {
                cost = 0;
            }
            modalscreen_teleport_dest_sel(page, assetTbl, current_city, hoverCity, (int)cost);
            screen_frame_present();
            screen_frame_sync_buffers_rect(0, 200);
        } else {
            screen_frame_present();
        }

        action = menupage_run(page, &redraw);
        entry = menupage_state_0e84();
        prevHoverCity = hoverCity;
        hoverCity = 0;
        if (entry != 0 && 0x80 < entry->wAction_id) {
            hoverCity = entry->wAction_id - 0x80;
        }

        if (action != 0 &&
            (menupage_state_0e7c() == 2 || key_is_down(0x2a) != 0 || key_is_down(0x36) != 0)) {
            g_gameState.nEvtArgCount = (short)(action != 1);
            dialog_play_record(0x13d663L, 0);
            redraw = 1;
        } else {
            if ((int)action > 0x80 && hoverCity != 0) {
                result = hoverCity;
            } else {
                if (action == 1)
                    result = -1;
            }
        }
    }

    if (result == 0xc && g_gameState.nChapter == 6 && gstate_event_read(0x1ed4) == 0) {
        dialog_play_record(0x493fdL, 0);
        result = -1;
    }

    if (0 < result && g_gameState.nParty_gold >= cost) {
        abx = 0;
        err = 0;
        frame = 0;
        curX = page->pEntries[current_city - 1].rect.x;
        curY = page->pEntries[current_city - 1].rect.y;
        tx = page->pEntries[hoverCity - 1].rect.x;
        ty = page->pEntries[hoverCity - 1].rect.y;
        dx = tx - curX;
        dy = ty - curY;
        sgnx = (dx > 0) ? 1 : (dx == 0) ? 0 : -1;
        sgny = (dy > 0) ? 1 : (dy == 0) ? 0 : -1;
        adx = abs(dx);
        ady = abs(dy);
        sfx_handle = audio_sfx_play_n_times(0xc, 0, 0);
        if (adx > ady) {

            i = 0;
            while (i <= adx) {
                int tmp, yoff;
                tmp = (int)(((long)i << 0xf) / (long)adx);
                yoff = (int)(((long)r3d_tbl_sin(tmp) * (long)adx) / 6 >> 0xe);
                err += ady;
                if (err >= adx) {
                    err -= adx;
                    curY += sgny;
                }
                resblit_sprite(assetTbl[frame + 0x10], curX + 3, (curY + 1) - yoff);
                screen_frame_present();
                screen_frame_sync_buffers_rect(0, 200);
                curX += sgnx;
                i++;
                frame++;
                frame = frame % 5;
            }
        } else {

            i = 0;
            while (i <= ady) {
                int tmp, yoff;
                tmp = (int)(((long)i << 0xf) / (long)ady);
                yoff = (int)(((long)r3d_tbl_sin(tmp) * (long)ady) / 6 >> 0xe);
                abx += adx;
                if (abx >= ady) {
                    abx -= ady;
                    curX += sgnx;
                }
                resblit_sprite(assetTbl[frame + 0x10], (curX + 3) - yoff, curY + 1);
                screen_frame_present();
                screen_frame_sync_buffers_rect(0, 200);
                curY += sgny;
                i++;
                frame++;
                frame = frame % 5;
            }
        }
        i = 0;
        do {
            screen_frame_present();
            i++;
        } while (i < 0x78);
        if (sfx_handle != 0)
            audio_sfx_stop(0xc);
    }

    menupage_end(page);
    menupage_free(page);
    free_image_record(assetTbl);
    cache_release(palChunk);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    resblit_load_pal_or_stream("DIALOG.SCX");
    g_nPalBlendMode = savedBlend;
    g_pPalQueuedForFlip = savedPal;
    screen_clear_both_pages();

    if (result > 0) {
        if (g_gameState.nParty_gold < cost) {
            dialog_play_record(0x13d65eL, 0);
            return 0;
        }
        g_gameState.nParty_gold -= cost;
        dialog_play_record(0x13d660L, 0);
        modalscreen_teleport_dat_load(hoverCity - 1);
        return 1;
    } else {
        dialog_play_record(0x13d661L, 0);
        return 0;
    }
}

#define SLOT_PTR(act, id) (&ACTOR_ITEM((act), (id) - 0x80))

void modalscreen_req_inv_run(int kind_or_id, int tax, int qty_mult, int char_slot) {
    unsigned short redraw;
    unsigned int i;
    unsigned int action;
    unsigned char far *palChunk;
    int partySlot;
    Actor far *act_rec;
    unsigned short savedBlend;
    unsigned char far *savedPal;
    register MenuPage *page;
    MenuEntry *entry;
    register int memberSlot;

    (void)kind_or_id;

    redraw = 1;
    partySlot = 1;
    savedBlend = g_nPalBlendMode;
    savedPal = palette_set((unsigned char far *)0);
    g_inventory_screen_mode = 2;
    screen_cursor_show_busy();
    invui_inspect_images_load_once(0);
    itemtbl_load();
    page = menupage_load("req_inv.dat");
    menupage_begin(page);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    resblit_load_pal_or_stream("INVENTOR.SCR");
    dialog_input_wait_with_cooldown(1);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_pPalQueuedForFlip = palChunk = chunk_load_into_slot("INVENTOR.PAL");
    g_nPalBlendMode = 0;
    act_rec = g_gameState.party_members[g_gameState.party_roster[partySlot - 1]].actor_record;

    do {
        do {
            if (redraw != 0) {
                g_gameState.nEvtArgActor0 = g_gameState.party_roster[partySlot - 1];
                cmbinv_combat_encounter_begin(page, act_rec, 0);
                i = 0;
                entry = page->pEntries;
                for (; i < page->wEntry_count; i++, entry++) {
                    if (entry->wAction_id >= 0x80) {
                        ItemRecord far *rec =
                            itemtbl_record_ptr(SLOT_PTR(act_rec, entry->wAction_id));
                        if (rec->wCategory == 4 || rec->wCategory == 1) {
                            entry->wCursor_shape = 1;
                        }
                    }
                }
                invui_render_present_sync(page, act_rec, partySlot, -1);
            }
            screen_frame_present();
            action = menupage_run(page, &redraw);
        } while (action == 0);

        if (action == 2 || action == 3 || action == 4) {
            memberSlot = action - 2 + 1;
            if (memberSlot <= g_gameState.party_count) {
                if (menupage_state_0e7c() == 2 || key_is_down(0x2a) != 0 ||
                    key_is_down(0x36) != 0) {
                    audio_play(0x53);
                    charscreen_info_loop(gstate_party_member_record(memberSlot - 1));
                    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
                    resblit_load_pal_or_stream("INVENTOR.SCR");
                    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                } else if (memberSlot != partySlot) {
                    audio_play(0x53);
                    partySlot = memberSlot;
                    act_rec = g_gameState.party_members[g_gameState.party_roster[partySlot - 1]]
                                  .actor_record;
                    redraw = 1;
                }
            }
        } else if (action >= 0x80) {
            ItemSlot far *slot_ptr;
            if (menupage_state_0e7c() == 2 || key_is_down(0x2a) != 0 || key_is_down(0x36) != 0) {
                ImageRecord *sprite;
                slot_ptr = SLOT_PTR(act_rec, action);
                sprite = invui_item_sprite_select(slot_ptr);
                entry = menupage_state_0e84();
                g_nInvSelItemAnchorX =
                    entry->rect.x + page->rect.x + (entry->rect.width - sprite->nWidth) / 2;
                g_nInvSelItemAnchorY =
                    entry->rect.y + page->rect.y + (entry->rect.height - sprite->nHeight) / 2;
                g_nInvSelItemIconDx = entry->rect.x - g_nInvSelItemAnchorX;
                g_nInvSelItemIconDy = entry->rect.y - g_nInvSelItemAnchorY;
                invinspect_item_flow(SLOT_PTR(act_rec, action), partySlot, page);
                redraw = 1;
            } else {
                ItemRecord far *rec;
                int price;
                slot_ptr = SLOT_PTR(act_rec, action);
                rec = itemtbl_record_ptr(slot_ptr);
                price = (int)((long)(unsigned)rec->nBase_price * qty_mult / 100 + (long)tax * 10);
                g_gameState.nEvtArgItemId = slot_ptr->item_id;
                g_gameState.lEvtArgGoldCost = (long)price;
                if (rec->wCategory == 4 || rec->wCategory == 1) {
                    if ((slot_ptr->flags & 0xe000) == 0 || dialog_play_record(0x13d66f, 0) == 0) {
                        g_gameState.nEvtArgCount = (short)(rec->wCategory == 4);
                        dialog_play_record(0x13d670, 0);

                        if (gstate_event_read(0x104) != 0) {
                            g_gameState.nParty_gold -= g_gameState.lEvtArgGoldCost;
                            slot_ptr->flags &= 0x1fff;

                            slot_ptr->flags |= 0x2000 << (char_slot - 1);
                            audio_sfx_play_n_times(0x3e, 0, 1);
                        }
                    }
                } else {
                    dialog_play_record(0x13d671, 0);
                }
            }
        }
    } while (action != 1);

    cache_release(palChunk);
    g_nPalBlendMode = savedBlend;
    g_pPalQueuedForFlip = savedPal;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    resblit_load_pal_or_stream("Dialog.scx");
    screen_clear_both_pages();
    menupage_end(page);
    menupage_free(page);
    itemtbl_free();
    invui_inspect_image_cleanup();
    g_inventory_screen_mode = 0;
}

#define SLOT_PTR(act, id) (&ACTOR_ITEM((act), (id) - 0x80))

void modalscreen_inventory_request(unsigned int category_mask, int discount_pct) {
    unsigned short redraw;
    unsigned int i;
    unsigned int action;
    int timeFlags;
    unsigned short allowEventDialog;
    unsigned char far *palChunk;
    int party_slot;
    Actor far *act_rec;
    unsigned short savedBlend;
    unsigned char far *savedPal;
    register MenuPage *page;
    MenuEntry *entry;

    redraw = 1;
    timeFlags = 0;
    allowEventDialog = 1;
    party_slot = 1;
    savedBlend = g_nPalBlendMode;
    savedPal = palette_set((unsigned char far *)0);
    g_inventory_screen_mode = 2;
    screen_cursor_show_busy();
    invui_inspect_images_load_once(0);
    itemtbl_load();
    page = menupage_load("req_inv.dat");
    menupage_begin(page);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    resblit_load_pal_or_stream("INVENTOR.SCR");
    dialog_input_wait_with_cooldown(1);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_pPalQueuedForFlip = palChunk = chunk_load_into_slot("INVENTOR.PAL");
    g_nPalBlendMode = 0;
    act_rec = g_gameState.party_members[g_gameState.party_roster[party_slot - 1]].actor_record;

    do {
        do {
            if (redraw != 0) {
                g_gameState.nEvtArgActor0 = g_gameState.party_roster[party_slot - 1];
                cmbinv_combat_encounter_begin(page, act_rec, 0);
                i = 0;
                entry = page->pEntries;
                for (; i < page->wEntry_count; i++, entry++) {
                    if (entry->wAction_id >= 0x80) {
                        ItemRecord far *rec =
                            itemtbl_record_ptr(SLOT_PTR(act_rec, entry->wAction_id));
                        if ((rec->wCategory == 1 && (category_mask & 1)) ||
                            (rec->wCategory == 4 && (category_mask & 2)) ||
                            (rec->wCategory == 2 && (category_mask & 4))) {
                            entry->wCursor_shape = 1;
                        }
                    }
                }
                invui_render_present_sync(page, act_rec, party_slot, -1);
            }
            screen_frame_present();
            action = menupage_run(page, &redraw);
        } while (action == 0);

        {
            if (action == 2 || action == 3 || action == 4) {
                int di = action - 2 + 1;
                if (g_gameState.party_count >= di) {
                    if (menupage_state_0e7c() == 2 || key_is_down(0x2a) != 0 ||
                        key_is_down(0x36) != 0) {
                        audio_play(0x53);
                        charscreen_info_loop(gstate_party_member_record(di - 1));
                        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
                        resblit_load_pal_or_stream("INVENTOR.SCR");
                        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                    } else if (di != party_slot) {
                        audio_play(0x53);
                        party_slot = di;
                        act_rec =
                            g_gameState.party_members[g_gameState.party_roster[party_slot - 1]]
                                .actor_record;
                        redraw = 1;
                    }
                }
            } else if (action >= 0x80) {
                if (menupage_state_0e7c() == 2 || key_is_down(0x2a) != 0 ||
                    key_is_down(0x36) != 0) {
                    ItemSlot far *slot_ptr;
                    ImageRecord *sprite;
                    slot_ptr = SLOT_PTR(act_rec, action);
                    sprite = invui_item_sprite_select(slot_ptr);
                    entry = menupage_state_0e84();
                    g_nInvSelItemAnchorX =
                        entry->rect.x + page->rect.x + (entry->rect.width - sprite->nWidth) / 2;
                    g_nInvSelItemAnchorY =
                        entry->rect.y + page->rect.y + (entry->rect.height - sprite->nHeight) / 2;
                    g_nInvSelItemIconDx = entry->rect.x - g_nInvSelItemAnchorX;
                    g_nInvSelItemIconDy = entry->rect.y - g_nInvSelItemAnchorY;
                    invinspect_item_flow(SLOT_PTR(act_rec, action), party_slot, page);
                    redraw = 1;
                } else {

                    int sfx_id;
                    int sfx_rep;
                    ItemSlot far *slot_ptr;
                    ItemRecord far *rec;
                    int di;

                    di = 0;
                    slot_ptr = SLOT_PTR(act_rec, action);
                    rec = itemtbl_record_ptr(slot_ptr);
                    redraw = 1;
                    g_gameState.nEvtArgCount = rec->wCategory;
                    g_gameState.nEvtArgItemId = slot_ptr->item_id;
                    g_gameState.lEvtArgValue = (unsigned int)(slot_ptr->flags & 0xff80);

                    switch (rec->wCategory) {
                    case 1:
                        if (category_mask & 1) {
                            g_gameState.lEvtArgGoldCost = (long)(unsigned)rec->nBase_price *
                                                          discount_pct *
                                                          (100L - slot_ptr->condition) / 10000L;
                            di = 4;
                            sfx_id = 0x12;
                            sfx_rep = 2;
                        }
                        break;
                    case 4:
                        if (category_mask & 2) {
                            g_gameState.lEvtArgGoldCost = (long)(unsigned)rec->nBase_price *
                                                          discount_pct *
                                                          (100L - slot_ptr->condition) / 10000L;
                            di = 8;
                            sfx_id = 0x14;
                            sfx_rep = 1;
                        }
                        break;
                    case 2:
                        if (category_mask & 4) {
                            ItemRecord far *rec2;
                            rec2 =
                                itemtbl_record_ptr_by_id(slot_ptr->item_id == 0x20 ? 0x4c : 0x4d);
                            g_gameState.lEvtArgGoldCost = (long)(unsigned)rec2->nBase_price << 1;
                            di = 2;
                            sfx_id = 0x16;
                            sfx_rep = 0;
                        }
                        break;
                    }

                    if (di != 0) {
                        timeFlags |= di;
                        if (slot_ptr->condition != 100) {
                            dialog_play_record(0x1b7763, 0);
                            if (gstate_event_read(0x104) != 0) {
                                g_gameState.nParty_gold -= g_gameState.lEvtArgGoldCost;
                                slot_ptr->flags &= ~0x20;
                                slot_ptr->condition = 100;
                                audio_sfx_play_n_times(sfx_id, sfx_rep, 1);
                            }
                        } else {
                            dialog_play_record(0x1b7765, 0);
                        }
                    } else {
                        dialog_play_record(0x1b7764, 0);
                    }
                }
            }
        }
    } while (action != 1);

    while (timeFlags-- != 0) {
        if (gstate_advance_time(0x708, allowEventDialog, 1, 1, 0) != 0) {
            allowEventDialog = 0;
        }
    }

    cache_release(palChunk);
    g_nPalBlendMode = savedBlend;
    g_pPalQueuedForFlip = savedPal;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    resblit_load_pal_or_stream("Dialog.scx");
    screen_clear_both_pages();
    menupage_end(page);
    menupage_free(page);
    itemtbl_free();
    invui_inspect_image_cleanup();
    g_inventory_screen_mode = 0;
}

static void modalscreen_inv_draw_gold_amount(void) {
    char szAmount[40];
    register int x;
    register int y;

    x = 139;
    y = 89;
    g_graphics_context.bClip_enabled = 0;
    g_graphics_context.bText_fg_color = 0;
    g_graphics_context.bText_style_flags = 1;
    font_draw_text_ds("Party Gold:", x, y);
    x += 60;
    gstate_format_money(szAmount, g_gameState.nParty_gold, 1);
    font_draw_text_ds(szAmount, x, y);
}

void modalscreen_rest_until_time(Actor far *pActor) {
    int done;
    int firstLoop;
    unsigned long saved_time;
    unsigned short saved_blend;
    unsigned char far *saved_pal;
    unsigned char far *pal_chunk;
    ActorSubrecord far *sub;
    unsigned int i;

    done = 0;
    firstLoop = 1;
    saved_time = g_gameState.game_time;
    saved_blend = g_nPalBlendMode;
    saved_pal = palette_set((unsigned char far *)0);
    if (g_pPalQueuedForFlip != 0) {
        saved_pal = g_pPalQueuedForFlip;
        g_pPalQueuedForFlip = 0;
    }
    sub = actorrec_get_subrecord(pActor, SUBREC_EVENT_STATE);
    screen_cursor_set_shape(0);
    palette_fade_out(0, 0x100, 8, 1);
    palette_screen_clear_black();
    g_pPalQueuedForFlip = pal_chunk = chunk_load_into_slot("INVENTOR.PAL");
    g_nPalBlendMode = 0;
    screen_cursor_hide();
    screen_frame_present();
    palette_set_scaled(0, 0x100, 0, 0);
    screen_clear_both_pages();
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    encamp_load();
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    encamp_restore_screen_background();

    g_graphics_context.bGfx_outline_color = 0x91;
    draw_line(0xc, 10, 0xc, 0x6f);
    draw_line(0xc, 0x6f, 0x133, 0x6f);
    g_graphics_context.bGfx_outline_color = 0x1c;
    draw_line(0xb, 9, 0xb, 0x70);
    draw_line(0xb, 0x70, 0x134, 0x70);
    g_graphics_context.bGfx_outline_color = 0x15;
    draw_line(0xc, 10, 0x133, 10);
    draw_line(0x133, 10, 0x133, 0x6f);
    g_graphics_context.bGfx_outline_color = 0x10;
    draw_line(0xb, 9, 0x134, 9);
    draw_line(0x134, 9, 0x134, 0x70);
    putpixel(0xc, 10, 0x93);
    putpixel(0xb, 9, 0x93);
    putpixel(0x133, 0x6f, 0x93);
    putpixel(0x134, 0x70, 0x93);
    screen_clear_back_buffer();

    while (done == 0) {
        done = (unsigned long)(g_gameState.game_time % 0xa8c0) / 0x708 * 0x708;
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
        gfx_present_dispatch(0, 0, 0x140, 200);
        encamp_draw_party_stats();
        encamp_draw_clock_hand(done);
        encamp_proj_trail_emit_facing(0, 1, sub->event_state.bRest_target_hour, done, done, done);
        modalscreen_inv_draw_gold_amount();
        screen_frame_present();
        screen_frame_sync_buffers_rect(0, 200);
        if (firstLoop) {
            palette_fade_in(0, 0x100, 4, 1);
        }
        g_gameState.lEvtArgGoldCost = (long)(int)sub->event_state.bRest_gold_cost * 10;
        g_gameState.lEvtArgValue = (long)(int)sub->event_state.bRest_target_hour;
        g_gameState.nEvtArgCount = (short)!firstLoop;
        if (dialog_play_record(0x13d672, 0) == 0) {
            g_dialog_in_scene = 0;
            gstate_advance_half_hours(1, 100, 0x85);
            do {
                for (i = 0; i < 2; i++) {
                    done = (int)((unsigned long)(g_gameState.game_time % 0xa8c0) / 0x708 * 0x708) +
                           (int)((long)(i * 0x708L) / 2);
                    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
                    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                    gfx_present_dispatch(0xd, 0xb, 0x125, 99);
                    encamp_draw_clock_hand(done);
                    encamp_draw_party_stats();
                    encamp_proj_trail_emit_facing(0, 1, sub->event_state.bRest_target_hour, done,
                                                  done, done);
                    modalscreen_inv_draw_gold_amount();
                    screen_frame_present();
                    screen_frame_sync_buffers_rect(10, 0x6e);
                }
                gstate_advance_half_hours(1, 100, 0x85);
                if (g_gameState.game_time - saved_time >= 0x5b68) {
                    for (i = 0; i < (unsigned)(int)g_gameState.party_count; i++) {
                        stat_combatant_apply_delta(gstate_party_member_record(i), 0, -100);
                    }
                }
            } while ((unsigned long)(g_gameState.game_time % 0xa8c0) / 0x708 !=
                     sub->event_state.bRest_target_hour);
            firstLoop = 0;
            g_gameState.nParty_gold -= (int)(sub->event_state.bRest_gold_cost * 10);
            i = 0;
            done = 1;
            for (; i < (unsigned)(int)g_gameState.party_count; i++) {
                if (stat_actor_get(gstate_party_member_record(i), 0x10, 0) !=
                    stat_actor_get(gstate_party_member_record(i), 0x10, 1)) {
                    done = 0;
                }
            }
            g_dialog_in_scene = 1;
        } else {
            done = 1;
        }
    }

    cache_release(pal_chunk);
    encamp_teardown();
    palette_fade_out(0, 0x100, 4, 1);
    palette_screen_clear_black();
    screen_cursor_hide();
    g_nPalBlendMode = saved_blend;
    g_pPalQueuedForFlip = saved_pal;
    screen_frame_present();
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    resblit_load_pal_or_stream("DIALOG.SCX");
}
