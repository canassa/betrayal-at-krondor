#include <mem.h>
#include <string.h>

#include "structs.h"
#include "globals.h"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/SYS/RAND.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/INVENTOR.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/CHAR/CHARSCRN.H"
#include "SRC/SCREENS/ITEMUSE.H"
#include "SRC/SCREENS/INVINSP.H"
#include "SRC/WORLD/ACTOR/ACTSPAWN.H"
#include "SRC/SCREENS/SHOP.H"
#include "SRC/WORLD/ACTOR/ACTORREC.H"
#include "SRC/SCREENS/PICKLOCK.H"


unsigned short g_inventory_screen_mode = 0x0000;
unsigned char g_bIsRestEncounter = 0x00;
Actor far *g_other_inventory_actor = {0};
Actor far *g_pDroppedItemActor = {0};
MenuPage *g_pInventoryMenuPage = {0};
ItemSlot far *g_pStackHeadroomSlot = {0};

void cmbinv_combat_encounter_begin(MenuPage *page, Actor far *actor, int pageBase) {
    int i;
    int col;
    int row;
    int span;
    int maxX;
    int maxY;
    ActorSubrecord far *subrec;
    char grid[28];
    MenuEntry *entry;
    ushort category;
    int found;

    maxX = 0;
    maxY = 0;
    subrec = actorrec_get_subrecord(actor, SUBREC_EVENT_STATE);
    page->wEntry_count = 7;
    cmbinv_combat_sort_initiative(actor);
    memset(grid, 0, 0x1c);
    g_bIsRestEncounter = 0;

    if (subrec != (ActorSubrecord far *)0) {

        g_bIsRestEncounter = subrec->event_state.bRest_gold_cost != 0;
        for (i = 0; i < 6 && i + pageBase < (int)(unsigned)actor->itemCount; i++) {
            if (itemtbl_record_ptr(&ACTOR_ITEM(actor, i + pageBase))->wDamage_class_threshold <=
                g_gameState.nChapter) {
                entry = &page->pEntries[page->wEntry_count];
                entry->wAction_id = page->wEntry_count + pageBase + 0x79;
                entry->wSprite_base = ACTOR_ITEM(actor, i + pageBase).item_id + 1;
                entry->rect.x = (i % 3) * 0x62 + 0xd;
                entry->rect.y = 2 < i ? 0x47 : 0xb;
                entry->rect.width = 0x62;
                entry->rect.height = (2 < i) + 0x3c;
                page->wEntry_count++;
            }
        }
    } else {

        if (actor->bResidence == RES_PARTY_SLOT || g_bInventoryShopMode != 0) {

            for (i = 0; i < (int)(unsigned)actor->itemCount && !g_bInventoryShopMode; i++) {
                span = 0;
                if ((ACTOR_ITEM(actor, i).flags & 0x40) != 0) {
                    category = itemtbl_record_ptr(&ACTOR_ITEM(actor, i))->wCategory;
                    if (category == 4) {
                        col = 0;
                        row = 2;
                        span = 4;
                    } else if (category == 3) {
                        col = 0;
                        row = 0;
                        span = 4;
                    } else if (category == 2) {
                        col = 0;
                        row = 1;
                        span = 2;
                    } else if (category == 1) {
                        col = 0;
                        row = 0;
                        span = 2;
                    }
                    if (span != 0) {
                        entry = &page->pEntries[page->wEntry_count];
                        entry->wAction_id = page->wEntry_count + 0x79;
                        entry->wSprite_base = ACTOR_ITEM(actor, i).item_id + 1;
                        entry->rect.x = col * 0x28 + 0xe;
                        entry->rect.y = row * 0x1e + 0xc;
                        entry->rect.width = (1 < span) * 0x28 + 0x28;
                        entry->rect.height = (2 < span) * 0x1e + 0x1e;
                        entry->wCursor_shape = 0;
                        page->wEntry_count++;
                    }
                }
            }

            for (col = 0; col < 2; col++) {
                for (row = 0; row < 4; row++) {
                    grid[col * 4 + row] = 1;
                }
            }
        }

        for (i = 0; i < (int)(unsigned)actor->itemCount; i++) {
            if (actor->bResidence != RES_PARTY_SLOT || (ACTOR_ITEM(actor, i).flags & 0x40) == 0) {
                col = found = 0;
                for (; !found && col < 7; col++) {
                    for (row = 0; !found && row < 4; row++) {
                        if (grid[col * 4 + row] == 0) {
                            grid[col * 4 + row] = 1;
                            span = cmbinv_item_field_32_or_1(&ACTOR_ITEM(actor, i));
                            if (1 < span) {
                                grid[col * 4 + row + 4] = 1;
                                if (2 < span) {
                                    grid[col * 4 + row + 1] = grid[col * 4 + row + 5] = 1;
                                }
                            }
                            entry = &page->pEntries[page->wEntry_count];
                            entry->wAction_id = page->wEntry_count + 0x79;
                            entry->wSprite_base = ACTOR_ITEM(actor, i).item_id + 1;
                            entry->rect.x = col * 0x28 + 0xe;
                            entry->rect.y = row * 0x1e + 0xc;
                            entry->rect.width = (1 < span) * 0x28 + 0x28;
                            entry->rect.height = (2 < span) * 0x1e + 0x1e;
                            entry->wCursor_shape = 0;
                            found = 1;
                            page->wEntry_count++;
                            if (actor->bResidence == RES_PARTY_SLOT || g_bInventoryShopMode != 0) {
                                entry->rect.x += 0xc;
                            }
                            if (maxX < entry->rect.x + entry->rect.width) {
                                maxX = entry->rect.x + entry->rect.width;
                            }
                            if (maxY < entry->rect.y + entry->rect.height) {
                                maxY = entry->rect.y + entry->rect.height;
                            }
                        }
                    }
                }
            }
        }

        if (actor->bResidence != RES_PARTY_SLOT && !g_bInventoryShopMode) {

            maxX = (0x133 - maxX) / 2;
            maxY = (0x84 - maxY) / 2;
            for (i = 7; i < (int)page->wEntry_count; i++) {
                page->pEntries[i].rect.x += maxX;
                page->pEntries[i].rect.y += maxY;
            }
        }

        if (g_bInventoryShopMode != 0) {
            entry = &page->pEntries[page->wEntry_count++];
            entry->wAction_id = 0x7f;
            entry->rect.x = 0xd;
            entry->rect.y = 0xb;
            entry->rect.width = 0x52;
            entry->rect.height = 0x79;
            entry->bActive_flag = 0;
            entry->wSprite_base = 0;
            entry->wCursor_shape = 1;
        }
    }
}

