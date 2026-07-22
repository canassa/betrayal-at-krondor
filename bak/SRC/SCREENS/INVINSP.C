#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "globals.h"
#include "structs.h"
#include "SRC/SCREENS/INVINSP.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/GFX/RASTER/DRAWLINE.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCREENS/INVENTOR.H"
#include "SRC/SCREENS/ITEMTBL.H"

DDXRecord g_invInspectPanelDdx = {0x05, 0x0000, 0x0000, 0x00, 0x01, 0x0001};
unsigned char g_abInvInspectPanelDdxStyle[10] = {0x06, 0x00, 0x67, 0x00, 0x0b,
                                                 0x00, 0xcc, 0x00, 0x79, 0x00};

static void far invinspect_dialog_panel_render(MenuPage *panel, int present_now) {
    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bGfx_fill_color = (g_graphics_context.bGfx_outline_color = 0);

    if (present_now != 0) {
        draw_rect_filled(0xd, 0xb, 0x126, 0x79);
    }

    dialog_frame_draw(&g_invInspectPanelDdx, (int far *)&panel->rect.x);

    g_graphics_context.bGfx_outline_color = 0x95;
    draw_rect_filled(panel->rect.x - 1, panel->rect.y - 1, panel->rect.width + 2,
                     panel->rect.height + 2);

    g_graphics_context.bGfx_outline_color = 0x94;
    draw_rect_filled(panel->rect.x, panel->rect.y, panel->rect.width, panel->rect.height);

    g_graphics_context.bGfx_outline_color = 0x92;
    draw_line(panel->rect.x, panel->rect.y - 1, panel->rect.x + panel->rect.width,
              panel->rect.y - 1);
    draw_line(panel->rect.x + panel->rect.width, panel->rect.y - 1,
              panel->rect.x + panel->rect.width, panel->rect.y + panel->rect.height);

    g_graphics_context.bGfx_outline_color = 0x90;
    draw_line(panel->rect.x + 1, panel->rect.y, panel->rect.x + panel->rect.width - 1,
              panel->rect.y);
    draw_line(panel->rect.x + panel->rect.width - 1, panel->rect.y,
              panel->rect.x + panel->rect.width - 1, panel->rect.y + panel->rect.height - 1);

    invui_draw_text_aligned_shadow((unsigned char far *)panel->pTitle, panel->rect.x + panel->nTitle_x,
                                   panel->rect.y + panel->nTitle_y, 1, -1, -1);

    if (present_now != 0) {
        screen_frame_present();
        screen_frame_sync_buffers_rect(0xb, 0x84);
    }
}

int far invinspect_quantity_picker_dlg(ItemSlot far *item, int param_2, int param_3) {
    register int value;
    register MenuPage *page;
    int maxValue;
    unsigned short dirty;
    char *label;
    unsigned int action;

    value = item->condition;
    maxValue = value;
    dirty = 1;
    if (maxValue >= 2) {
        page = menupage_load("req_inv2.dat");
        if (param_2 == 0) {
            page->wEntry_count--;
            page->rect.y += 7;
            page->rect.height -= 0xe;
        }
        if (param_3 != 0) {
            int i;
            for (i = 1; i < 5; i = i + 1) {
                page->pEntries[i].wEnable_gate = 1;
            }
        }
        label = page->pEntries->pPrimary_label;
        menupage_begin(page);
        invinspect_dialog_panel_render(page, param_3);
        do {
            do {
                if (dirty != 0) {
                    strcpy(label, "Give: ");
                    if (value == 0) {
                        strcpy(label, "None: (Cancel)");
                    } else {
                        itoa(value, label + 6, 10);
                        if (value == maxValue) {
                            strcat(label, " (All)");
                        }
                    }
                    menupage_draw(page);
                    screen_frame_present();
                    screen_frame_sync_buffers_rect(page->rect.y + -5, page->rect.height + 10);
                } else {
                    screen_frame_present();
                }
                action = menupage_run(page, &dirty);
                if (menupage_state_0e7c() == 2) {
                    action = 0;
                }
            } while (action == 0);
            if (param_3 == 0) {
                if ((((action == 0x4a) || (action == 0x33)) || (action == 0x4b)) ||
                    (action == 0x50)) {
                    if (key_is_down(0x2a) != 0)
                        goto L_down_shift;
                    if (key_is_down(0x36) == 0)
                        goto L_down_no_shift;
                L_down_shift:
                    action = 0x51;
                    goto L_check_up;
                L_down_no_shift:
                    dirty = 1;
                    if (--value < 0) {
                        value = maxValue;
                    }
                }
            L_check_up:
                if (((action == 0x4e) || (action == 0x34)) ||
                    ((action == 0x4d || (action == 0x48)))) {
                    if (key_is_down(0x2a) != 0)
                        goto L_up_shift;
                    if (key_is_down(0x36) == 0)
                        goto L_up_no_shift;
                L_up_shift:
                    action = 0x49;
                    goto L_check_pgup;
                L_up_no_shift:
                    dirty = 1;
                    if (++value > maxValue) {
                        value = 0;
                    }
                }
            L_check_pgup:
                if (action == 0x49) {
                    dirty = 1;
                    if (value == maxValue) {
                        value = 0;
                    } else {
                        if ((value += 5) > maxValue) {
                            value = maxValue;
                        }
                    }
                }
                if (action == 0x51) {
                    dirty = 1;
                    if (value == 0) {
                        value = maxValue;
                    } else {
                        if ((value -= 5) < 0) {
                            value = 0;
                        }
                    }
                }
            }
            if ((param_2 != 0) && (action == 0x1f)) {
                action = 0x22;
                value = -1;
            }
        } while (((action != 1) && (action != 0x22)) && (action != 0x39));
        menupage_end(page);
        menupage_free(page);
        if (action == 1) {
            return 0;
        }
        return value;
    }
    return value;
}

