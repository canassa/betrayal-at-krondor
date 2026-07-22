#include <stdio.h>
#include <string.h>
#include "globals.h"
#include "structs.h"
#include "SRC/CHAR/CHARSCRN.H"
#include "SRC/IO/IO.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/WIDGET.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/CHAR/STAT.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/DIALOG/ASKABOUT.H"
#include "SRC/UI/TEXTWRAP.H"
#include "SRC/SCREENS/INVENTOR.H"
#include "statname.h"

char g_dialog_in_char_screen = 0;

extern ConditionInfo far g_aConditionInfo[7];

struct SpellRecord {
    char name[0x18];
    int idx;
};

static void charscreen_draw_spell_book_actor(CombatActor *actor, unsigned char far *pal_scratch) {
    int row;
    int spell_icon;
    int spell_count;
    int first;
    BakFile *stream;
    struct SpellRecord spell_rec;
    register int panel_y;
    register int spell_idx;

    if (gstate_actor_is_caster(actor) != 0) {
        stream = bak_fopen("InvSpell.dat", "rb");
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        gfx_present_dispatch(0, 0, 0x140, 200);
        for (row = 1; row <= 6; row++) {
            *g_pMainScratchBuf = '\0';
            bak_fread(&spell_icon, 1, 2, stream);
            bak_fread(&spell_count, 1, 2, stream);
            panel_y = row * 0x20 - 0x1b;
            g_graphics_context.bGfx_fill_enabled = '\x01';
            g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_outline_color = '\0';
            draw_rect_filled(7, panel_y + 1, 0x27, 0x1e);
            g_graphics_context.bGfx_fill_color = '\x11';
            g_graphics_context.bGfx_outline_color = 0x8e;
            draw_rect_filled(6, panel_y, 0x27, 0x1e);
            resblit_sprite(g_pButtonSpriteUp[spell_icon], 9, panel_y + 1);
            spell_idx = 0;
            first = 1;
            if (spell_idx < spell_count) {
                do {
                    bak_fread(&spell_rec, 1, 0x1a, stream);
                    if (((1 << (spell_rec.idx % 0x10)) &
                         actor->pSpellsKnown[spell_rec.idx / 0x10]) != 0) {
                        if (first == 0) {
                            _fstrcat((char far *)g_pMainScratchBuf, ", ");
                        }
                        _fstrcat((char far *)g_pMainScratchBuf, spell_rec.name);
                        first = 0;
                    }
                    spell_idx++;
                } while (spell_idx < spell_count);
            }
            g_graphics_context.bText_fg_color = '\x01';

            textwrap_draw_aligned((long)g_pMainScratchBuf, 0x33, panel_y + 1, 0x109, 0x1e, 0, 0x10,
                                  0);
            g_graphics_context.bText_fg_color = '\n';
            textwrap_draw_aligned((long)g_pMainScratchBuf, 0x32, panel_y, 0x109, 0x1e, 0, 0x10, 0);
        }
        bak_fclose(stream);
        g_pPalQueuedForFlip = pal_scratch = chunk_load_into_slot("INVENTOR.PAL");
        g_nPalBlendMode = 0;
        screen_frame_present();
        screen_frame_sync_buffers_rect(0, 200);
        cache_release(pal_scratch);
        while (dialog_poll_arrow_or_button() == 0) {
            screen_frame_present();
        }
    }
}