int cmbinv_inventory_screen_run(Actor far *actor, int idx, int flag) {

    ushort needRedraw;
    int fadeIn;
    int selSlot;
    int page;
    int result;
    ushort savedEntryCount;
    ushort savedBlendMode;
    byte far *savedInstalledPal;
    byte far *palBuf;

    int memberIdx;
    uint action;
    int drag;

    memberIdx = idx;
    needRedraw = 1;
    fadeIn = 1;
    selSlot = -1;
    page = 0;
    result = -1;
    savedBlendMode = g_nPalBlendMode;
    g_inventory_screen_mode = 1;
    g_pPalQueuedForFlip = (byte far *)0;
    g_nPalBlendMode = 0;
    screen_cursor_show_busy();
    invui_inspect_images_load_once((uint)g_bInventoryShopMode);
    if (g_wInCombatMode == 0) {
        itemtbl_load();
    }
    if (actor != (Actor far *)0) {
        if (actorrec_get_subrecord(actor, SUBREC_EVENT_STATE) != (ActorSubrecord far *)0) {
            shop_items_compute_actor_prices(actor);
        }
    }
    g_pInventoryMenuPage = menupage_load("req_inv.dat");
    menupage_begin(g_pInventoryMenuPage);
    savedEntryCount = g_pInventoryMenuPage->wEntry_count;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    resblit_load_pal_or_stream("INVENTOR.SCR");
    dialog_input_wait_with_cooldown(1);
    palette_fade_out(0, 0x100, 8, 1);
    palette_screen_clear_black();
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    savedInstalledPal = palette_set((uchar far *)0);
    g_pPalQueuedForFlip = palBuf = chunk_load_into_slot("INVENTOR.PAL");
    g_nPalBlendMode = 0;
    screen_cursor_hide();
    screen_frame_present();
    palette_set_scaled(0, 0x100, 0, 0);

    if ((memberIdx != 0) && !g_bInventoryShopMode) {
        actor = gstate_party_member_record(memberIdx - 1)->actor_record;
    }
    cmbinv_consolidate_stacks(actor);
    dialog_viewport_clip_point(-1, -1);

    g_other_inventory_actor = (actor->bResidence == RES_PARTY_SLOT) ? (Actor far *)0 : actor;
    g_pDroppedItemActor = (Actor far *)0;

    {
        ActorSubrec08_HotspotAction far *pSub08 =
            (ActorSubrec08_HotspotAction far *)actorrec_get_subrecord(actor, SUBREC_HOTSPOT);
        if ((pSub08 != (ActorSubrec08_HotspotAction far *)0) &&
            (pSub08->wGame_state_event_id != 0)) {
            gstate_event_write(pSub08->wGame_state_event_id, 1);
        }
    }

    for (;;) {

        if (needRedraw != 0) {
            if (memberIdx != 0) {
                g_gameState.nEvtArgActor0 =
                    (short)(signed char)((char *)&g_gameState.party_count)[memberIdx];
                stat_actor_recalc_equip_bonuses(
                    &g_gameState.party_members[g_gameState.nEvtArgActor0]);
            } else {

                g_gameState.nEvtArgActor0 =
                    (short)(signed char)g_gameState.party_roster[RND(g_gameState.party_count)];
            }
            cmbinv_combat_encounter_begin(g_pInventoryMenuPage, actor, page * 6);
            invui_render_present_sync(g_pInventoryMenuPage, actor, memberIdx, selSlot);
        }
        screen_frame_present();
        if (fadeIn != 0) {
            palette_fade_in(0, 0x100, 8, 1);
        }

        action = menupage_run(g_pInventoryMenuPage, &needRedraw);
        fadeIn = 0;
        if ((drag = invui_handle_item_drag(g_pInventoryMenuPage, actor, memberIdx, &selSlot)) !=
            0) {
            needRedraw = 1;
            if (drag == -2) {
                action = 0x16;
            } else if (drag < 0) {
                if (g_pPicklockOwnerActor != (Actor far *)0) {

                    actor = g_pPicklockOwnerActor;
                    g_other_inventory_actor = g_pPicklockOwnerActor;
                    g_bInventoryShopMode = 0;
                    needRedraw = 1;
                    memberIdx = 0;
                } else {
                    g_bInventoryShopMode = 0;
                    action = 1;
                }
            }
        }

        if ((action != 0) && (menupage_state_0e7c() == 2)) {
            needRedraw = 1;
            if (action >= 0x80) {

                invinspect_item_flow(
                    ACTOR_ITEMS(actor) + (action - 0x80), memberIdx,
                    (actorrec_get_subrecord(actor, SUBREC_EVENT_STATE) == (ActorSubrecord far *)0)
                        ? g_pInventoryMenuPage
                        : (MenuPage *)0);
            } else {
                if (((action < 2) || (4 < action)) && (action != 0x7f)) {
                    if (action == 0x20) {

                        if ((short)(g_gameState.nEvtArgCount = g_inventory_actor_kind) >= 0) {
                            dialog_play_record(0x1b7751L, 0);
                        }
                        action = 0;
                    } else if (action != 0x22) {

                        g_gameState.nEvtArgCount = menupage_state_0e80()->wSprite_base;
                        dialog_play_record(0x1b775aL, 0);
                        action = 0;
                    }
                }
            }
        }

        if (action != 0) {
            if (((action == 2) || (action == 3) || (action == 4)) && !g_bInventoryShopMode) {
                int target = (int)(action - 2) + 1;
                selSlot = -1;
                if (target <= g_gameState.party_count) {
                    if ((menupage_state_0e7c() == 2) || (key_is_down(0x2a) != 0) ||
                        (key_is_down(0x36) != 0)) {

                        audio_play(0x53);
                        charscreen_info_loop(gstate_party_member_record(target - 1));
                        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
                        resblit_load_pal_or_stream("INVENTOR.SCR");
                        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                    } else if ((target != memberIdx) && (g_wInCombatMode == 0)) {

                        audio_play(0x53);
                        memberIdx = target;
                        actor = gstate_party_member_record(memberIdx - 1)->actor_record;
                        cmbinv_consolidate_stacks(actor);
                        needRedraw = 1;
                    }
                }
            } else if (action == 0x22) {

                g_gameState.lEvtArgGoldCost = g_gameState.nParty_gold;
                dialog_play_record(0x1b7762L, 0);
            }

            if (actor->bResidence == RES_PARTY_SLOT) {
                if (action == 0x16) {
                    if (selSlot >= 0) {
                        ItemSlot far *slot = ACTOR_ITEMS(actor) + selSlot;
                        ItemRecord far *pRec;
                        pRec = itemtbl_record_ptr(slot);
                        if ((pRec->wCategory == 9) || (pRec->wCategory == 8) ||
                            (pRec->wCategory == 0xc)) {
                            dialog_play_record(0x1b774aL, 0);
                        } else {
                            result = itemuse_dispatch_on_target(actor, slot, (ItemSlot far *)0,
                                                                memberIdx);
                        }
                    }
                    selSlot = -1;
                    needRedraw = 1;
                }
                if (action == 0x20) {
                    if (selSlot >= 0) {
                        if (cmbinv_actor_transfer_item(g_other_inventory_actor, actor,
                                                       ACTOR_ITEMS(actor) + selSlot) == 0) {

                            g_gameState.nEvtArgCount =
                                (unsigned char)g_other_inventory_actor->bResidence;
                            dialog_play_record(0x1b7748L, 0);
                        }
                    } else {

                        if (g_other_inventory_actor != (Actor far *)0) {
                            memberIdx = 0;
                            actor = g_other_inventory_actor;
                        } else {
                            memberIdx = 0;
                            actor = g_gameState.shared_inventory;
                        }
                    }
                    selSlot = -1;
                    needRedraw = 1;
                }
            }

            if (g_bInventoryShopMode != 0) {
                if (action == 0x16) {
                    if (selSlot >= 0) {
                        itemuse_dispatch_on_target(actor, ACTOR_ITEMS(actor) + selSlot,
                                                   (ItemSlot far *)0, memberIdx);
                    }
                    selSlot = -1;
                    needRedraw = 1;
                } else if (action == 0x7f) {
                    picklock_inv_info_query_disp();
                } else if ((action == 2) || (action == 3) || (action == 4)) {
                    int target = (int)(action - 2) + 1;
                    selSlot = -1;
                    needRedraw = 1;
                    if (target <= g_gameState.party_count) {
                        if ((menupage_state_0e7c() == 2) || (key_is_down(0x2a) != 0) ||
                            (key_is_down(0x36) != 0)) {
                            charscreen_info_loop(gstate_party_member_record(target - 1));
                            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
                            resblit_load_pal_or_stream("INVENTOR.SCR");
                            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                        } else {
                            memberIdx = target;
                        }
                    }
                }
            }

            if ((actorrec_get_subrecord(actor, SUBREC_EVENT_STATE) != (ActorSubrecord far *)0) &&
                (action == 0x32)) {
                needRedraw = 1;
                selSlot = -1;
                if (key_is_down(0x2a) != 0) {
                    page -= (0 < page);
                } else if (key_is_down(0x36) != 0) {
                    page = 0;
                } else {
                    page++;
                }
                if (((int)(uint)actor->itemCount <= page * 6) ||
                    (g_gameState.nChapter <
                     itemtbl_record_ptr(ACTOR_ITEMS(actor) + page * 6)->wDamage_class_threshold)) {
                    page = 0;
                }
            }

            if ((action != 1) && (result < 0) && !g_gameState.bCombatExitRequest) {
                continue;
            }
            cache_release(palBuf);
            g_nPalBlendMode = savedBlendMode;
            g_pPalQueuedForFlip = savedInstalledPal;
            g_pInventoryMenuPage->wEntry_count = savedEntryCount;
            menupage_end(g_pInventoryMenuPage);
            menupage_free(g_pInventoryMenuPage);
            if (g_pDroppedItemActor != (Actor far *)0) {
                actorspawn_destroy_and_persist(g_pDroppedItemActor);
            }
            g_other_inventory_actor = g_pDroppedItemActor = (Actor far *)0;
            if (g_wInCombatMode == 0) {
                itemtbl_free();
            }
            invui_inspect_image_cleanup();
            g_pInventoryMenuPage = (MenuPage *)0;
            if ((g_wInCombatMode == 0) && (g_dialog_in_scene == 0) && (result == 0x66)) {
                screen_render_main_frame(0);
                itemuse_cam_vert_raise_anim(0x1194L, 0x23);
                g_nSceneReloadPending = 0;
            } else {
                g_nSceneReloadPending = 1;
                g_nExploreReloadPending = 1;
            }
            g_inventory_screen_mode = 0;
            return result;
        }
    }
}