static void far invinspect_animate_item_move(ImageRecord *sprite, int x, int y, int dst_x,
                                             int dst_y, unsigned int flags) {
    int dx;
    int dy;

    g_graphics_context.bGfx_fill_enabled = '\x01';
    g_graphics_context.bGfx_fill_color = (g_graphics_context.bGfx_outline_color = '\0');
    do {
        draw_rect_filled(0xd, 0xb, 0x126, 0x79);
        invui_blit_spr_ckey_dflt_size(sprite, x, y, -1, -1);
        if (flags != 0) {
            invui_status_icons_render(flags, x + g_nInvSelItemIconDx + 1,
                                      y + g_nInvSelItemIconDy + 1);
        }
        screen_frame_present();
        if ((dx = dst_x - x) != 0) {
            if (dx > 0) {
                x += dx / 0xc + 1;
            } else {
                x += dx / 0xc - 1;
            }
        }
        if ((dy = dst_y - y) != 0) {
            if (dy > 0) {
                y += dy / 0xc + 1;
            } else {
                y += dy / 0xc - 1;
            }
        }
    } while ((dx != 0) || (dy != 0));
    draw_rect_filled(0xd, 0xb, 0x126, 0x79);
    invui_blit_spr_ckey_dflt_size(sprite, x, y, -1, -1);
    if (flags != 0) {
        invui_status_icons_render(flags, x + g_nInvSelItemIconDx + 1, y + g_nInvSelItemIconDy + 1);
    }
    screen_frame_present();
    return;
}