static void far charscreen_draw_sheet_stat_row(int stat_idx, int value, int party_slot) {
    int x_base;
    int y_pos;
    int skillIdx;
    unsigned short selected;
    unsigned short improved;
    char buf[10];

    x_base = stat_idx > 9 ? 0x93 : 0x1e;
    y_pos = ((stat_idx - 4) % 6) * 0x10 + 0x57;
    skillIdx = party_slot * 0x11 + stat_idx;

    selected = gstate_event_read(SKILL_SELECTED(skillIdx));
    improved = gstate_event_read(SKILL_IMPROVED(skillIdx));
    gstate_event_write(SKILL_IMPROVED(skillIdx), 0);
    if (stat_actor_get(&g_gameState.party_members[party_slot], stat_idx, 1) != 0) {
        sprintf(buf, "%3d%%", value);
    } else {
        sprintf(buf, "N/A");
    }
    if (improved != 0) {
        invui_draw_text_aligned_shadow(g_abStatNames[stat_idx], x_base + 0x14, y_pos - 1, 0, 0x89,
                                       0x8f);
        invui_draw_text_aligned_shadow((unsigned char far *)buf, x_base + 0x71, y_pos - 1, 2, 0x89, 0x8f);
    } else {
        invui_draw_text_aligned_shadow(g_abStatNames[stat_idx], x_base + 0x14, y_pos - 1, 0, 10, 1);
        invui_draw_text_aligned_shadow((unsigned char far *)buf, x_base + 0x71, y_pos - 1, 2, 10, 1);
    }
    if (value < 0) {
        value = 0;
    }
    if (100 < value) {
        value = 100;
    }
    if (x_base == 0x93) {
        resblit_sprite_frame(g_pInvSpriteHiAssetTable[0x15], x_base + 0xe, y_pos + 1, 2);
        if (selected != 0) {
            resblit_sprite_frame(g_pInvSpriteHiAssetTable[0x17], x_base + 0x8d, y_pos + 9, 2);
        }
        g_graphics_context.clip.xmin = x_base + 0xd;
        g_graphics_context.clip.xmax = g_graphics_context.clip.xmin + value;
        if (value == 0) {
            g_graphics_context.clip.xmin = 0;
            g_graphics_context.clip.xmax = 0x13f;
            return;
        }
        resblit_sprite_frame(g_pInvSpriteHiAssetTable[0x16], x_base + 0xe, y_pos + 9, 2);
    } else {
        resblit_sprite_frame(g_pInvSpriteHiAssetTable[0x15], x_base - 0xe, y_pos + 1, 0);
        if (selected != 0) {
            resblit_sprite_frame(g_pInvSpriteHiAssetTable[0x17], x_base - 0x10, y_pos + 9, 0);
        }
        g_graphics_context.clip.xmin = (x_base + 0x75) - value;
        g_graphics_context.clip.xmax = x_base + 0x75;
        if (value == 0) {
            g_graphics_context.clip.xmin = 0;
            g_graphics_context.clip.xmax = 0x13f;
            return;
        }
        resblit_sprite_frame(g_pInvSpriteHiAssetTable[0x16], x_base + 0x11, y_pos + 9, 0);
    }
    g_graphics_context.clip.xmin = 0;
    g_graphics_context.clip.xmax = 0x13f;
    return;
}

static void far charscreen_draw_stat_row(int stat_idx, int cur_val, int max_val, int party_slot) {
    int skillIdx;
    int y;
    int fgColor;
    int shadowColor;
    char buf[10];
    unsigned short improved;

    y = stat_idx * 0xb + 0x1c;
    skillIdx = party_slot * 0x11 + stat_idx;
    improved = gstate_event_read(SKILL_IMPROVED(skillIdx));
    fgColor = improved ? 0x89 : -1;
    shadowColor = improved ? 0x8f : -1;
    gstate_event_write(SKILL_IMPROVED(skillIdx), 0);
    invui_draw_text_aligned_shadow(g_abStatNames[stat_idx], 0x69, y, 0, fgColor, shadowColor);
    sprintf(buf, "%d", cur_val);
    invui_draw_text_aligned_shadow((unsigned char far *)buf, 0xa4, y, 2, fgColor, shadowColor);
    if (stat_idx <= 1) {
        invui_draw_text_aligned_shadow((unsigned char far *)"of", 0xaa, y, 0, fgColor, shadowColor);
        sprintf(buf, "%d", max_val);
        invui_draw_text_aligned_shadow((unsigned char far *)buf, 0xc2, y, 2, fgColor, shadowColor);
    }
}