int cmbinv_item_field_32_or_1(ItemSlot far *slot) {
    ItemRecord far *rec;

    rec = itemtbl_record_ptr(slot);
    return rec->wDefault_qty_or_1 != 0 ? rec->wDefault_qty_or_1 : 1;
}

static int cmbinv_item_compare(ItemSlot far *a, ItemSlot far *b, int sort_mode,
                               int use_equipped_order) {
    ItemRecord far *ra;
    ItemRecord far *rb;
    int cat_a;
    int cat_b;
    int qty_a;
    int qty_b;
    int avail_a;
    int avail_b;
    int bit_a;
    int bit_b;

    ra = itemtbl_record_ptr(a);
    rb = itemtbl_record_ptr(b);

    cat_a = (a->flags & 0x40) ? ra->wCategory : 0;
    cat_b = (b->flags & 0x40) ? rb->wCategory : 0;

    qty_a = cmbinv_item_field_32_or_1(a);
    qty_b = cmbinv_item_field_32_or_1(b);

    avail_a = ra->wDamage_class_threshold <= g_gameState.nChapter;
    avail_b = rb->wDamage_class_threshold <= g_gameState.nChapter;

    bit_a = a->flags & 2;
    bit_b = b->flags & 2;

    if (sort_mode == 0) {
        if (use_equipped_order != 0) {
            if (cat_a < cat_b)
                return 1;
            if (cat_a > cat_b)
                return 0;
        }
        if (qty_a < qty_b)
            return 1;
        if (qty_a > qty_b)
            return 0;
    } else {
        if (avail_a < avail_b)
            return 1;
        if (avail_a > avail_b)
            return 0;
        if (bit_a < bit_b)
            return 0;
        if (bit_a > bit_b)
            return 1;
    }

    if (a->item_id > b->item_id)
        return 1;
    if (a->item_id < b->item_id)
        return 0;
    if (sort_mode == 0 && (ra->wFlags & 0x1000))
        return 0;
    if (a->condition > b->condition)
        return 1;
    return 0;
}

