#include <dos.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include "gfx169d.h"
#include "globals.h"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/SYS/SYSLOWIO.H"
#include "SRC/INPUT/TIMER.H"
#include "structs.h"
#include "SRC/SCREENS/INVENTOR.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/CMBINV.H"
#include "SRC/SCREENS/ITEMTBL.H"
#include "SRC/SCREENS/ITEMUSE.H"
#include "SRC/WORLD/ACTOR/ACTORREC.H"
#include "SRC/SCREENS/PICKLOCK.H"
#include "SRC/COMBAT/ARENA/COMBAT.H"


short g_nInvSelItemAnchorX;
short g_nInvSelItemAnchorY;
short g_nInvSelItemIconDx;
short g_nInvSelItemIconDy;
short g_nCursorSaveRectX;
short g_nCursorSaveRectY;
unsigned short g_inventory_actor_kind;

ImageRecord **g_pInvSpriteLoAssetTable = {0};
ImageRecord **g_pInvSpriteHiAssetTable = {0};
ImageRecord **g_pInvLockAssetTable = {0};
ImageRecord **g_pInvMiscAssetTable = {0};
unsigned char far *g_pCursorSaveBufActive = {0};
unsigned char far *g_pCursorSaveBufA = {0};
unsigned char far *g_pCursorSaveBufB = {0};
unsigned long g_dwDblClickDeadline = 0x00000000UL;

void invui_inspect_image_cleanup(void) {
    if (g_pInvMiscAssetTable != (ImageRecord **)0x0) {
        _freemem(g_pCursorSaveBufB);
        _freemem(g_pCursorSaveBufA);
        if (g_pInvLockAssetTable != (ImageRecord **)0x0) {
            emsimg_free_paged(g_pInvLockAssetTable);
        }
        emsimg_free_paged(g_pInvMiscAssetTable);
        g_pInvLockAssetTable = g_pInvMiscAssetTable = 0;
    }
}

void invui_inspect_images_load_once(int load_lock_images) {
    int count;
    int maxSize;
    int i;
    int size;

    if (g_pInvMiscAssetTable == (ImageRecord **)0) {
        g_pInvMiscAssetTable = resblit_load_asset_table("INVMISC.BMX", 2);
        if (load_lock_images != 0) {
            g_pInvLockAssetTable = resblit_load_asset_table("INVLOCK.BMX", 2);
        } else {
            g_pInvLockAssetTable = (ImageRecord **)0;
        }
        count = null_terminated_count(g_pInvSpriteLoAssetTable);
        i = maxSize = 0;
        if (i < count) {
            do {
                if ((size = (int)rect_byte_size(g_pInvSpriteLoAssetTable[i]->nWidth,
                                                g_pInvSpriteLoAssetTable[i]->nHeight)) > maxSize) {
                    maxSize = size;
                }
                i++;
            } while (i < count);
        }
        g_pCursorSaveBufActive = g_pCursorSaveBufA = (unsigned char far *)alloc_far((long)maxSize, 0L);
        g_pCursorSaveBufB = (unsigned char far *)alloc_far((long)maxSize, 0L);
        i = 0;
        do {
            g_abCursorPaletteLut[i] = (unsigned char)i;
            i++;

        } while (i < 0x100);
    }
}

ImageRecord *invui_item_sprite_select(ItemSlot far *slot) {
    ItemRecord far *pItem;
    unsigned int uIdx;
    ImageRecord *pSprite;
    int i;

    pItem = itemtbl_record_ptr_by_id((unsigned int)slot->item_id);
    uIdx = pItem->wUnk_30 != 0 ? pItem->wUnk_30 : (unsigned int)slot->item_id;
    pSprite = (int)uIdx < 0x78 ? g_pInvSpriteLoAssetTable[uIdx]
                               : g_pInvSpriteHiAssetTable[(int)uIdx - 0x78];
    for (i = 0x88; i <= 0x8f; i++) {
        g_abCursorPaletteLut[i] = (unsigned char)i;
    }
    g_abCursorPaletteLut[0xca] = 0xca;
    if (pItem->wCategory == 2 && (slot->flags & 0x10)) {
        g_abCursorPaletteLut[0xca] = 0;
    }
    if (slot->item_id == 0x54 && (slot->flags & 1)) {
        pSprite = g_pInvSpriteHiAssetTable[8];
    }
    if (slot->item_id == 6 && (slot->flags & 1)) {
        for (i = 0x88; i <= 0x8f; i++) {
            g_abCursorPaletteLut[i] = (unsigned char)(i - 4);
        }
    }
    return pSprite;
}