static void far invinspect_render_details(ItemSlot far *item, int affecting) {
    ItemRecord far *irec;
    DDXRecord far *dlg;
    int frameRect[4];
    char buf[80];
    register int x;
    register int y;

    x = 0x8c;
    y = 0x1e;

    irec = itemtbl_record_ptr(item);
    dlg = dialog_load_record_by_key(0x1b7768UL, 0);

    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bGfx_fill_color = g_graphics_context.bGfx_outline_color = 0;
    draw_rect_filled(0x16, 0x72, 0x4a, 0xd);

    dialog_apply_style_state(dlg, (void far *)frameRect);
    dialog_frame_draw(dlg, (int far *)frameRect);
    dialog_freemem_if_not_null((unsigned char far *)dlg);

    if ((irec->wCategory == 1) || (irec->wCategory == 3)) {
        x = 0x73;
        y += (irec->wCategory == 3) * 10;
        invui_draw_text_aligned_shadow((char far *)"Thrust", x + 0x55, y, 1, 0, 0xb);
        invui_draw_text_aligned_shadow((char far *)"Swing", x + 0x96, y, 1, 0, 0xb);
        invui_draw_text_aligned_shadow((char far *)"________", x + 0x55, y + 3, 1, 0, 0xb);
        invui_draw_text_aligned_shadow((char far *)"________", x + 0x96, y + 3, 1, 0, 0xb);
        y += 0xf;
        invui_draw_text_aligned_shadow((char far *)"Base Dmg:", x, y, 0, 0, 0xb);
        sprintf(buf, "%d+Strength", irec->nThrust_damage);
        invui_draw_text_aligned_shadow((char far *)buf, x + 0x55, y, 1, -1, -1);
        sprintf(buf, "%d+Strength", irec->nSwing_damage);
        invui_draw_text_aligned_shadow((char far *)buf, x + 0x96, y, 1, -1, -1);
        y += 0xa;
        invui_draw_text_aligned_shadow((char far *)"Accuracy:", x, y, 0, 0, 0xb);
        sprintf(buf, "%d+Skill", irec->nAttack_or_range_long);
        invui_draw_text_aligned_shadow((char far *)buf, x + 0x55, y, 1, -1, -1);
        sprintf(buf, "%d+Skill", irec->nDefense_or_range_close);
        invui_draw_text_aligned_shadow((char far *)buf, x + 0x96, y, 1, -1, -1);
    } else {
        if ((irec->wCategory == 2) || ((item->item_id >= 0x24) && (item->item_id <= 0x2b))) {
            y += 0x19;
            invui_draw_text_aligned_shadow((char far *)"Base Damage:", x, y, 0, 0, 0xb);
            sprintf(buf, "%d+%s", irec->nSwing_damage,
                    irec->wCategory == 2 ? "Quarrel" : "CrossBow");
            invui_draw_text_aligned_shadow((char far *)buf, x + 0x46, y, 0, -1, -1);
            y += 0xa;
            invui_draw_text_aligned_shadow((char far *)"Accuracy:", x, y, 0, 0, 0xb);
            sprintf(buf, "%d+%s+Skill", irec->nDefense_or_range_close,
                    irec->wCategory == 2 ? "Quarrel" : "CrossBow");
        } else {
            if (irec->wCategory != 4)
                goto LAB_5a82_079b;
            x += 0xf;
            y += 0xf;
            invui_draw_text_aligned_shadow((char far *)"Armor Mod:", x, y, 0, 0, 0xb);
            sprintf(buf, "%d%%", irec->nDefense_or_range_close);
        }
        invui_draw_text_aligned_shadow((char far *)buf, x + 0x46, y, 0, -1, -1);
    }
    y += 10;

LAB_5a82_079b:
    if ((irec->wCategory == 1) || (irec->wCategory == 4)) {
        y += 6;
        invui_draw_text_aligned_shadow(
            (char far *)(irec->wCategory == 1 ? "Active Mods:" : "Resistances:"), x, y, 0, 0, 0xb);

        sprintf(buf, "%s%s%s%s%s%s%s", (item->flags & 0x1f80) ? "" : "None",
                (item->flags & 0x80) ? "Poisoned " : "", (item->flags & 0x400) ? "Frosted " : "",
                (item->flags & 0x100) ? "Flaming " : "", (item->flags & 0x200) ? "Steelfired " : "",
                (item->flags & 0x800) ? "Enhanced" : "", (item->flags & 0x1000) ? "Enhanced" : "");
        invui_draw_text_aligned_shadow((char far *)buf, x + 0x46, y, 0, -1, -1);

        y += 0xa;
        invui_draw_text_aligned_shadow((char far *)"Bless Type:", x, y, 0, 0, 0xb);

        sprintf(buf, "%s%s%s%s", (item->flags & 0xe000) ? "" : "None",
                (item->flags & 0x2000) ? "#1 (+5%)" : "", (item->flags & 0x4000) ? "#2 (+10%)" : "",
                (item->flags & 0x8000) ? "#3 (+15%)" : "");
        invui_draw_text_aligned_shadow((char far *)buf, x + 0x46, y, 0, -1, -1);
        y += 0xa;
    }

    if (irec->wRace_mask != 0) {
        y += 6;
        invui_draw_text_aligned_shadow((char far *)"Racial Mod:", x, y, 0, 0, 0xb);
        sprintf(buf, "%s",
                irec->wRace_mask == 1   ? "Tsurani"
                : irec->wRace_mask == 2 ? "Elf"
                : irec->wRace_mask == 4 ? "Dwarf"
                                        : "Human");
        invui_draw_text_aligned_shadow((char far *)buf, x + 0x46, y, 0, -1, -1);
        y += 0xa;
    }

    if (irec->wPlayer_stat_mask != 0) {
        y += 6;
        sprintf(buf, "%s player statistics", affecting != 0 ? "Affecting" : "Can affect");
        invui_draw_text_aligned_shadow((char far *)buf, x, y, 0, -1, -1);
        y += 0xa;
    }

    if (y != 0x1e) {
        screen_frame_present();
        screen_frame_sync_buffers_rect(0xb, 0x79);
        dialog_input_wait_release(1, 0);
        while (dialog_poll_arrow_or_button() == 0) {
            screen_frame_present();
        }
    }
    return;
}