void cmbinv_combat_sort_initiative(Actor far *actor) {
    int sort_mode;
    ItemSlot far *a;
    ItemSlot far *b;
    ItemSlot tmp;
    int did_swap;
    int i;

    sort_mode = actorrec_get_subrecord(actor, SUBREC_EVENT_STATE) != 0;

    do {
        i = did_swap = 0;
        for (; i < (int)(actor->itemCount - 1); i++) {
            a = ACTOR_ITEMS(actor) + i;
            b = a + 1;
            if (cmbinv_item_compare(a, b, sort_mode, actor->bResidence == RES_PARTY_SLOT) != 0) {
                did_swap = 1;
                tmp = *a;
                *a = *b;
                *b = tmp;
            }
        }
    } while (did_swap);
}

void cmbinv_consolidate_stacks(Actor far *actor) {
    ItemSlot far *slotA;
    ItemSlot far *slotB;
    ItemRecord far *rec;
    int done;
    int i;
    unsigned int sum;
    unsigned int bMax;

    do {
        done = 1;
        cmbinv_combat_sort_initiative(actor);
        actor->dirty_flag = 1;
        for (i = 1; (int)(unsigned int)actor->itemCount > i; i++) {
            slotA = ACTOR_ITEMS(actor) + (i - 1);
            slotB = slotA + 1;
            rec = itemtbl_record_ptr(slotA);
            if (slotA->item_id != slotB->item_id)
                continue;
            if (!(rec->wFlags & 0x800))
                continue;
            if (slotB->condition >= rec->bMax_stack)
                continue;
            if (slotA->condition < rec->bMax_stack) {
                sum = (unsigned int)slotA->condition + (unsigned int)slotB->condition;
                bMax = (unsigned int)rec->bMax_stack;
                done = 0;
                if ((int)sum <= (int)bMax) {
                    slotA->condition = (unsigned char)sum;
                    *slotB = *(ACTOR_ITEMS(actor) +
                               (unsigned int)(actor->itemCount = actor->itemCount + 0xff));
                    continue;
                }
                slotA->condition = (unsigned char)sum - (unsigned char)bMax;
                slotB->condition = (unsigned char)bMax;
            }
        }
    } while (!done);
}