void far invui_blit_spr_ckey_dflt_size(ImageRecord *sprite, int x, int y, int w, int h) {
    if (w <= 0) {
        w = sprite->nWidth;
    }
    if (h <= 0) {
        h = sprite->nHeight;
    }

    g_polyRasterState.nRemapTableOff = CURSOR_REMAP_TAB_OFF;
    emsimg_sprite_blit_scaled_paged(sprite, x, y, 0, w, h);
    g_polyRasterState.nRemapTableOff = 0;
}

void invui_portrait_refresh_animated(int portrait_idx, int prev_portrait, int anim_step) {
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
    gfx_present_dispatch(0, 0x84, 0xbe, 0x44);
    anim_step %= 6;
    if (prev_portrait != 0 && prev_portrait != portrait_idx) {
        if (anim_step > 3) {
            resblit_sprite(g_pHeadsBmxAssetTable[0xe - anim_step], prev_portrait * 0x3a - 0x2b,
                           0x94);
        } else {
            resblit_sprite(g_pHeadsBmxAssetTable[anim_step + 8], prev_portrait * 0x3a - 0x2b, 0x94);
        }
        while (g_nFrameTickCountdown != 0)
            ;
        g_nFrameTickCountdown = 9;
    }
    if (portrait_idx != 0) {
        resblit_sprite(g_pHeadsBmxAssetTable[7], portrait_idx * 0x3a - 0x2b, 0x94);
    }
}

void invui_draw_text_aligned_shadow(char far *text, int x, int y, int align, int fg_color,
                                    int shadow_color) {
    if (align == 2) {
        x -= font_text_pixel_width(text);
    } else if (align != 0) {
        x -= font_text_pixel_width(text) / 2;
    }
    if (shadow_color >= -1) {
        g_graphics_context.bText_fg_color = shadow_color >= 0 ? (unsigned char)shadow_color : 0;
        font_draw_text_far(text, x + 1, y + 1);
    }
    g_graphics_context.bText_fg_color = fg_color >= 0 ? (unsigned char)fg_color : (unsigned char)0x9f;
    font_draw_text_far(text, x, y);
    return;
}

static void invui_op_noop(void) {
    return;
}

void far invui_portr_panel_fill_pulsing(int state, int phase) {
    register int m;

    m = phase;
    m %= 6;
    g_graphics_context.bGfx_fill_enabled = 0;
    if (state != 0) {
        g_graphics_context.bGfx_outline_color = (char)((m > 3) ? ('q' - m) : (m + 'k'));
    } else {
        g_graphics_context.bGfx_outline_color = 0;
    }
    draw_rect_filled(0xd, 0xb, 0x52, 0x79);
}

static void invui_portrait_panel_draw(int mode, int tick) {
    register int phase;
    ImageRecord *sprite;
    int xDst, yDst;

    phase = tick;
    sprite = g_pInvMiscAssetTable[g_inventory_actor_kind];
    xDst = (0x40 - sprite->nWidth) / 2 + 0xc3;
    yDst = (0x1f - sprite->nHeight) / 2 + 0x94;
    phase %= 6;
    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bGfx_fill_color = 0;
    if (mode < 0) {
        g_graphics_context.bGfx_outline_color = 'i';
    } else if (mode != 0) {
        g_graphics_context.bGfx_outline_color = (char)((phase > 3) ? ('q' - phase) : (phase + 'k'));
    } else {
        g_graphics_context.bGfx_outline_color = 0;
    }
    draw_rect_filled(0xc3, 0x94, 0x40, 0x1f);
    resblit_sprite(sprite, xDst, yDst);
    g_graphics_context.bGfx_fill_enabled = 0;
    draw_rect_filled(0xc3, 0x94, 0x40, 0x1f);
}