static void far charscreen_info_draw(CombatActor *actor, MenuPage *page, int party_slot,
                                     int full_sheet, unsigned char far *pal_buf) {
    int condCount;
    char buf[80];
    MenuEntry stack_me;
    int i;

    charscreen_recalc_condition_tick();
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    menupage_draw(page);
    g_graphics_context.bClip_enabled = 1;
    g_graphics_context.clip.ymin = g_graphics_context.clip.xmin = 0;
    g_graphics_context.clip.ymax = 199;

    g_graphics_context.clip.xmax = 0x13f;
    askabout_actor_spr_blit_pal_swap(party_slot + 1, -1, 0, pal_buf);
    g_graphics_context.bGfx_fill_color = 0xa8;
    g_graphics_context.bGfx_fill_enabled = 1;
    draw_rect_filled(0x54, 9, 0xde, 0x47);
    resblit_sprite_frame(g_pInvSpriteHiAssetTable[0x19], 0x54, 9, 0);

    resblit_sprite_frame(g_pInvSpriteHiAssetTable[0x19], 0x130, 9, 2);
    resblit_sprite_frame(g_pInvSpriteHiAssetTable[0x1a], 0x56, 9, 0);
    resblit_sprite_frame(g_pInvSpriteHiAssetTable[0x1a], 0x56, 0x4e, 1);
    invui_draw_text_aligned_shadow((unsigned char far *)"Ratings:", 0x5f, 0xe, 0, -1, -1);
    stack_me = page->pEntries[2];
    stack_me.bActive_flag = 1;
    stack_me.pPrimary_label = actor->name;
    widget_dispatch_by_type(&stack_me, -0xe4, 0, 0);
    invui_draw_text_aligned_shadow((unsigned char far *)"Condition:", 0xd2, 0xe, 0, -1, -1);
    i = condCount = 0;
    for (; i < 7; i++) {
        if ((char)g_gameState.abActorStatusRanks[party_slot][i] > 0) {
            sprintf(buf, "%Fs (%d%)", g_aConditionInfo[i].pName,
                    (int)(char)g_gameState.abActorStatusRanks[party_slot][i]);
            invui_draw_text_aligned_shadow((unsigned char far *)buf, 0xdc, ++condCount * 9 + 0x10, 0, 0x89,
                                           0x8f);
        }
    }
    if (condCount == 0) {
        invui_draw_text_aligned_shadow((unsigned char far *)"Normal", 0xdc, 0x1c, 0, -1, -1);
    }
    if (full_sheet != 0) {
        resblit_sprite_frame(g_pInvSpriteHiAssetTable[0x18], 2, 0x6b, 0);
        resblit_sprite_frame(g_pInvSpriteHiAssetTable[0x18], 0xbc, 0x6b, 2);
    } else {
        resblit_sprite_frame(g_pInvSpriteHiAssetTable[9], 0xe6, 0x83, 2);
        resblit_sprite_frame(g_pInvSpriteHiAssetTable[9], -4, 0x83, 0);
    }
    i = 0;
    do {
        charscreen_draw_stat_row(i, stat_actor_get(actor, i, 0), stat_actor_get(actor, i, 1),
                                 party_slot);
        i++;
    } while (i < 4);
    for (i = 0; full_sheet != 0 && i < 0xc; i++) {
        charscreen_draw_sheet_stat_row(i + 4, stat_actor_get(actor, i + 4, 0), party_slot);
    }
}

void charscreen_info_loop(CombatActor *actor) {
    unsigned short memberIdx;
    int firstDraw;
    unsigned short redrawFlag;
    unsigned short savedBlendMode;
    MenuPage *page;
    unsigned char far *savedPal;
    unsigned char far *pal_buf;
    int tmp;
    int slot;
    unsigned int key;

    firstDraw = 1;
    redrawFlag = 0xffff;
    savedBlendMode = g_nPalBlendMode;
    savedPal = palette_set((unsigned char far *)0x0);
    slot = gstate_find_party_slot(actor);
    if (slot >= 0) {
        page = menupage_load("req_info.dat");
        menupage_begin(page);
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
        resblit_load_pal_or_stream("DIALOG.SCR");
        palette_fade_out(0, 0x100, 8, 1);
        palette_screen_clear_black();
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        g_pPalQueuedForFlip = pal_buf = chunk_load_into_slot("INVENTOR.PAL");
        g_nPalBlendMode = 0;
        screen_cursor_hide();
        screen_frame_present();
        palette_set_scaled(0, 0x100, 0, 0);
        g_dialog_in_char_screen = '\x01';
        do {
            do {
                if (redrawFlag != 0) {
                    memberIdx = (unsigned short)g_gameState.party_roster[slot];
                    actor = &g_gameState.party_members[memberIdx];
                    page->pEntries[2].bActive_flag = (unsigned char)gstate_actor_is_caster(actor);
                    if (redrawFlag != 1) {
                        memberIdx = (unsigned short)g_gameState.party_roster[slot];
                        actor = &g_gameState.party_members[memberIdx];
                        charscreen_info_draw(actor, page, memberIdx, 1, pal_buf);
                        if ((g_pPalQueuedForFlip != (unsigned char far *)0x0) && (firstDraw != 0)) {
                            palette_set(g_pPalQueuedForFlip);
                            palette_set_scaled(0, 0x100, 0, 0);
                            g_pPalQueuedForFlip = (unsigned char far *)0x0;
                        }
                    }
                    g_nPalBlendMode = 0;
                    menupage_draw(page);
                    screen_frame_present();
                    screen_frame_sync_buffers_rect(0, 200);
                    if (firstDraw != 0) {
                        palette_fade_in(0, 0x100, 8, 1);
                    }
                    firstDraw = 0;
                    redrawFlag = 0;
                } else {
                    screen_frame_present();
                }
            } while ((key = menupage_run(page, &redrawFlag)) == 0);
            if ((int)key >= 0x80) {
                redrawFlag = 0xffff;
                if ((menupage_state_0e7c() == 2) ||
                    (key_is_down(0x2a) != 0 || key_is_down(0x36) != 0)) {
                    g_gameState.nEvtArgCount = key + 0xff80;
                    dialog_play_record(0x143L, 0);
                } else {
                    if (stat_actor_get(actor, key + 0xff84, 1) != 0) {
                        tmp = memberIdx * 0x11 + key + 0xff84;
                        gstate_event_write(SKILL_SELECTED(tmp),
                                           (unsigned int)!gstate_event_read(SKILL_SELECTED(tmp)));
                    }
                }
            } else {
                if ((key == 0x39) || (key == 0x31)) {
                    redrawFlag = 0xffff;
                    if ((menupage_state_0e7c() == 2) ||
                        (key_is_down(0x2a) != 0 || key_is_down(0x36) != 0)) {
                        g_gameState.nEvtArgCount = memberIdx;
                        dialog_play_record(0x69L, 0);
                    } else {
                        askabout_free_paged_image_table();
                        if (g_gameState.party_count <= ++slot) {
                            slot = 0;
                        }
                    }
                } else {
                    if (((key == 2) || (key == 3)) || (key == 4)) {
                        tmp = key + 0xfffe;
                        askabout_free_paged_image_table();
                        if ((int)tmp < (int)g_gameState.party_count)
                            slot = tmp;
                        redrawFlag = 0xffff;
                    } else {
                        if (key == 0x1f) {
                            charscreen_draw_spell_book_actor(actor, pal_buf);
                            redrawFlag = 0xffff;
                        }
                    }
                }
            }
        } while (key != 1);
        askabout_free_paged_image_table();
        cache_release(pal_buf);
        g_nPalBlendMode = savedBlendMode;
        g_pPalQueuedForFlip = savedPal;
        menupage_end(page);
        menupage_free(page);
        g_dialog_in_char_screen = '\0';
    }
    return;
}

