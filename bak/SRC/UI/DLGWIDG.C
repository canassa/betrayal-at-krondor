#include "SRC/GEN/GFXCTX.H"
#include "SRC/SYS/SYSLOWIO.H"
#include "structs.h"
#include "SRC/UI/DLGWIDG.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/GFX/RASTER/DRAWLINE.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"

unsigned char g_key_scancode;
unsigned char g_key_ascii;
unsigned char g_key_held;
unsigned char g_key_shift_held;

short g_text_input_drag_anchor = -1;
int g_nCursorBlinkOn = 0;
unsigned long g_dwCursorBlinkPhaseStart = 0x00000000UL;

Dialog *dlgwidget_dialog_load(char *filename) {
    IoFile *stream;
    Dialog *dialog;
    DialogWidget *widget;
    void *string_table;
    short label_offset;
    unsigned short widget_count;
    unsigned int capacity;
    short rect_x;
    short rect_y;
    short rect_w;
    unsigned short label_x;
    unsigned short label_y;
    int has_fill_image;
    unsigned char bg_color;
    unsigned char fg_color;
    unsigned char cursor_color;
    unsigned char label_fg;
    unsigned char selection_color;
    int i;

    string_table = (void *)0x0;
    stream = bak_fopen(filename, "rb");
    bak_fread(&widget_count, 2, 1, stream);
    if (widget_count != 0) {
        string_table = galloc_safe_zcalloc(widget_count);
        bak_fread(string_table, 1, widget_count, stream);
    }
    bak_fread(&widget_count, 2, 1, stream);
    dialog = dlgwidget_dialog_create(widget_count);
    for (i = 0; i < (int)widget_count; i++) {
        bak_fread(&capacity, 2, 1, stream);
        bak_fread(&rect_x, 2, 1, stream);
        bak_fread(&rect_y, 2, 1, stream);
        bak_fread(&rect_w, 2, 1, stream);
        bak_fread(&bg_color, 1, 1, stream);
        bak_fread(&fg_color, 1, 1, stream);
        bak_fread(&cursor_color, 1, 1, stream);
        bak_fread(&label_fg, 1, 1, stream);
        bak_fread(&selection_color, 1, 1, stream);
        bak_fread(&label_offset, 2, 1, stream);
        bak_fread(&label_x, 2, 1, stream);
        bak_fread(&label_y, 2, 1, stream);
        bak_fread(&has_fill_image, 2, 1, stream);
        if (label_offset == -1) {
            label_offset = 0;
        } else {
            label_offset += (int)string_table;
        }
        widget = dlgwidget_create(capacity, rect_x, rect_y, rect_w, bg_color, fg_color,
                                  cursor_color, label_fg, selection_color, has_fill_image);
        dlgwidget_dialog_add_widget(dialog, widget, (char *)0x0, (char *)label_offset, label_x,
                                    label_y);
    }
    bak_fclose(stream);
    return dialog;
}

void dlgwidget_dialog_destroy_bgs(Dialog *dialog) {
    int i;
    char *lowestLabel;

    lowestLabel = (*dialog->pWidgets)->pLabel;
    for (i = 1; i < dialog->nWidget_count; i = i + 1) {
        if ((dialog->pWidgets[i]->pLabel != (char *)0x0) &&
            ((lowestLabel == (char *)0x0 || (dialog->pWidgets[i]->pLabel < lowestLabel)))) {
            lowestLabel = dialog->pWidgets[i]->pLabel;
        }
    }
    dlgwidget_dialog_destroy(dialog);
    if (lowestLabel != (char *)0x0) {
        galloc_zfree(lowestLabel);
    }
    return;
}

Dialog *dlgwidget_dialog_create(int capacity) {
    Dialog *pDialog;

    pDialog = galloc_safe_zcalloc(8);
    pDialog->pWidgets = galloc_safe_zcalloc(capacity << 1);
    pDialog->nWidget_capacity = capacity;
    pDialog->nWidget_count = 0;
    pDialog->nFocused_idx = -1;
    return pDialog;
}

void dlgwidget_dialog_destroy(Dialog *dialog) {
    int i;

    i = dialog->nWidget_count - 1;
    while (i >= 0) {
        dlgwidget_destroy(dialog->pWidgets[i]);
        i--;
    }
    galloc_zfree(dialog->pWidgets);
    galloc_zfree(dialog);
    return;
}

