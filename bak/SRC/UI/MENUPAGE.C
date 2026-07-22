#include "globals.h"
#include "structs.h"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/WIDGET.H"
#include "SRC/UI/UIWIDGET.H"

MenuEntry *g_pMenuHoverEntry;
MenuEntry *g_pMenuPressAnchor;
MenuEntry *g_pMenuClickedEntry;
unsigned short g_wMenuDragSubMode;
unsigned short g_wMenuDragState;

short g_nJoyXVel = 0;
short g_nJoyYVel = 0;

MenuPage *menupage_load(char *filename) {
    BakFile *stream;
    MenuPage *page;
    int i;
    void *stringBlob;
    unsigned int blobSize;

    stringBlob = (void *)0;
    stream = bak_fopen(filename, "rb");
    page = galloc_safe_zcalloc(0x1c);
    bak_fread(page, 0x1c, 1, stream);
    bak_fread(&page->wEntry_count, 2, 1, stream);
    page->pEntries = galloc_safe_zcalloc(page->wEntry_count * 0x21);
    bak_fread(page->pEntries, 0x21, page->wEntry_count, stream);
    bak_fread(&blobSize, 2, 1, stream);
    if (blobSize != 0) {
        stringBlob = galloc_safe_zcalloc(blobSize);
        bak_fread(stringBlob, 1, blobSize, stream);
    }
    if ((int)page->pTitle == -1) {
        page->pTitle = (char *)0;
    } else {
        page->pTitle += (int)stringBlob;
    }
    for (i = 0; i < (int)page->wEntry_count; i++) {
        if ((int)page->pEntries[i].pLabel == -1) {
            page->pEntries[i].pLabel = (char *)0;
        } else {
            page->pEntries[i].pLabel += (int)stringBlob;
        }
        if ((int)page->pEntries[i].pPrimary_label == -1) {
            page->pEntries[i].pPrimary_label = (char *)0;
        } else {
            page->pEntries[i].pPrimary_label += (int)stringBlob;
        }
        if ((int)page->pEntries[i].pAlt_label == -1) {
            page->pEntries[i].pAlt_label = (char *)0;
        } else {
            page->pEntries[i].pAlt_label += (int)stringBlob;
        }
    }
    bak_fclose(stream);
    return page;
}

void menupage_free(MenuPage *page) {
    char *blobBase;
    int i;

    blobBase = page->pTitle;
    for (i = 0; i < (int)page->wEntry_count; i++) {
        if ((page->pEntries[i].pLabel != (char *)0x0) &&
            ((blobBase == (char *)0x0 || (page->pEntries[i].pLabel < blobBase)))) {
            blobBase = page->pEntries[i].pLabel;
        }
        if ((page->pEntries[i].pPrimary_label != (char *)0x0) &&
            ((blobBase == (char *)0x0 || (page->pEntries[i].pPrimary_label < blobBase)))) {
            blobBase = page->pEntries[i].pPrimary_label;
        }
        if ((page->pEntries[i].pAlt_label != (char *)0x0) &&
            ((blobBase == (char *)0x0 || (page->pEntries[i].pAlt_label < blobBase)))) {
            blobBase = page->pEntries[i].pAlt_label;
        }
    }
    if (blobBase != (char *)0x0) {
        galloc_zfree(blobBase);
    }
    galloc_zfree(page->pEntries);
    galloc_zfree(page);
    return;
}

void menupage_begin(MenuPage *page) {
    int nSize;

    if (page->wWants_screen_save == 1) {
        nSize = (int)rect_byte_size(page->rect.width, page->rect.height);
        page->pBackdrop_buffer = alloc_far((long)nSize, 0);
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;
        cga_save_rect_to_buffer(page->pBackdrop_buffer, page->rect.x, page->rect.y,
                                page->rect.width, page->rect.height);
    }
    g_pMenuHoverEntry = (MenuEntry *)0;
    g_pMenuPressAnchor = (MenuEntry *)0;
    g_pMenuClickedEntry = (MenuEntry *)0;
    g_wMenuDragSubMode = 0;
    g_wMenuDragState = 0;
}