void far charscreen_recalc_condition_tick(void) {
    int memberIdx;
    int i;
    int count;

    memberIdx = 0;
    do {
        i = count = 0;
        for (; i < 0x10; i++) {
            if (gstate_event_read(SKILL_SELECTED(memberIdx * 0x11 + i)) != 0) {
                count++;
            }
        }
        g_gameState.aConditionTickAdvance[memberIdx] = count != 0 ? 0x1a / count : 0;
        memberIdx = memberIdx + 1;
    } while (memberIdx < 6);
    return;
}

static long charscreen_temple_heal_price(CombatActor *actor, int multiplier_pct) {
    int cond;
    int i;
    long total;

    i = total = 0;
    for (; i < 7; i++) {
        if ((cond = (signed char)((unsigned char *)&g_gameState
                                      .aConditionTickAdvance)[5 + actor->cParty_slot * 7 + i]) !=
            0) {
            switch (i) {
            case 0:
                total += (cond << 2) + 10;
                break;
            case 1:
            case 2:
                total += cond * 10 + 10;
                break;
            case 3:
                total += cond * 3 + 10;
                break;
            case 4:
                continue;
            case 5:
                total += (cond << 1) + 10;
                break;
            case 6:
                total += cond * 30 + 10;
                break;
            }
        }
    }
    return (long)total * multiplier_pct / 100;
}