ItemSlot far *cmbinv_find_equipped_in_category(Actor far *actor, int item_category) {
    int i;
    ItemSlot far *slot;

    i = 0;
    slot = ACTOR_ITEMS(actor);
    for (; i < (int)(unsigned char)actor->itemCount; i++, slot++) {
        if ((slot->flags & 0x40) != 0 && itemtbl_record_ptr(slot)->wCategory == item_category) {
            return slot;
        }
    }
    return (ItemSlot far *)0;
}

static int cmbinv_has_space_for_item(Actor far *actor, ItemSlot far *item) {
    int itemSize;
    int budget;
    int total;
    int r;
    int i;

    itemSize = cmbinv_item_field_32_or_1(item);

    budget = (actor->bResidence == RES_PARTY_SLOT) ? 0x14 : 0x1c;

    if (actor->itemCount == actor->itemCapacity) {
        return 0;
    }

    total = (itemSize > 1) ? itemSize : 0;
    for (i = 0; i < (int)actor->itemCount; i++) {
        if (((actor->bResidence != RES_PARTY_SLOT) || ((ACTOR_ITEM(actor, i).flags & 0x40) == 0)) &&
            ((r = cmbinv_item_field_32_or_1(ACTOR_ITEMS(actor) + i)) != 1)) {
            total += r;
        }
    }

    if (total + 4 > budget) {
        return 0;
    }

    total += (itemSize == 1);
    for (i = 0; i < (int)actor->itemCount; i++) {
        if (((actor->bResidence != RES_PARTY_SLOT) || ((ACTOR_ITEM(actor, i).flags & 0x40) == 0)) &&
            ((r = cmbinv_item_field_32_or_1(ACTOR_ITEMS(actor) + i)) <= 1)) {
            total += r;
        }
    }

    return total <= budget;
}

static int cmbinv_actor_can_stack_item(Actor far *actor, ItemSlot far *item) {
    ItemSlot far *slot;
    ItemRecord far *rec;
    int i;

    rec = itemtbl_record_ptr(item);
    if (rec->wFlags & 0x800) {
        if (actor->itemCount != actor->itemCapacity) {
            i = 0;
            slot = ACTOR_ITEMS(actor);
            for (; i < actor->itemCount; i++, slot++) {
                if (slot->item_id == item->item_id &&
                    slot->condition + item->condition <= rec->bMax_stack) {
                    return 1;
                }
            }
        }
    }
    return 0;
}

static int cmbinv_actor_find_stack_headroom(Actor far *actor, ItemSlot far *item) {
    ItemSlot far *slot;
    ItemRecord far *rec;
    int i;

    rec = itemtbl_record_ptr(item);
    g_pStackHeadroomSlot = 0;
    if (!(rec->wFlags & 0x8800)) {
        return 0;
    }
    i = 0;
    slot = ACTOR_ITEMS(actor);
    for (; i < actor->itemCount; i++, slot++) {
        if (slot->item_id == item->item_id && slot->condition < rec->bMax_stack) {
            g_pStackHeadroomSlot = slot;
            return rec->bMax_stack - slot->condition;
        }
    }
    return 0;
}

static int cmbinv_actor_can_auto_equip(Actor far *actor, ItemSlot far *item) {
    int slot;
    ItemRecord far *rec;

    rec = itemtbl_record_ptr(item);
    if (actor->bResidence != RES_PARTY_SLOT) {
        return 0;
    }
    slot = gstate_find_party_slot((CombatActor *)((char *)&g_gameState + 0x18 +
                                                  actor->loc.party_slot.wSlot_id * 0x5f)) +
           1;
    return cmbinv_member_can_equip_cat(slot, item) != 0 &&
           cmbinv_find_equipped_in_category(actor, rec->wCategory) == 0;
}