void menupage_end(MenuPage *page) {
    if (page->wWants_screen_save == 1) {
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        cga_rect_paste_from_buffer(page->pBackdrop_buffer, page->rect.x, page->rect.y,
                                   page->rect.width, page->rect.height);
        screen_frame_present();
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        cga_rect_paste_from_buffer(page->pBackdrop_buffer, page->rect.x, page->rect.y,
                                   page->rect.width, page->rect.height);
        screen_frame_present();
        _freemem(page->pBackdrop_buffer);
    }
    g_pMenuHoverEntry = (MenuEntry *)0;
    g_pMenuPressAnchor = (MenuEntry *)0;
    g_pMenuClickedEntry = (MenuEntry *)0;
    g_wMenuDragSubMode = 0;
    g_wMenuDragState = 0;
}

void menupage_draw(MenuPage *page) {
    unsigned short bgColor;

    bgColor = page->wBg_color;
    g_graphics_context.bClip_enabled = 0;
    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bText_style_flags = 1;
    if (page->wVisible != 0) {
        if (bgColor == 0xa9) {
            uiwidget_panel_inset_inverted(page->rect.x, page->rect.y, page->rect.width,
                                          page->rect.height, 0);
        } else {
            uiwidget_panel_draw_3edge_bevel(page->rect.x, page->rect.y, page->rect.width,
                                            page->rect.height, bgColor + 3, bgColor, bgColor + 2,
                                            bgColor + 4, bgColor + 6);
        }
        if (page->pTitle != (char *)0x0) {
            if (bgColor == 0xa9) {
                uiwidget_draw_text_shadowed(page->pTitle, 0x33, 1, page->rect.x + page->nTitle_x,
                                            page->rect.y + page->nTitle_y);
            } else {
                uiwidget_draw_text_shadowed_dflt(page->pTitle, 0xffff, -1,
                                                 page->rect.x + page->nTitle_x,
                                                 page->rect.y + page->nTitle_y);
            }
        }
    }
    menupage_draw_entries(page->pEntries, page->wEntry_count, page->rect.x, page->rect.y);
}

void far menupage_draw_entries(MenuEntry *first, int count, int x, int y) {
    int i;

    for (i = 0; i < count; i++, first++) {
        widget_dispatch_by_type(first, x, y,
                                (first == g_pMenuPressAnchor) ? g_wMenuDragSubMode : 0);
    }
    return;
}

void menupage_cur_set_pos_clamped(int x, int y) {
    if (x < 0) {
        x = 0;
    }
    if (y < 0) {
        y = 0;
    }

    if (0x13f < x) {
        x = 0x13f;
    }
    if (199 < y) {
        y = 199;
    }
    screen_cursor_set_position(x, y);
    return;
}

void menupage_cursor_joystick_step(void) {
    unsigned int state;

    state = key_state_get_via_2cf8_table(0);
    if (state & 4) {
        g_nJoyXVel = (g_nJoyXVel <= 0) ? g_nJoyXVel + -2 : -1;
    } else {
        if (state & 8) {
            g_nJoyXVel = (g_nJoyXVel >= 0) ? g_nJoyXVel + 2 : 1;
        } else {
            g_nJoyXVel = 0;
        }
    }
    if (state & 1) {
        g_nJoyYVel = (g_nJoyYVel <= 0) ? g_nJoyYVel + -2 : -1;
    } else {
        if (state & 2) {
            g_nJoyYVel = (g_nJoyYVel >= 0) ? g_nJoyYVel + 2 : 1;
        } else {
            g_nJoyYVel = 0;
        }
    }
    if ((g_nJoyXVel != 0) || (g_nJoyYVel != 0)) {
        menupage_cur_set_pos_clamped(screen_cursor_get_x() + g_nJoyXVel,
                                     screen_cursor_get_y() + g_nJoyYVel);
    }
    return;
}