void far invui_cur_spr_paint_ctrd(ImageRecord *sprite, int mode) {
    short nx;
    short ny;
    short dstX;
    short dstY;

    if ((sprite != (ImageRecord *)0) && (mode == 0)) {
        g_graphics_context.bClip_enabled = 1;
        g_graphics_context.clip.xmin = g_graphics_context.clip.ymin = 0;

        g_graphics_context.clip.xmax = 0x13f;
        g_graphics_context.clip.ymax = 199;
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        screen_cursor_get_position(&nx, &ny);
        nx -= sprite->nWidth / 2;
        ny -= sprite->nHeight / 2;
        if ((dstX = nx) < 0) {
            dstX = 0;
        }
        if ((dstY = ny) < 0) {
            dstY = 0;
        }
        cga_save_rect_to_buffer(g_pCursorSaveBufActive, dstX, dstY, sprite->nWidth,
                                sprite->nHeight);
        if (g_nCursorSaveRectX >= 0) {
            invui_blit_spr_ckey_dflt_size(sprite, nx, ny, -1, -1);
        }
    }
    screen_frame_present();
    if (sprite != (ImageRecord *)0) {
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        g_pCursorSaveBufActive =
            ((unsigned char huge *)g_pCursorSaveBufActive == (unsigned char huge *)g_pCursorSaveBufA)
                ? g_pCursorSaveBufB
                : g_pCursorSaveBufA;
        if (g_nCursorSaveRectX >= 0) {
            cga_rect_paste_from_buffer(g_pCursorSaveBufActive, g_nCursorSaveRectX,
                                       g_nCursorSaveRectY, sprite->nWidth, sprite->nHeight);
        }
        g_nCursorSaveRectX = dstX;
        g_nCursorSaveRectY = dstY;
    }
}

int far invui_actor_inventory_kind(Actor far *actor, int flag) {
    if (g_inventory_screen_mode == 2) {
        return -1;
    }
    if (actor->bResidence == RES_PICKLOCK_BUFFER ||
        (actor->bResidence == RES_PARTY_SLOT && g_other_inventory_actor == (Actor far *)0 &&
         flag == 0)) {
        return 0xb;
    }
    if (actor->bResidence == RES_PARTY_SLOT) {
        actor = g_other_inventory_actor;
        if (g_other_inventory_actor != (Actor far *)0)
            goto check_combat;
        return 0;
    }
check_combat:
    if (actor->bResidence == RES_COMBAT) {
        return 4;
    }
    if (actorrec_get_subrecord(actor, SUBREC_EVENT_STATE) != (ActorSubrecord far *)0) {
        return 7;
    }
    switch ((unsigned)ts_get_shape(actor->world_item_id)->kind - 6) {
    case 0:
        return 1;
    case 11:
        return 2;
    case 6:
        return 3;
    case 10:
        return 4;
    case 4:
        return 10;
    case 18:
        return 8;
    case 24:
        return 9;
    case 29:
        return 5;
    case 25:
        return 0;
    case 20:
    case 21:
    case 22:
        return 6;
    default:
        return 0;
    }
}

void far invui_status_icons_render(unsigned status_bits, int x, int y) {
    int bit;

    status_bits &= 0xff80;
    if (status_bits != 0) {
        for (bit = 7; bit < 16; bit++) {
            if ((status_bits & (1 << bit)) != 0) {
                resblit_sprite(g_pInvSpriteHiAssetTable[bit + 5], x, y);
                x += 10;
            }
        }
    }
}