int cmbinv_actor_classify_pickup(Actor far *actor, ItemSlot far *item) {
    if (cmbinv_actor_can_auto_equip(actor, item))
        return 3;
    if (cmbinv_has_space_for_item(actor, item))
        return 1;
    cmbinv_consolidate_stacks(actor);
    if (cmbinv_has_space_for_item(actor, item))
        return 1;
    if (cmbinv_actor_can_stack_item(actor, item))
        return 2;
    return 0;
}

void cmbinv_actor_inv_remove_item(Actor far *actor, ItemSlot far *item_slot) {
    int i;

    for (i = 0; i < actor->itemCount; i++) {
        if (_fmemcmp(ACTOR_ITEMS(actor) + i, item_slot, 4) == 0) {
            actor->dirty_flag = 1;
            ACTOR_ITEM(actor, i) = ACTOR_ITEM(actor, --actor->itemCount);
            return;
        }
    }
}

static void cmbinv_combat_op_noop(Actor far *src, ItemSlot far *item) {
    (void)src;
    (void)item;
}

int cmbinv_actor_transfer_item(Actor far *src, Actor far *dst, ItemSlot far *item) {
    ItemRecord far *rec;
    ItemSlot savedItem;
    ItemSlot equipTmp;
    ItemSlot far *equippedSlot;
    int pickupResult;

    rec = itemtbl_record_ptr(item);
    savedItem = *item;
    if (item->flags & 0x40) {
        if (dst->bResidence == RES_PARTY_SLOT) {
            if (rec->wCategory == 1 || rec->wCategory == 3) {
                equipTmp = *item;
                if (src->bResidence != RES_PARTY_SLOT ||
                    !(equippedSlot = cmbinv_find_equipped_in_category(src, rec->wCategory))) {
                    dialog_play_record(0x1b774eL, 0);
                    return -1;
                }
                *item = *equippedSlot;
                *equippedSlot = equipTmp;
                return 1;
            }
        }
    }
    if (item->item_id == '5' || item->item_id == '6') {
        if (item->item_id == '5') {
            g_gameState.nParty_gold += (long)(int)(unsigned int)item->condition * 10;
        } else {
            g_gameState.nParty_gold += (long)(unsigned char)item->condition;
        }
        if (dst == (Actor far *)0L)
            return 1;
        cmbinv_actor_inv_remove_item(dst, item);
        return 1;
    }
    if (src == (Actor far *)0L) {
        return cmbinv_actor_drop_item_at_pos(dst, item);
    }
    if (actorrec_get_subrecord(dst, SUBREC_EVENT_STATE) != (ActorSubrecord far *)0L) {
        return shop_npc_transaction(dst, src, item) != 0 ? 1 : -1;
    }
    if (actorrec_get_subrecord(src, SUBREC_EVENT_STATE) != (ActorSubrecord far *)0L) {
        return shop_sell_item(src, dst, item) != 0 ? 1 : -1;
    }
    cmbinv_combat_op_noop(src, item);
    pickupResult = cmbinv_actor_pickup_item(src, dst, item);
    if (pickupResult != 1) {
        return pickupResult;
    }
    if (src->bResidence == RES_PARTY_SLOT) {
        if (itemtbl_record_ptr((ItemSlot far *)&savedItem)->wCategory == 0x17) {
            int slot;
            slot = src->loc.party_slot.wSlot_id - 1;
            if (g_gameState.abActorStatusRanks[slot][5] != 0) {
                gstate_member_consume_rations(slot, 1);
            }
        }
    }
    return pickupResult;
}

static void cmbinv_recompute_has_weapon_flag(Actor far *actor) {
    ItemSlot far *slot;
    int i;

    actor->flags &= 0xbf;
    actor->dirty_flag = 1;
    i = 0;
    slot = ACTOR_ITEMS(actor);
    for (; i < actor->itemCount; i++, slot++) {
        if (itemtbl_record_ptr(slot)->wFlags & 2) {
            actor->flags |= 0x40;
        }
    }
}

int far cmbinv_pty_distribute_item_stack(Actor far *src, ItemSlot far *item) {
    int assigned;
    unsigned int remaining;
    Actor far *recipient;
    ItemSlot itemCopy;
    int recipientCount;
    int i;

    remaining = (unsigned int)item->condition;
    itemCopy = *item;
    i = recipientCount = 0;
    for (; i < g_gameState.party_count; i++) {
        if (cmbinv_has_space_for_item(gstate_party_member_record(i)->actor_record, item))
            recipientCount++;
    }
    if (recipientCount == 0) {
        return 0;
    }
    if (src != (Actor far *)0) {
        cmbinv_actor_inv_remove_item(src, item);
    }
    i = assigned = 0;
    for (; i < g_gameState.party_count; i++) {
        recipient = gstate_party_member_record(i)->actor_record;
        if (cmbinv_has_space_for_item(recipient, (ItemSlot far *)&itemCopy)) {
            int portion;
            assigned++;
            portion = (int)(remaining * assigned) / recipientCount;
            if (portion != 0) {
                remaining -= portion;
                itemCopy.condition = (unsigned char)portion;
                ACTOR_ITEM(recipient, recipient->itemCount++) = itemCopy;
                cmbinv_consolidate_stacks(recipient);
                if (itemtbl_record_ptr((ItemSlot far *)&itemCopy)->wCategory == 0x17 &&
                    g_gameState.abActorStatusRanks[g_gameState.party_roster[i]][5] != 0) {
                    gstate_member_consume_rations(g_gameState.party_roster[i], 1);
                }
            }
        }
    }
    return 1;
}