void menupage_navigate(MenuPage *page, int dx_sign, int dy_sign, int tab_mode) {
    int chosen;
    int count;
    short cur_x;
    short cur_y;
    int dist_x;
    int sign_x;
    int sign_y;
    int best_x;
    int best_y;
    int enabled;
    int idx;
    int i;
    int dist_y;
    int neg;
    MenuEntry *entry;

    chosen = -1;
    count = page->wEntry_count;
    if (g_pMenuHoverEntry != (MenuEntry *)0x0) {
        cur_x = g_pMenuHoverEntry->rect.x;
    } else {
        cur_x = screen_cursor_get_x();
    }
    if (g_pMenuHoverEntry != (MenuEntry *)0x0) {
        cur_y = g_pMenuHoverEntry->rect.y;
    } else {
        cur_y = screen_cursor_get_y();
    }
    /* 0x270f 9999 = "infinite" nearest-widget distance sentinel (running-min seed) */
    best_x = 9999;
    best_y = 9999;
    entry = page->pEntries;
    if (tab_mode != 0) {
        idx = 0;
        if (g_pMenuHoverEntry == (MenuEntry *)0x0) {
            idx = (g_key_shift_held != 0) ? 0 : count - 1;
        }
        i = enabled = 0;
        if (i < count) {
            do {
                if (entry->wEnable_gate == 0) {
                    enabled++;
                    if (entry == g_pMenuHoverEntry) {
                        idx = i;
                    }
                }
                i++;
                entry++;
            } while (i < count);
        }
        while ((enabled != 0) && (chosen < 0)) {
            idx = ((g_key_shift_held != 0) ? idx - 1 : idx + 1) % count;
            if (idx < 0) {
                idx = count - 1;
            }
            if (page->pEntries[idx].wEnable_gate == 0) {
                chosen = idx;
            }
        }
    } else {
        for (i = 0; i < count; i++, entry++) {
            if (entry->wEnable_gate == 0) {
                dist_x = entry->rect.x - cur_x;
                dist_y = entry->rect.y - cur_y;
                sign_x = (0 < dist_x) ? 1 : ((dist_x == 0) ? 0 : -1);
                sign_y = (0 < dist_y) ? 1 : ((dist_y == 0) ? 0 : -1);
                if (dist_x < 0) {
                    neg = -1;
                    dist_x = dist_x * neg;
                }
                if (dist_y < 0) {
                    neg = -1;
                    dist_y = dist_y * neg;
                }
                if ((dx_sign != 0) && (dx_sign == sign_x)) {
                    if ((dist_y < best_y) || ((dist_y == best_y) && (dist_x < best_x))) {
                        best_y = dist_y;
                        best_x = dist_x;
                        chosen = i;
                    }
                } else if (((dy_sign != 0) && (dy_sign == sign_y)) &&
                           ((dist_x < best_x) || ((dist_x == best_x) && (dist_y < best_y)))) {
                    best_x = dist_x;
                    best_y = dist_y;
                    chosen = i;
                }
            }
        }
    }
    if (chosen != -1) {
        entry = page->pEntries + chosen;
        menupage_cur_set_pos_clamped(page->rect.x + entry->rect.x + (entry->rect.width >> 1),
                                     page->rect.y + entry->rect.y + (entry->rect.height >> 1));
    }
    return;
}