static void invui_grid_render(MenuPage *page, Actor far *actor, short selected_slot,
                              short highlight_slot) {
    MenuPage *pg = page;
    MenuEntry *e;
    int slot_idx;
    int saved_count;
    int has_subrec;
    char buf[100];

    has_subrec = actorrec_get_subrecord(actor, SUBREC_EVENT_STATE) != 0;
    g_inventory_actor_kind = invui_actor_inventory_kind(actor, highlight_slot != -1);
    g_graphics_context.bClip_enabled = 1;

    /* The lone `xor ax,ax; mov [ymin],ax` zero store is a chained assignment
     * whose RIGHT-hand partner store is dead: slot_idx's next access is the
     * `slot_idx = 7` re-init below, so -Ob deletes just the `mov [slot_idx],ax`
     * while the chain's xor-AX form survives (a plain `= 0` emits the 6-byte
     * `mov word,0` instead).  This replaced a sanctioned _AX pin 2026-07-11;
     * the pin-era probes had only tried the reverted chain order
     * (`slot_idx = ymin = 0`), which collapses back to the 6-byte form.
     * NB: this block then sets clip.xmax=0x13f and clip.xmin=199, never
     * touching clip.ymax - an apparent 1993 typo (every sibling clip-setup
     * sets ymax=199), faithfully reproduced. */
    g_graphics_context.clip.ymin = slot_idx = 0;
    g_graphics_context.clip.xmax = 0x13f;
    g_graphics_context.clip.xmin = 199;

    pg->pEntries[3].wEnable_gate = 1;
    pg->pEntries[4].wEnable_gate = 1;
    pg->pEntries[4].bActive_flag = 0;

    if (actor->bResidence == RES_PARTY_SLOT && g_inventory_screen_mode != 2) {
        pg->pEntries[4].bActive_flag = 1;
        pg->pEntries[4].wAction_id = 22;
        pg->pEntries[4].wSprite_base = 34;
        pg->pEntries[4].wEnable_gate = 0;
        pg->pEntries[3].wEnable_gate = 0;
        pg->pEntries[3].wAction_id = 32;
    } else if (has_subrec && actor->itemCount > 6) {
        pg->pEntries[4].bActive_flag = 1;
        pg->pEntries[4].wAction_id = 50;
        pg->pEntries[4].wSprite_base = 103;
        pg->pEntries[4].wEnable_gate = 0;
    } else {
        pg->pEntries[3].wEnable_gate = 1;
        pg->pEntries[4].bActive_flag = 0;
    }

    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
    gfx_present_dispatch(0, 0, 0x140, 200);

    saved_count = pg->wEntry_count;
    pg->wEntry_count = 7;
    menupage_draw(pg);
    pg->wEntry_count = saved_count;

    if ((int)g_inventory_actor_kind >= 0)
        invui_portrait_panel_draw(0, 0);

    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_outline_color = 0;

    if (actor->bResidence == RES_PARTY_SLOT || g_bInventoryShopMode != 0) {
        draw_rect_filled(0xd, 0xb, 0x52, 0x79);
        draw_rect_filled(0x69, 0xb, 0xca, 0x79);
    } else {
        draw_rect_filled(0xd, 0xb, 0x126, 0x79);
    }

    if (actor->bResidence != RES_PARTY_SLOT)
        invui_portrait_panel_draw(-1, 0);

    if (actor->bResidence == RES_PARTY_SLOT) {
        if (gstate_actor_is_caster(gstate_party_member_record(selected_slot - 1)) == 0)
            resblit_sprite(g_pInvSpriteHiAssetTable[10], 0xe, 0x2b);
        resblit_sprite(g_pInvSpriteHiAssetTable[11], 0xe, 0x49);
    }

    g_graphics_context.bGfx_fill_enabled = 1;
    slot_idx = 7;
    e = &pg->pEntries[7];
    while ((short)pg->wEntry_count > slot_idx) {
        if (e->wSprite_base != 0) {
            ItemSlot far *slot;
            ItemRecord far *item;
            ImageRecord *sprite;
            int icon_x, icon_y;

            slot = ACTOR_ITEMS(actor) + (e->wAction_id - 0x80);
            item = itemtbl_record_ptr(slot);
            sprite = invui_item_sprite_select(slot);

            icon_x = e->rect.x + pg->rect.x + (e->rect.width - sprite->nWidth) / 2;
            icon_y =
                e->rect.y + pg->rect.y + (e->rect.height - sprite->nHeight) / (has_subrec ? 4 : 2);

            if (highlight_slot >= 0 && (e->wAction_id - 0x80) == highlight_slot) {
                g_graphics_context.bGfx_fill_color = 0x8f;
                g_graphics_context.bGfx_outline_color = 0x8b;
                draw_rect_filled(e->rect.x + pg->rect.x, e->rect.y + pg->rect.y, e->rect.width,
                                 e->rect.height);
                g_nInvSelItemAnchorX = icon_x;
                g_nInvSelItemAnchorY = icon_y;
                g_nInvSelItemIconDx = e->rect.x - icon_x;
                g_nInvSelItemIconDy = e->rect.y - icon_y;
            } else if ((slot->flags & 0x40) != 0) {
                g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_outline_color = 0;
                draw_rect_filled(e->rect.x + pg->rect.x, e->rect.y + pg->rect.y, e->rect.width,
                                 e->rect.height);
            }

            invui_blit_spr_ckey_dflt_size(sprite, icon_x, icon_y, -1, -1);

            if (slot->flags != 0)
                invui_status_icons_render(slot->flags, e->rect.x + 1, e->rect.y + 1);

            if (has_subrec) {
                int text_x, text_ym1;
                long item_value;
                text_x = e->rect.x + pg->rect.x + e->rect.width / 2;
                text_ym1 = e->rect.y + pg->rect.y + e->rect.height - 1;
                item_value = itemtbl_compute_value(slot);
                sprintf(buf, "%Fs", (char far *)item);
                if (item->wName_split_off != 0) {
                    item->pName[item->wName_split_off] = '\0';
                    if (item->wDefault_qty_or_1 == 4)
                        invui_draw_text_aligned_shadow(
                            (char far *)item, text_x - 1,
                            text_ym1 - 1 - g_graphics_context.pFont_height[0] * 3, 1, 0, 0);
                    invui_draw_text_aligned_shadow(
                        (char far *)item, text_x, text_ym1 - g_graphics_context.pFont_height[0] * 3,
                        1, -1, -1);
                    sprintf(buf, "%Fs", (char far *)item + (item->wName_split_off + 1));
                    item->pName[item->wName_split_off] = ' ';
                }
                if ((item->wFlags & 0xa000) != 0) {
                    sprintf(buf + strlen(buf), " (%d)", slot->condition);
                } else if ((item->wFlags & 0x1000) != 0) {
                    sprintf(buf + strlen(buf), " (%d%%)", slot->condition);
                }
                g_graphics_context.bText_fg_color = 0x9f;
                if (item->wDefault_qty_or_1 == 4)
                    invui_draw_text_aligned_shadow(
                        (char far *)buf, text_x - 1,
                        text_ym1 - 1 - g_graphics_context.pFont_height[0] * 2, 1, 0, 0);
                invui_draw_text_aligned_shadow((char far *)buf, text_x,
                                               text_ym1 - g_graphics_context.pFont_height[0] * 2, 1,
                                               -1, -1);
                if (item_value < 0) {
                    sprintf(buf, "Unavailable");
                } else {
                    long g = item_value / 10;
                    long r = item_value % 10;
                    if (r != 0) {
                        if (g != 0)
                            sprintf(buf, "%ld gold %ld silver", g, r);
                        else
                            sprintf(buf, "%ld silver", r);
                    } else {
                        sprintf(buf, "%ld gold", g);
                    }
                }
                invui_draw_text_aligned_shadow((char far *)buf, text_x,
                                               text_ym1 - g_graphics_context.pFont_height[0], 1, -1,
                                               -1);
            } else {
                if ((item->wFlags & 0x1000) != 0 && (item->wFlags & 8) != 0) {
                    int text_x, text_ym1;
                    text_x = e->rect.x + pg->rect.x + e->rect.width;
                    text_ym1 = e->rect.y + pg->rect.y + e->rect.height -
                               g_graphics_context.pFont_height[0];
                    g_graphics_context.bText_fg_color = 0x9f;
                    sprintf(buf, "%d%%", slot->condition);
                    font_draw_text_ds(buf, text_x - font_text_width_ds(buf), text_ym1);
                } else {
                    int text_x, text_ym1;
                    if ((item->wFlags & 0x8000) == 0 && actor->bResidence != RES_PICKLOCK_BUFFER) {
                        if ((item->wFlags & 0x3000) == 0)
                            goto next_slot;
                        if (highlight_slot < 0)
                            goto next_slot;
                        if ((e->wAction_id - 0x80) != highlight_slot)
                            goto next_slot;
                    }
                    text_x = e->rect.x + pg->rect.x + e->rect.width;
                    text_ym1 = e->rect.y + pg->rect.y + e->rect.height -
                               g_graphics_context.pFont_height[0];
                    g_graphics_context.bText_fg_color = 0x9f;
                    itoa(slot->condition, buf, 10);
                    font_draw_text_ds(buf, text_x - font_text_width_ds(buf), text_ym1);
                }
            }
        next_slot:;
        }
        slot_idx++;
        e++;
    }

    invui_portrait_refresh_animated(selected_slot, 0, 0);
    if (g_bInventoryShopMode != 0)
        picklock_lock_slide_animation(0);

    {
        long gold = g_gameState.nParty_gold / 10;
        long silver = g_gameState.nParty_gold % 10;
        if (actor->bResidence == RES_PARTY_SLOT)
            invui_op_noop();
        if (gold > 9999)
            sprintf(buf, "%ld", gold);
        else
            sprintf(buf, "%lds %ldr", gold, silver);
    }

    invui_draw_text_aligned_shadow((char far *)buf, 0x103, 0xb7, 2, -1, -1);
}