int dlgwidget_dialog_add_widget(Dialog *dialog, DialogWidget *widget, char *label_text, char *label,
                                short label_x, short label_y) {
    if (dialog->nWidget_count < dialog->nWidget_capacity) {
        dialog->pWidgets[dialog->nWidget_count++] = widget;
        dialog->nFocused_idx = 0;
        dlgwidget_set_text(widget, label_text);
        dlgwidget_set_label_pos(widget, label, label_x, label_y);
        return 1;
    }
    return 0;
}

void far dlgwidget_dialog_set_widget_text(Dialog *dialog, int widget_index, char *text) {
    if (widget_index < dialog->nWidget_count) {
        dlgwidget_set_text(dialog->pWidgets[widget_index], text);
    }
    return;
}

int dlgwidget_dialog_focus_widget(Dialog *dialog, int widget_idx) {
    if (widget_idx < dialog->nWidget_count) {
        dialog->nFocused_idx = widget_idx;
        dialog->pWidgets[widget_idx]->nCursor = 0;
        dialog->pWidgets[widget_idx]->nFull_length = dialog->pWidgets[widget_idx]->nLength;
        return 1;
    }
    return 0;
}

char *dlgwidget_dialog_widget_text_ptr(Dialog *dialog, int widget_idx) {
    return (widget_idx < dialog->nWidget_count) ? dialog->pWidgets[widget_idx]->pText_buf
                                                : (char *)0x0;
}

void dlgwidget_dlg_capture_bgs(Dialog *dialog) {
    int i;

    for (i = 0; i < dialog->nWidget_count; i = i + 1) {
        dlgwidget_capture_background(dialog->pWidgets[i]);
    }
    return;
}

void dlgwidget_dlg_focus_first_wdg(Dialog *dialog) {
    DialogWidget *widget;

    widget = *dialog->pWidgets;
    g_text_input_drag_anchor = -1;
    dialog->nFocused_idx = 0;
    widget->nCursor = 0;
    widget->nFull_length = widget->nLength;
    return;
}

int dlgwidget_text_input_dialog_pump(Dialog *pDialog) {
    DialogWidget **widgets;
    char ch;
    short x;
    short y;
    int char_idx;
    DialogWidget *widget;
    int i;

    widget = pDialog->pWidgets[pDialog->nFocused_idx];
    widgets = pDialog->pWidgets;
    x = screen_cursor_get_x();
    y = screen_cursor_get_y();
    char_idx = dlgwidget_text_char_at_point(widget, x, y);
    if (char_idx >= 0) {
        switch (screen_input_poll_confirm_cancel()) {
        case 2:
            g_text_input_drag_anchor = -1;
            widget->nCursor = 0;
            widget->nFull_length = widget->nLength;
            break;
        case 1: {
            int ci;
            if (g_text_input_drag_anchor < 0) {
                ci = g_text_input_drag_anchor = char_idx;
            } else {
                ci = char_idx;
            }
            if (ci < g_text_input_drag_anchor) {
                widget->nCursor = ci;
                widget->nFull_length = g_text_input_drag_anchor;
                break;
            }
            widget->nCursor = g_text_input_drag_anchor;
            widget->nFull_length = ci;
            break;
        }
        default:
            g_text_input_drag_anchor = -1;
        }
    } else {
        if (screen_input_poll_confirm_cancel() == 0)
            goto L_keyboard;
        for (i = 0; i < pDialog->nWidget_count; i++) {
            if (pDialog->nFocused_idx != i && dlgwidget_text_char_at_point(widgets[i], x, y) >= 0) {
                g_text_input_drag_anchor = -1;
                widgets[i]->nCursor = widgets[i]->nFull_length = 0;
                pDialog->nFocused_idx = i;
                widget = widgets[i];
                break;
            }
        }
    }
L_keyboard:

    if ((ch = dlgwidget_text_input_disp_key()) != '\0') {
        switch (ch) {
        case 5:
            g_text_input_drag_anchor = -1;
            widget->nCursor = 0;
            widget->nFull_length = widget->nLength;
            dlgwidget_dialog_rstrip_widgets(pDialog);
            return 1;
        case 6:
            if (pDialog->nFocused_idx != 0)
                i = --pDialog->nFocused_idx;
            else
                i = pDialog->nFocused_idx = pDialog->nWidget_count - 1;
            widgets[i]->nCursor = 0;
            widgets[i]->nFull_length = widgets[i]->nLength;
            break;
        case 7:
            if (pDialog->nFocused_idx < pDialog->nWidget_count - 1)
                i = ++pDialog->nFocused_idx;
            else
                i = pDialog->nFocused_idx = 0;
            widgets[i]->nCursor = 0;
            widgets[i]->nFull_length = widgets[i]->nLength;
            break;
        case 1:
            dlgwidget_text_delete_or_bksp(widget);
            break;
        case 2:
            dlgwidget_text_extend_or_end(widget);
            break;
        case 3:
            dlgwidget_text_compact_delete(widget);
            break;
        case 4:
            dlgwidget_text_forward_delete(widget);
            break;
        case 8:
            dlgwidget_text_cursor_home(widget);
            break;
        case 9:
            dlgwidget_text_cursor_end(widget);
            break;
        default:
            dlgwidget_text_insert_char(widget, ch);
            g_text_input_drag_anchor = -1;
            return 0;
        }
        g_text_input_drag_anchor = -1;
    }
    return 0;
}