int menupage_run(MenuPage *page, unsigned short *out_consumed) {
    int i;
    unsigned int key;
    MenuEntry *entry;

    i = 0;
    entry = page->pEntries;
    key = menupage_input_poll(page, out_consumed);
    if ((g_dwDialogInputCooldown != 0) && (g_timer_ticks > g_dwDialogInputCooldown)) {
        g_dwDialogInputCooldown = 0;
    }
    if (key == 0) {
        if ((((g_pMenuPressAnchor != (MenuEntry *)0x0) && (g_wMenuDragState == 1)) &&
             (g_pMenuPressAnchor->wWidget_type == 2)) &&
            (g_wMenuDragSubMode == 3)) {
            unsigned short sub_state;
            sub_state = g_pMenuPressAnchor->wSub_state;
            widget_scrollbar_update(g_pMenuPressAnchor);
            if (g_pMenuPressAnchor->wSub_state != sub_state) {
                *out_consumed = 1;
                return g_pMenuPressAnchor->wAction_id;
            }
            return 0;
        }
        if (menupage_input_poll_key() == 0) {
            return 0;
        }
        key = (unsigned int)g_key_scancode;
        /* ENTER (scancode 0x1c) is already mapped to a confirm-click by
         * menupage_input_poll when wWants_screen_save != 2; whatever special
         * ENTER handling once lived here was stubbed out. */
        if ((key == 0x1c) && (page->wWants_screen_save != 2)) {
        }
        for (; i < (int)page->wEntry_count; i++, entry++) {
            if (entry->wAction_id == key) {
                if ((entry->wEnable_gate != 0) &&
                    ((((entry->wWidget_type == 6 || (entry->wWidget_type == 0)) ||
                       ((entry->wWidget_type == 3 ||
                         ((entry->wWidget_type == 1 || (entry->wWidget_type == 4)))))) ||
                      (entry->wWidget_type == 7)))) {
                    key = 0;
                    break;
                }
                g_pMenuClickedEntry = entry;
                g_wMenuDragState = 1;
                if (g_pMenuClickedEntry->wWidget_type == 2) {
                    if (key_is_down(0x2a) || key_is_down(0x36)) {
                        g_wMenuDragSubMode = 2;
                    } else {
                        g_wMenuDragSubMode = 4;
                    }
                    *out_consumed = 1;
                } else {
                    g_wMenuDragSubMode = 1;
                }
                *out_consumed = 1;
            }
        }
    }
    if ((g_pMenuClickedEntry != (MenuEntry *)0x0) && (g_wMenuDragState == 1)) {
        if ((g_pMenuClickedEntry->wWidget_type == 1) || (g_pMenuClickedEntry->wWidget_type == 4)) {
            widget_toggle_state(g_pMenuClickedEntry);
        } else if (g_pMenuClickedEntry->wWidget_type == 2) {
            if (g_wMenuDragSubMode == 2) {
                widget_list_scroll(g_pMenuClickedEntry, 1);
            } else if (g_wMenuDragSubMode == 4) {
                widget_list_scroll(g_pMenuClickedEntry, 0);
            } else if (g_wMenuDragSubMode == 3) {
                unsigned short sub_state;
                sub_state = g_pMenuClickedEntry->wSub_state;
                widget_scrollbar_update(g_pMenuClickedEntry);
                if (g_pMenuPressAnchor->wSub_state != sub_state) {
                    *out_consumed = 1;
                }
            }
        }
    }
    if ((((key != 0x4d) && (key != 0x4b)) && (key != 0x48)) && ((key != 0x50) && (key != 0xf))) {
        return key;
    }
    g_key_ascii = '\0';
    if (key_is_down(0x38) != 0) {
        if (key == 0xf) {
            menupage_navigate(page, 0, 0, 1);
        } else {
            menupage_cursor_joystick_step();
        }
    } else {
        if ((page->wWants_screen_save == 2) && (key_is_down(0x1d) == 0)) {
            return key;
        }
        menupage_navigate(page, (unsigned int)(key == 0x4d) - (unsigned int)(key == 0x4b),
                          (unsigned int)(key == 0x50) - (unsigned int)(key == 0x48), (unsigned int)(key == 0xf));
    }
    g_key_scancode = key = 0;
    return key;
}