void far invinspect_item_flow(ItemSlot far *item, int affecting, MenuPage *page) {
    ImageRecord *sprite;
    unsigned int action;
    int dstX;
    int dstY;
    ItemRecord far *irec;
    MenuEntry *savedEntries;
    unsigned short savedCount;
    unsigned short dirty;
    char buf[80];

    irec = itemtbl_record_ptr(item);
    sprite = invui_item_sprite_select(item);
    dstX = 0x3a - sprite->nWidth / 2;
    dstY = 0x47 - sprite->nHeight / 2;
    invinspect_animate_item_move(sprite, g_nInvSelItemAnchorX, g_nInvSelItemAnchorY, dstX, dstY,
                                 item->flags);

    if (irec->wName_split_off != 0) {
        irec->pName[irec->wName_split_off] = '\0';
        invui_draw_text_aligned_shadow((char far *)irec, 0x3a, 0xf, 1, -1, -1);
        invui_draw_text_aligned_shadow((char far *)(irec->pName + (irec->wName_split_off + 1)),
                                       0x3a, 0x19, 1, -1, -1);
        irec->pName[irec->wName_split_off] = ' ';
    } else {
        invui_draw_text_aligned_shadow((char far *)irec, 0x3a, 0x19, 1, -1, -1);
    }

    if (((irec->wFlags & 0x8000) != 0) || (irec->wCategory == 7)) {
        sprintf(buf, "Amount: %d", (unsigned int)item->condition);
        invui_draw_text_aligned_shadow((char far *)buf, 0x3a, 0x23, 1, -1, -1);
    } else if (((irec->wFlags & 0x2000) != 0) && (irec->wCategory != 0x11)) {
        sprintf(buf, "Uses left: %d", (unsigned int)item->condition);
        invui_draw_text_aligned_shadow((char far *)buf, 0x3a, 0x23, 1, -1, -1);
    } else if (((irec->wFlags & 0x1000) != 0) && ((irec->wSub_flags & 4) != 0)) {
        sprintf(buf, "Value Rating: %d%", (unsigned int)item->condition);
        invui_draw_text_aligned_shadow((char far *)buf, 0x3a, 0x23, 1, -1, -1);
    } else if ((irec->wFlags & 0x1000) != 0) {
        sprintf(buf, "Condition: %d%%", (unsigned int)item->condition);
        invui_draw_text_aligned_shadow((char far *)buf, 0x3a, 0x23, 1, -1, -1);
    }

    buf[0] = '\0';
    if (affecting != 0) {
        if (((item->flags & 0x40) != 0) || (irec->wPlayer_stat_mask != 0)) {
            strcpy(buf, "Using");
            if ((item->flags & 0x30) != 0) {
                strcat(buf, ", ");
            }
        }
    }

    if ((item->flags & 0x10) != 0) {
        strcat(buf, "Broken");
    } else if ((item->flags & 0x20) != 0) {
        strcat(buf, "Repairable");
    }

    invui_draw_text_aligned_shadow((char far *)buf, 0x3b, 0x65, 1, -1, -1);
    screen_frame_present();
    screen_frame_sync_buffers_rect(0xb, 0x79);

    if (item->item_id == 0x85) {
        g_gameState.nEvtArgCount = (short)item->condition;
        dialog_play_record(0x1b7761UL, 0);
    } else {
        g_gameState.nEvtArgCount = (short)item->item_id;
        dialog_play_record(0x1b7741UL, 0);
        dialog_input_wait_release(1, 1);
        if (page != (MenuPage *)0) {
            if ((((irec->wCategory != 0) && ((int)irec->wCategory <= 4)) ||
                 ((item->item_id >= 0x24) && (item->item_id <= 0x2b))) ||
                (irec->wPlayer_stat_mask != 0)) {
                savedEntries = page->pEntries;
                savedCount = page->wEntry_count;

                page->pEntries = savedEntries + 0x23;
                page->wEntry_count = 2;
                do {
                    menupage_draw(page);
                    screen_frame_present();
                } while ((action = menupage_run(page, &dirty)) == 0);
                page->pEntries = savedEntries;
                page->wEntry_count = savedCount;
                if ((action == 0x39) || (action == 0x32)) {
                    invinspect_render_details(item, affecting);
                }
                goto LAB_5a82_0d2c;
            }
        }
        while (dialog_poll_arrow_or_button() == 0) {
            screen_frame_present();
        }
    }

LAB_5a82_0d2c:
    invinspect_animate_item_move(sprite, dstX, dstY, g_nInvSelItemAnchorX, g_nInvSelItemAnchorY,
                                 item->flags);
    return;
}