void dlgwidget_dialog_rstrip_widgets(Dialog *dialog) {
    DialogWidget **ppWidgets;
    char *pText;
    int i;
    int idx;

    ppWidgets = dialog->pWidgets;
    for (idx = 0; idx < dialog->nWidget_count; idx++) {
        pText = ppWidgets[idx]->pText_buf;
        for (i = ppWidgets[idx]->nLength - 1; i >= 0; i--) {
            if (pText[i] != ' ')
                break;
            pText[i] = '\0';
            ppWidgets[idx]->nLength--;
        }
    }
    return;
}

void dlgwidget_dialog_render(Dialog *dialog, int show_selection) {
    int i;

    if (show_selection != 0) {
        for (i = 0; i < dialog->nWidget_count; i = i + 1) {
            dlgwidget_draw_text_input_widget(dialog->pWidgets[i],
                                             (unsigned)(dialog->nFocused_idx == i));
        }
    } else {
        for (i = 0; i < dialog->nWidget_count; i = i + 1) {
            dlgwidget_draw_text_input_widget(dialog->pWidgets[i], 0);
        }
    }
}

DialogWidget *dlgwidget_create(unsigned int capacity, short rect_x, short rect_y, short rect_w,
                               unsigned char bg_color, unsigned char fg_color, unsigned char cursor_color, unsigned char label_fg,
                               unsigned char selection_color, int has_fill_image) {
    DialogWidget *w;

    w = (DialogWidget *)galloc_safe_zcalloc(0x21);
    w->pText_buf = (char *)galloc_safe_zcalloc(capacity);
    w->nCapacity = capacity;
    w->nLength = 0;
    w->nCursor = 0;
    w->nFull_length = 0;
    w->rect.x = rect_x;
    w->rect.y = rect_y;
    w->rect.width = rect_w;
    w->rect.height = g_graphics_context.pFont_height[0] + 5;
    w->bBg_color = bg_color;
    w->bFg_color = fg_color;
    w->bCursor_color = cursor_color;
    w->bLabel_fg = label_fg;
    w->bSelection_color = selection_color;
    if (has_fill_image != 0) {
        w->pFill_image =
            (unsigned char far *)alloc_far((unsigned long)(unsigned short)rect_byte_size(w->rect.width, w->rect.height), 0L);
    } else {
        w->pFill_image = (unsigned char far *)0x0;
    }
    w->pLabel = (char *)0x0;
    return w;
}

void dlgwidget_destroy(DialogWidget *widget) {

    if (*(int *)&widget->pFill_image | *((int *)&widget->pFill_image + 1)) {
        _freemem(widget->pFill_image);
    }
    galloc_zfree(widget->pText_buf);
    galloc_zfree(widget);
    return;
}

void far dlgwidget_set_text(DialogWidget *widget, char *text) {
    int cap_minus_1;
    int pixel_width;
    int glyph_w;
    int glyph_h;
    int threshold;
    int i;

    cap_minus_1 = widget->nCapacity - 1;
    i = 0;
    pixel_width = 0;
    threshold = widget->rect.width - 6;
    if (text != 0) {
        for (; text[i] != '\0' && i < cap_minus_1; i++) {
            font_glyph_metrics((int)text[i], &glyph_w, &glyph_h);
            pixel_width += glyph_w;
            if (pixel_width > threshold)
                break;
            widget->pText_buf[i] = text[i];
        }
        widget->nCursor = (widget->pText_buf[i] = '\0');
        widget->nFull_length = widget->nLength = i;
    }
}