int far menupage_input_poll(MenuPage *page, unsigned short *out_consumed) {
    register unsigned short *pConsumed;
    int actionId;
    int relX;
    int relY;
    int i;
    unsigned short prevDragState;
    int input;
    MenuEntry *prevAnchor;
    register MenuEntry *widget;

    pConsumed = out_consumed;
    actionId = 0;
    i = 0;
    prevDragState = g_wMenuDragState;
    widget = page->pEntries;
    prevAnchor = g_pMenuPressAnchor;
    *pConsumed = 0;
    relX = screen_cursor_get_x() - page->rect.x;
    relY = screen_cursor_get_y() - page->rect.y;
    g_pMenuHoverEntry = 0;
    g_pMenuPressAnchor = 0;
    g_pMenuClickedEntry = 0;
    g_wMenuDragSubMode = 0;
    g_wMenuDragState = 0;
    input = screen_input_poll_confirm_cancel();
    if (page->wWants_screen_save != 2 && key_is_down(0x1c))
        input = 1;
    while ((int)page->wEntry_count > i) {
        if (widget->wEnable_gate == 0) {
            if (widget->wWidget_type != 2)
                goto do_hit_test;
        }
        if (widget->wWidget_type != 2)
            goto do_skip;
    do_hit_test:
        if (widget_hit_test(widget, relX, relY, (int *)&g_wMenuDragSubMode)) {
            g_pMenuHoverEntry = widget;
            goto post_loop;
        }
    do_skip:
        i++;
        widget++;
    }
post_loop:
    if (g_pMenuHoverEntry != 0)
        screen_cursor_set_shape(widget->wCursor_shape);
    else
        screen_cursor_set_shape(-1);
    if (g_pMenuHoverEntry == 0)
        goto hover_null;
    if (input == 0)
        goto input_zero;
    if (input == (int)prevDragState) {
        if (g_pMenuHoverEntry != prevAnchor)
            *pConsumed = 1;
        g_pMenuPressAnchor = g_pMenuHoverEntry;
        g_wMenuDragState = input;
        goto action_check;
    }
    if (prevDragState != 0) {
        *pConsumed = 1;
        g_pMenuClickedEntry = g_pMenuHoverEntry;
        g_wMenuDragState = prevDragState;
        if (!(g_pMenuClickedEntry->wClick_flags & 2)) {
            if (g_pMenuClickedEntry->wClick_sfx_id != 0)
                audio_play(g_pMenuClickedEntry->wClick_sfx_id);
            else
                audio_play(0x53);
        }
        goto action_check;
    }
    *pConsumed = 1;
    g_pMenuPressAnchor = g_pMenuHoverEntry;
    g_wMenuDragState = input;
    if (!(g_pMenuPressAnchor->wClick_flags & 1)) {
        if (g_pMenuPressAnchor->wClick_sfx_id != 0)
            audio_play(g_pMenuPressAnchor->wClick_sfx_id);
        else
            audio_play(0x53);
    }
    goto action_check;
input_zero:
    if (prevAnchor == 0)
        goto action_check;
    if (prevAnchor != g_pMenuHoverEntry)
        goto action_check;
    *pConsumed = 1;
    g_pMenuClickedEntry = g_pMenuHoverEntry;
    g_wMenuDragState = prevDragState;
    if (!(g_pMenuClickedEntry->wClick_flags & 2)) {
        if (g_pMenuClickedEntry->wClick_sfx_id != 0)
            audio_play(g_pMenuClickedEntry->wClick_sfx_id);
        else
            audio_play(0x53);
    }
action_check:
    if (g_pMenuClickedEntry == 0)
        goto past_hover;
    actionId = g_pMenuClickedEntry->wAction_id;
    goto past_hover;
hover_null:
    if (prevAnchor != 0)
        *pConsumed = 1;
past_hover:
    return actionId;
}

MenuEntry *menupage_state_0e84(void) {
    return g_pMenuHoverEntry;
}

MenuEntry *menupage_focused_entry(void) {
    return g_pMenuPressAnchor;
}

MenuEntry *menupage_state_0e80(void) {
    return g_pMenuClickedEntry;
}

unsigned int menupage_highlight_color(void) {
    return g_wMenuDragSubMode;
}

unsigned int menupage_state_0e7c(void) {
    return g_wMenuDragState;
}

unsigned int menupage_input_poll_key(void) {
    int key;

    key = kbhit_read();
    if (key != 0) {
        g_key_held = (unsigned char)key_is_down(g_key_scancode = (unsigned char)(key >> 8));
        g_key_shift_held = key_is_down(0x2a) || key_is_down(0x36);
        g_key_ascii = key & 0xff;
    } else {
        g_key_scancode = 0;
    }
    return key;
}