void far invui_render_present_sync(MenuPage *page, Actor far *actor, short selected_slot,
                                   short highlight_slot) {
    invui_grid_render(page, actor, selected_slot, highlight_slot);
    screen_frame_present();
    screen_frame_sync_buffers_rect(0, 200);
}

static void far invui_animate_item_fly(ImageRecord *image, int src_x, int src_y, int dst_x,
                                       int dst_y, int actor, int sfx_flag, int is_shop) {
    int i;
    int x;
    int y;
    int scaled_w;
    int scaled_h;
    int prev_x;
    int prev_y;

    prev_x = -999;
    prev_y = -999;
    audio_sfx_play_n_times(is_shop != 0 ? 0x3c : 0x3d, 0, 0);
    for (i = 14; i >= 0; i--) {
        g_graphics_context.bClip_enabled = 1;
        g_graphics_context.clip.xmin = g_graphics_context.clip.ymin = 0;
        g_graphics_context.clip.xmax = 0x13f;
        g_graphics_context.clip.ymax = 199;
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
        invui_portrait_refresh_animated(actor, sfx_flag, 0);
        if (sfx_flag == 0) {
            invui_portrait_panel_draw(1, 0);
        }
        scaled_w = (image->nWidth * i) / 0xf;
        scaled_h = (image->nHeight * i) / 0xf;
        x = ((dst_x - src_x) * i / 0xf + src_x) - scaled_w / 2;
        y = ((dst_y - src_y) * i / 0xf + src_y) - scaled_h / 2;
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;
        cga_save_rect_to_buffer(g_pCursorSaveBufActive, x < 0 ? 0 : x, y < 0 ? 0 : y, image->nWidth,
                                image->nHeight);
        if ((scaled_w > 0) && (scaled_h > 0)) {
            invui_blit_spr_ckey_dflt_size(image, x, y, scaled_w, scaled_h);
        }
        screen_frame_present();
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        if (i == 14) {
            screen_frame_sync_buffers_rect(0, 200);
            cga_rect_paste_from_buffer(g_pCursorSaveBufActive, x < 0 ? 0 : x, y < 0 ? 0 : y,
                                       image->nWidth, image->nHeight);
        }
        g_pCursorSaveBufActive =
            ((unsigned char huge *)g_pCursorSaveBufActive == (unsigned char huge *)g_pCursorSaveBufA)
                ? g_pCursorSaveBufB
                : g_pCursorSaveBufA;
        if (prev_x != -999) {
            cga_rect_paste_from_buffer(g_pCursorSaveBufActive, prev_x, prev_y, image->nWidth,
                                       image->nHeight);
        }
        prev_x = x < 0 ? 0 : x;
        prev_y = y < 0 ? 0 : y;
    }
}