int cmbinv_actor_pickup_item(Actor far *dst_actor, Actor far *src_actor, ItemSlot far *item) {
    int classify;
    int i;

    if (item->item_id == 'T' && (item->flags & 1)) {
        dialog_play_record(0x1b775dUL, 0);
        return -1;
    }
    if (item->item_id == 0x06 && (item->flags & 1)) {
        dialog_play_record(0x1b774eUL, 0);
        return -1;
    }

    if (dst_actor->bResidence == RES_PARTY_SLOT) {
        ItemRecord far *rec;
        rec = itemtbl_record_ptr(item);
        if (rec->wCategory == 7) {
            dst_actor = g_gameState.shared_inventory;
            if (itemtbl_inv_count_by_kind(dst_actor, (unsigned int)item->item_id) != 0) {

                for (i = 0; i < dst_actor->itemCount; i++) {
                    if (ACTOR_ITEM(dst_actor, i).item_id == item->item_id)
                        ACTOR_ITEM(dst_actor, i).condition++;
                }
            } else {

                item->condition = 1;
                ACTOR_ITEM(dst_actor, dst_actor->itemCount++) = *item;
            }
            cmbinv_combat_sort_initiative(dst_actor);
            dst_actor->dirty_flag = 1;
            if (src_actor != 0)
                cmbinv_actor_inv_remove_item(src_actor, item);
            return 1;
        }
    }

    if ((classify = cmbinv_actor_classify_pickup(dst_actor, item)) != 0) {
        ItemRecord far *rec;
        rec = itemtbl_record_ptr(item);
        item->flags &= 0xffbf;
        if (classify == 3)
            item->flags |= 0x40;

        if ((rec->wFlags & 0x8000) ||
            (dst_actor != 0 && src_actor != 0 && dst_actor->bResidence == RES_PARTY_SLOT &&
             src_actor->bResidence == RES_PARTY_SLOT && (rec->wFlags & 0x800))) {
            int has_sub;
            int qty;
            has_sub =
                (src_actor != 0 && actorrec_get_subrecord(src_actor, SUBREC_EVENT_STATE) != 0);

            qty = invinspect_quantity_picker_dlg(
                item, (dst_actor->bResidence == RES_PARTY_SLOT && g_wInCombatMode == 0) ? 1 : 0,
                has_sub);
            if (qty > 0) {
                if (item->condition == qty) {

                    ACTOR_ITEM(dst_actor, dst_actor->itemCount++) = *item;
                    cmbinv_consolidate_stacks(dst_actor);
                    cmbinv_combat_sort_initiative(dst_actor);
                    dst_actor->dirty_flag = 1;
                    if (src_actor != 0)
                        cmbinv_actor_inv_remove_item(src_actor, item);
                } else {
                    int saved_cond;
                    saved_cond = item->condition;
                    item->condition = (unsigned char)qty;
                    ACTOR_ITEM(dst_actor, dst_actor->itemCount++) = *item;
                    item->condition = (unsigned char)(saved_cond - qty);
                    if (src_actor != 0)
                        cmbinv_consolidate_stacks(src_actor);
                    cmbinv_consolidate_stacks(dst_actor);
                    cmbinv_combat_sort_initiative(dst_actor);
                    dst_actor->dirty_flag = 1;
                }
                return 1;
            }
            if (qty < 0) {

                return cmbinv_pty_distribute_item_stack(src_actor, item);
            }
            return -1;
        }

        ACTOR_ITEM(dst_actor, dst_actor->itemCount++) = *item;
        cmbinv_combat_sort_initiative(dst_actor);
        dst_actor->dirty_flag = 1;
        if (src_actor != 0)
            cmbinv_actor_inv_remove_item(src_actor, item);
        if (dst_actor->bResidence == RES_PARTY_SLOT)
            stat_actor_recalc_equip_bonuses(
                (CombatActor *)((char *)&g_gameState + 0x18 +
                                dst_actor->loc.party_slot.wSlot_id * 0x5f));
        return 1;
    }

    {
        ActorSubrecord far *sub;
        if (src_actor == 0 || (sub = actorrec_get_subrecord(src_actor, SUBREC_EVENT_STATE)) == 0) {
            ItemSlot local_item;
            ItemRecord far *rec;
            int qty;
            rec = itemtbl_record_ptr(item);
            local_item = *item;
            qty = cmbinv_actor_find_stack_headroom(dst_actor, item);
            if (qty > 0) {
                local_item.condition = (unsigned char)qty;
                qty = invinspect_quantity_picker_dlg((ItemSlot far *)&local_item, 0, 0);
                if (qty <= 0)
                    return -1;

                if (g_pStackHeadroomSlot != 0) {
                    if ((int)item->condition < qty)
                        item->condition = (unsigned char)qty;
                    g_pStackHeadroomSlot->condition =
                        g_pStackHeadroomSlot->condition + (unsigned char)qty;
                    item->condition = item->condition - (unsigned char)qty;
                    if (g_pStackHeadroomSlot->condition > rec->bMax_stack)
                        g_pStackHeadroomSlot->condition = rec->bMax_stack;
                    if (item->condition == 0)
                        item->condition = 1;
                    if (src_actor != 0)
                        cmbinv_consolidate_stacks(src_actor);
                    dst_actor->dirty_flag = 1;
                    return 1;
                }
                return -1;
            }
        }
    }
    return 0;
}