void dlgwidget_set_label_pos(DialogWidget *widget, char *label, short label_x, short label_y) {
    widget->nLabel_x = label_x;
    widget->nLabel_y = label_y;
    widget->pLabel = label;
}

void dlgwidget_capture_background(DialogWidget *widget) {

    if (*(int *)&widget->pFill_image | *((int *)&widget->pFill_image + 1)) {
        cga_save_rect_to_buffer(widget->pFill_image, widget->rect.x, widget->rect.y,
                                widget->rect.width, widget->rect.height);
    }
}

int far dlgwidget_text_char_at_point(DialogWidget *widget, int x, int y) {
    char *text;
    int nlen;
    int w;
    int half_w;
    int running;
    int limit;
    int i;

    text = widget->pText_buf;
    i = 0;
    nlen = widget->nLength;
    running = 0;
    limit = widget->rect.width - 6;

    if (widget->rect.x <= x && widget->rect.x + widget->rect.width > x && widget->rect.y <= y &&
        widget->rect.y + widget->rect.height > y) {

        x -= widget->rect.x + 3;

        if (i < nlen) {
            do {
                font_glyph_metrics((int)text[i], (unsigned int *)&w, (unsigned int *)&half_w);
                half_w = w >> 1;
                running += half_w;
                if (running > limit) {
                    return i - 1;
                }
                if (x < running) {
                    return i;
                }
                running += w - half_w;
                i++;
            } while (i < nlen);
        }

        return i;
    }

    return -1;
}

void dlgwidget_text_delete_or_bksp(DialogWidget *widget) {
    if (widget->nCursor != widget->nFull_length) {
        widget->nFull_length = widget->nCursor;
    } else {
        if (widget->nCursor == 0)
            return;
        --widget->nCursor;
        --widget->nFull_length;
    }
}

void dlgwidget_text_extend_or_end(DialogWidget *widget) {
    if (widget->nCursor != widget->nFull_length) {
        widget->nCursor = widget->nFull_length;
    } else if (widget->nCursor < widget->nLength) {
        widget->nCursor++;
        widget->nFull_length++;
    }
    return;
}

void dlgwidget_text_compact_delete(DialogWidget *widget) {
    char *text;
    int src;
    int dst;

    text = widget->pText_buf;
    src = widget->nFull_length;
    dst = widget->nCursor;
    if (src == dst) {
        if (src == 0) {
            return;
        }
        dst = dst - 1;
    }
    while (text[src] != '\0') {
        text[dst] = text[src];
        src = src + 1;
        dst = dst + 1;
    }
    text[dst] = '\0';
    widget->nLength = dst;
    if (widget->nCursor == widget->nFull_length) {
        widget->nFull_length = --widget->nCursor;
    } else {
        widget->nFull_length = widget->nCursor;
    }
}

void dlgwidget_text_forward_delete(DialogWidget *widget) {
    char *text;
    int dst;
    int src;

    text = widget->pText_buf;
    src = widget->nFull_length;
    dst = widget->nCursor;
    if (src == dst) {
        if (!text[src]) {
            return;
        }
        src = src + 1;
    }
    for (; text[src] != '\0'; dst = dst + 1) {
        text[dst] = text[src];
        src = src + 1;
    }
    text[dst] = '\0';
    widget->nLength = dst;
    widget->nFull_length = widget->nCursor;
    return;
}

void dlgwidget_text_cursor_home(DialogWidget *widget) {
    widget->nCursor = widget->nFull_length = 0;
}

void dlgwidget_text_cursor_end(DialogWidget *widget) {
    widget->nFull_length = widget->nLength;
    widget->nCursor = widget->nLength;
    return;
}

void dlgwidget_text_insert_char(DialogWidget *widget, unsigned char ch) {
    char *text;
    int pixelWidth;
    int src;
    int dst;

    text = widget->pText_buf;
    src = widget->nLength;
    dst = src + 1;
    if (widget->nCursor != widget->nFull_length) {
        dlgwidget_text_forward_delete(widget);
    }
    if (widget->nLength < widget->nCapacity - 1) {
        text[src] = ch;
        text[dst] = '\0';
        pixelWidth = font_text_width_ds(text);
        text[src] = '\0';
        if (pixelWidth <= widget->rect.width - 5) {
            for (; widget->nCursor != dst; dst--) {
                text[dst] = text[src];
                src--;
            }
            text[dst] = ch;
            widget->nLength++;
            widget->nCursor++;
            widget->nFull_length = widget->nCursor;
        }
    }
}