#pragma intrinsic(abs)

int far invui_handle_item_drag(MenuPage *page, Actor far *actor, int selected_slot,
                               int *p_selected_slot) {
    unsigned short consumed;
    int target_slot;
    int equip_portrait;
    int item_cat;
    int dist;
    int cx;
    int cy;
    int phase;
    int init_cx;
    int init_cy;
    int dragging;
    unsigned int is_shop;
    int old_sel;
    ItemSlot far *item_ptr;
    MenuEntry *focused;
    MenuEntry *hovered;
    Actor far *party_actor;

    phase = 0;
    init_cx = screen_cursor_get_x();
    init_cy = screen_cursor_get_y();
    dragging = 0;
    is_shop = (actorrec_get_subrecord(actor, SUBREC_EVENT_STATE) != 0);
    old_sel = *p_selected_slot;
    item_ptr = (ItemSlot far *)0;

    focused = menupage_focused_entry();
    if (focused == 0 && screen_input_poll_confirm_cancel() == 1) {
        *p_selected_slot = -1;
        return 1;
    }

    if ((focused = menupage_focused_entry()) == 0)
        return 0;
    if (focused->wSprite_base == 0)
        return 0;
    if (focused->wAction_id < 0x80)
        return 0;

    item_ptr = ACTOR_ITEMS(actor) + (focused->wAction_id - 0x80);
    g_nCursorSaveRectX = -1;
    g_nFrameTickCountdown = 0;
    g_gameState.nEvtArgItemId = item_ptr->item_id;

    while (screen_input_poll_confirm_cancel() == 1) {
        if (dragging) {
            invui_cur_spr_paint_ctrd(invui_item_sprite_select(item_ptr), 0);
        } else {
            invui_cur_spr_paint_ctrd((ImageRecord *)0, 0);
        }
        menupage_run(page, &consumed);
        cx = screen_cursor_get_x();
        cy = screen_cursor_get_y();
        dist = abs(cx - init_cx) + abs(cy - init_cy);
        if (dist > 4) {
            if (!dragging && !is_shop) {
                focused->wSprite_base = 0;
                invui_render_present_sync(page, actor, selected_slot, -2);
            }
            dragging = 1;
            if ((hovered = menupage_state_0e84()) != 0 && actor->bResidence != 8) {
                target_slot = hovered->wAction_id - 2 + 1;
            } else {
                target_slot = 0;
            }
            if (g_wInCombatMode != 0 && actor->bResidence == 7 &&
                combat_arena_dist_actors_by_id(selected_slot, target_slot) > 1) {
                target_slot = 0;
            }
            if (target_slot >= 0 && target_slot <= g_gameState.party_count) {
                if (target_slot > 0) {
                    g_gameState.nEvtArgActor1 = g_gameState.party_roster[target_slot - 1];
                    if (selected_slot == 0)
                        g_gameState.nEvtArgActor0 = g_gameState.nEvtArgActor1;
                }
                invui_portrait_refresh_animated(selected_slot, target_slot, phase);
            } else {
                invui_portrait_refresh_animated(selected_slot, 0, 0);
            }
            equip_portrait = (&(page)->pEntries[3] == hovered && actor->bResidence == 1);
            invui_portrait_panel_draw(equip_portrait, phase);
            if (actor->bResidence != 1) {
                invui_portrait_panel_draw(-1, 0);
            }
            item_cat = 0;
            if (actor->bResidence == 1 && selected_slot != 0) {
                if (cx > 0xd && cx < 0x5f && cy > 0xb && cy < 0x84 &&
                    cmbinv_member_can_equip_cat(selected_slot, item_ptr) != 0) {
                    item_cat = itemtbl_record_ptr_by_id(
                                   (ACTOR_ITEMS(actor) + (focused->wAction_id - 0x80))->item_id)
                                   ->wCategory;
                }
                invui_portr_panel_fill_pulsing(item_cat, phase);
                invui_op_noop();
            } else if (g_bInventoryShopMode != 0) {
                if (cx > 0xd && cx < 0x5f && cy > 0xb && cy < 0x84) {
                    item_cat = (ACTOR_ITEMS(actor) + (focused->wAction_id - 0x80))->item_id;
                }
                invui_portr_panel_fill_pulsing(item_cat, phase);
            }
            phase = (phase + 1) % 12;
        }
    }

    if (dragging) {
        *p_selected_slot = -1;
        invui_cur_spr_paint_ctrd(invui_item_sprite_select(item_ptr), 0);
    } else {
        *p_selected_slot = focused->wAction_id - 0x80;
        g_gameState.nEvtArgItemId = (ACTOR_ITEMS(actor) + *p_selected_slot)->item_id;
        if (*p_selected_slot == old_sel && g_dwDblClickDeadline > g_timer_ticks) {
            g_dwDblClickDeadline = 0;
            return -2;
        }
        g_dwDblClickDeadline = g_timer_ticks + 0x32;
    }
    menupage_run(page, &consumed);

    if (dragging && (selected_slot == 0 || target_slot != selected_slot) && target_slot >= 1 &&
        target_slot <= g_gameState.party_count) {
        ImageRecord *spr;
        int xfer_result;
        spr = invui_item_sprite_select(item_ptr);
        if (g_wInCombatMode != 0 &&
            combat_arena_dist_actors_by_id(selected_slot, target_slot) > 1) {
            dialog_play_record(0x1b774c, 0);
            goto play_record;
        }
        if (g_wInCombatMode != 0 && actor->bResidence != 1 && (item_ptr->flags & 0x40))
            goto blocked;
        invui_portrait_refresh_animated(selected_slot, target_slot, 0);
        invui_cur_spr_paint_ctrd(spr, 0);
        screen_frame_sync_buffers_rect(0, 200);
        party_actor =
            g_gameState.party_members[g_gameState.party_roster[target_slot - 1]].actor_record;
        g_gameState.nEvtArgCount = 1;
        *p_selected_slot = -1;
        if ((xfer_result = cmbinv_actor_transfer_item(party_actor, actor, item_ptr)) == 0) {
            g_gameState.nEvtArgCount = (actor->bResidence == 1);
            dialog_play_record(0x1b7748, 0);
            return 1;
        } else if (xfer_result > 0) {
            invui_grid_render(page, actor, selected_slot, -2);
            invui_animate_item_fly(spr, (page)->rect.x + hovered->rect.x + hovered->rect.width / 2,
                                   (page)->rect.y + hovered->rect.y + hovered->rect.height / 2, cx,
                                   cy, selected_slot, target_slot, is_shop);
        }
        return 1;
    blocked:
        dialog_play_record(actor->bResidence == 7 ? 0x1b7769 : 0x1b774d, 0);
    play_record:;
    }

    if (dragging && equip_portrait != 0) {
        ImageRecord *spr;
        int xfer_result;
        spr = invui_item_sprite_select(item_ptr);
        invui_portrait_panel_draw(1, 0);
        invui_portrait_refresh_animated(selected_slot, 0, 0);
        invui_cur_spr_paint_ctrd(spr, 0);
        screen_frame_sync_buffers_rect(0, 200);
        *p_selected_slot = -1;
        if ((xfer_result = cmbinv_actor_transfer_item(g_other_inventory_actor, actor, item_ptr)) ==
            0) {
            g_gameState.nEvtArgCount = g_other_inventory_actor->bResidence;
            dialog_play_record(0x1b7748, 0);
            return 0;
        }
        if (xfer_result > 0) {
            invui_grid_render(page, actor, selected_slot, -2);
            invui_animate_item_fly(
                spr, (page)->rect.x + hovered->rect.x + hovered->rect.width / 2,
                (page)->rect.y + hovered->rect.y + hovered->rect.height / 2, cx, cy, selected_slot,
                target_slot,
                (is_shop != 0 ||
                 actorrec_get_subrecord(g_other_inventory_actor, SUBREC_EVENT_STATE) != 0));
        }
        return 1;
    } else if (dragging && item_cat != 0) {
        *p_selected_slot = -1;
        if (g_bInventoryShopMode != 0) {
            if (picklock_screen_handle_drop(item_cat == 0x50 ? 0 : item_cat + 0xffc4,
                                            selected_slot) != 0)
                return -1;
        } else {
            itemuse_dispatch_on_target(actor, ACTOR_ITEMS(actor) + (focused->wAction_id - 0x80),
                                       (ItemSlot far *)0, selected_slot);
        }
        return 1;
    } else {
        ItemSlot far *src_item;
        ItemSlot far *dst_item;
        unsigned int cat;
        if (selected_slot == 0 || !dragging || hovered == 0 || hovered->wAction_id < 0x80)
            return 0;
        src_item = ACTOR_ITEMS(actor) + (focused->wAction_id - 0x80);
        dst_item = ACTOR_ITEMS(actor) + (hovered->wAction_id - 0x80);
        cat = itemtbl_record_ptr(src_item)->wCategory;
        if (focused->wAction_id != hovered->wAction_id &&
            (((int)cat >= 8 && (int)cat <= 0xc) || cat == 0x19)) {
            itemuse_dispatch_on_target(actor, src_item, dst_item, selected_slot);
        }
        *p_selected_slot = -1;
        return 0;
    }
}