int far cmbinv_actor_acquire_item(Actor far *actor, ItemSlot far *item) {
    ItemRecord far *rec;
    int partySlot;
    int i;

    rec = itemtbl_record_ptr(item);
    if (rec->wCategory == 7) {
        cmbinv_actor_pickup_item(actor, (Actor far *)0, item);
        return 1;
    }
    if (cmbinv_has_space_for_item(actor, item)) {
        ACTOR_ITEM(actor, actor->itemCount++) = *item;
        actor->dirty_flag = 1;
        cmbinv_combat_sort_initiative(actor);
        if (rec->wCategory != 0x17)
            return 1;
        partySlot = actor->loc.party_slot.wSlot_id - 1;
        if (g_gameState.abActorStatusRanks[partySlot][5] != 0)
            gstate_member_consume_rations(partySlot, 1);
        return 1;
    }
    for (i = 0; i < g_gameState.party_count; i++) {
        actor = g_gameState.party_members[(signed char)g_gameState.party_roster[i]].actor_record;
        if (cmbinv_has_space_for_item(actor, item)) {
            ACTOR_ITEM(actor, actor->itemCount++) = *item;
            cmbinv_combat_sort_initiative(actor);
            actor->dirty_flag = 1;
            if (rec->wCategory == 0x17) {
                partySlot = actor->loc.party_slot.wSlot_id - 1;
                if (g_gameState.abActorStatusRanks[partySlot][5] != 0)
                    gstate_member_consume_rations(partySlot, 1);
            }
            return 1;
        }
    }
    actor = g_gameState.ground_pile;
    if (cmbinv_has_space_for_item(actor, item)) {
        ACTOR_ITEM(actor, actor->itemCount++) = *item;
        cmbinv_combat_sort_initiative(actor);
        actor->dirty_flag = 1;
        return 1;
    }
    return 0;
}

int cmbinv_actor_drop_item_at_pos(Actor far *src_actor, ItemSlot far *item) {
    ItemRecord far *item_rec;

    item_rec = itemtbl_record_ptr(item);
    g_gameState.nEvtArgItemId = (short)item->item_id;
    if ((item->flags & 0x40) && (item_rec->wCategory == 1 || item_rec->wCategory == 3)) {
    dialog_774e:
        dialog_play_record(0x1b774eL, 0);
        goto return_neg1;
    }
    if (item->item_id == 0x54 && (item->flags & 1)) {
        dialog_play_record(0x1b775dL, 0);
        goto return_neg1;
    }
    if ((item->item_id == 0x06 && (item->flags & 1)) || (item_rec->wFlags & 1)) {
        goto dialog_774e;
    }
    if ((g_other_inventory_actor =
             actorspawn_objfixed((uint)g_gameState.nZoneId, g_world_camera->base.pos.xy.nWorld_x,
                                 g_world_camera->base.pos.xy.nWorld_y)) == (Actor far *)0L) {
        dialog_play_record(0x1b7749L, 0);
        g_other_inventory_actor =
            actorspawn_enc_location((uint)g_gameState.nZoneId, g_world_camera->base.pos.xy.nWorld_x,
                                    g_world_camera->base.pos.xy.nWorld_y);
    }
    g_pDroppedItemActor = g_other_inventory_actor;
    g_gameState.nEvtArgCount = (short)g_other_inventory_actor->bResidence;
    if (cmbinv_actor_pickup_item(g_other_inventory_actor, src_actor, item) == 0) {
        dialog_play_record(0x1b7748L, 0);
        goto return_neg1;
    }
    cmbinv_recompute_has_weapon_flag(g_other_inventory_actor);
    return 1;
return_neg1:
    return -1;
}

int cmbinv_member_can_equip_cat(int party_slot_plus_1, ItemSlot far *item) {
    int category;

    category = itemtbl_record_ptr(item)->wCategory;
    if (party_slot_plus_1 == 0) {
        return 0;
    }
    if (gstate_actor_is_caster(gstate_party_member_record(party_slot_plus_1 + -1)) != 0) {
        return (category == 4 || category == 3) ? 1 : 0;
    }
    return (category == 4 || category == 1 || category == 2) ? 1 : 0;
}