void dlgwidget_draw_text_input_widget(DialogWidget *widget, int in_input_mode) {
    char saved;
    int caret_x;
    int sel_w;

    g_graphics_context.bClip_enabled = 0;
    g_graphics_context.bGfx_outline_color = widget->bFg_color;
    if (*(int *)&widget->pFill_image | *((int *)&widget->pFill_image + 1)) {
        cga_rect_paste_from_buffer(widget->pFill_image, widget->rect.x, widget->rect.y,
                                   widget->rect.width, widget->rect.height);
        g_graphics_context.bGfx_fill_enabled = 0;
    } else {
        g_graphics_context.bGfx_fill_enabled = 1;
        g_graphics_context.bGfx_fill_color = widget->bBg_color;
    }
    draw_rect_filled(widget->rect.x, widget->rect.y, widget->rect.width, widget->rect.height);
    g_graphics_context.bGfx_fill_enabled = 0;
    g_graphics_context.bText_style_flags = 1;
    if (widget->pLabel != (char *)0) {
        g_graphics_context.bText_fg_color = widget->bLabel_fg;
        font_draw_text_ds(widget->pLabel, widget->nLabel_x, widget->nLabel_y);
    }
    g_graphics_context.clip.xmin = widget->rect.x + 2;
    g_graphics_context.clip.ymin = widget->rect.y + 2;
    g_graphics_context.clip.xmax = widget->rect.x + widget->rect.width - 3;
    g_graphics_context.clip.ymax = widget->rect.y + widget->rect.height - 3;
    g_graphics_context.bClip_enabled = 1;
    if (in_input_mode != 0) {
        saved = widget->pText_buf[widget->nCursor];
        widget->pText_buf[widget->nCursor] = 0;
        caret_x = widget->rect.x + font_text_width_ds(widget->pText_buf) + 2;
        widget->pText_buf[widget->nCursor] = saved;
        if (widget->nCursor == widget->nFull_length) {
            if (g_nCursorBlinkOn != 0 || g_dwCursorBlinkPhaseStart + 0x28 <= g_timer_ticks) {
                if (g_nCursorBlinkOn != 0) {
                    if (g_dwCursorBlinkPhaseStart + 0x14 <= g_timer_ticks) {
                        g_nCursorBlinkOn = 0;
                    }
                    g_graphics_context.bGfx_outline_color = widget->bCursor_color;
                    draw_line(caret_x, widget->rect.y + 2, caret_x,
                              widget->rect.y + widget->rect.height - 3);
                } else {
                    g_dwCursorBlinkPhaseStart = g_timer_ticks;
                    g_nCursorBlinkOn = 1;
                }
            }
        } else {
            saved = widget->pText_buf[widget->nFull_length];
            widget->pText_buf[widget->nFull_length] = 0;
            sel_w = font_text_width_ds(widget->pText_buf + widget->nCursor) + 1;
            widget->pText_buf[widget->nFull_length] = saved;
            g_graphics_context.bGfx_fill_enabled = 1;
            g_graphics_context.bGfx_fill_color = widget->bSelection_color;
            g_graphics_context.bGfx_outline_color = g_graphics_context.bGfx_fill_color;
            draw_rect_filled(caret_x, widget->rect.y + 2, sel_w, widget->rect.height - 4);
        }
    }
    g_graphics_context.bText_fg_color = widget->bLabel_fg;
    font_draw_text_ds(widget->pText_buf, widget->rect.x + 3, widget->rect.y + 2);
}

unsigned char dlgwidget_text_input_disp_key(void) {
    if (g_key_scancode != 0 && g_key_scancode != 0x38) {
        if (g_key_ascii >= 0x20 && g_key_ascii <= 0x7e)
            return g_key_ascii;

        switch (g_key_scancode) {
        case 14:
            return 3;
        case 15:
            if (g_key_shift_held != 0)
                return 6;
            return 7;
        case 28:
            return 5;
        case 71:
            return 8;
        case 75:
            return 1;
        case 77:
            return 2;
        case 79:
            return 9;
        case 83:
            return 4;
        }
    }
    return 0;
}