void charscreen_temple_heal_menu(int actor_filter, int mode) {
    unsigned short member_idx;
    unsigned short redraw_flag;
    unsigned short saved_blend_mode;
    MenuPage *page;
    unsigned char far *saved_pal;
    unsigned char far *pal_buf;
    long price;
    DDXRecord far *dlg_rec;
    int slot;
    unsigned int key;
    int stat_idx;
    int dst_slot;

    redraw_flag = 0xffff;
    saved_blend_mode = g_nPalBlendMode;
    saved_pal = palette_set((unsigned char far *)0);
    for (slot = 0; slot < g_gameState.party_count; slot++) {
        if (charscreen_temple_heal_price(gstate_party_member_record(slot), actor_filter) != 0)
            break;
    }
    if (g_gameState.party_count != slot)
        goto LAB_main;
    for (slot = 0; slot < g_gameState.party_count; slot++) {
        if (stat_actor_get(gstate_party_member_record(slot), 0x10, 0) !=
            stat_actor_get(gstate_party_member_record(slot), 0x10, 1))
            break;
    }
    if (mode == 4) {
        if (g_gameState.party_count != slot)
            goto LAB_main;
        dialog_play_record(0x13d66b, 0);
    } else {
        dialog_play_record(g_gameState.party_count == slot ? 0x13d66b : 0x13d673, 0);
    }
    return;
LAB_main:
    page = menupage_load("req_heal.dat");
    menupage_begin(page);
    g_pPalQueuedForFlip = pal_buf = chunk_load_into_slot("INVENTOR.PAL");
    g_nPalBlendMode = 0;
    dlg_rec = dialog_load_record_by_key(0x13d66d, 0);
    screen_frame_present();
    g_dialog_in_char_screen = 1;
    do {
        do {
            if (redraw_flag != 0) {
                g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                if (redraw_flag == 1) {
                    menupage_draw(page);
                } else {
                    member_idx = (signed char)g_gameState.party_roster[slot];
                    g_gameState.nEvtArgActor0 = member_idx;
                    price = charscreen_temple_heal_price(&g_gameState.party_members[member_idx],
                                                         actor_filter);
                    if (mode == 4) {
                        price +=
                            (int)(stat_actor_get(&g_gameState.party_members[member_idx], 0x10, 1) -
                                  stat_actor_get(&g_gameState.party_members[member_idx], 0x10, 0));
                    }
                    g_gameState.lEvtArgGoldCost = price;
                    charscreen_info_draw(&g_gameState.party_members[member_idx], page, member_idx,
                                         0, pal_buf);
                    dialog_cmbt_name_assign_kind(0, 0x13, 0, 0);
                    dialog_render_text_with_tokens(dlg_rec, (char far *)0, 1, -1, 1, 0);
                    dialog_render_text_with_tokens(dlg_rec, (char far *)0, 10, 0, 0, 0);
                }
                screen_frame_present();
                screen_frame_sync_buffers_rect(0, 200);
                redraw_flag = 0;
            } else {
                screen_frame_present();
            }
        } while ((key = menupage_run(page, &redraw_flag)) == 0);
        if (key != 0 &&
            (menupage_state_0e7c() == 2 || key_is_down(0x2a) != 0 || key_is_down(0x36) != 0)) {
            redraw_flag = 0xffff;
            if (key == 0x39 || key == 0x31) {
                g_gameState.nEvtArgCount = member_idx;
                dialog_play_record(0x69, 0);
            } else {
                g_gameState.nEvtArgCount = key;
                dialog_play_record(0x13d66a, 0);
            }
            key = 0;
        }
        if ((key == 2 || key == 3 || key == 4) && g_wInCombatMode == 0) {
            dst_slot = (int)key - 2;
            if (dst_slot < g_gameState.party_count)
                slot = dst_slot;
            redraw_flag = 0xffff;
        }
        if (key == 0x23) {
            if (g_gameState.nParty_gold < price) {
                dialog_play_record(0x13d66c, 0);
            } else {
                g_gameState.nParty_gold -= price;
                dialog_play_record(0x13d66e, 0);
                audio_sfx_play_n_times(0xc, 0, 1);
                g_gameState.dwLastActionTimeSnapshot = g_gameState.game_time;
                stat_idx = 0;
                do {
                    stat_combatant_apply_delta(&g_gameState.party_members[member_idx], stat_idx,
                                               stat_idx == 4 ? 0x14 : -100);
                    stat_idx++;
                } while (stat_idx < 7);
                if (mode == 4) {
                    stat_combatant_modify(&g_gameState.party_members[member_idx], 0x10, 0x7fff,
                                          100);
                    stat_combatant_apply_delta(&g_gameState.party_members[member_idx], 4, 100);
                }
                key = 0x31;
            }
            redraw_flag = 0xffff;
        }
        if ((key == 0x31 || key == 0x39) && g_wInCombatMode == 0) {
            redraw_flag = 0xffff;
            do {
                if (g_gameState.party_count <= ++slot)
                    break;
            } while (charscreen_temple_heal_price(gstate_party_member_record(slot), actor_filter) ==
                     0);
            if (g_gameState.party_count == slot)
                break;
        }
    } while (key != 1);
    askabout_free_paged_image_table();
    dialog_freemem_if_not_null((unsigned char far *)dlg_rec);
    cache_release(pal_buf);
    g_nPalBlendMode = saved_blend_mode;
    g_pPalQueuedForFlip = saved_pal;
    screen_clear_both_pages();
    menupage_end(page);
    menupage_free(page);
    g_dialog_in_char_screen = 0;
}
