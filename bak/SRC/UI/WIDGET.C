#include <string.h>

#include "globals.h"
#include "SRC/GEN/GFXCTX.H"
#include "structs.h"
#include "SRC/UI/WIDGET.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/RASTER/DRAWLINE.H"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/UI/LISTWDG.H"

ImageRecord **g_pButtonSpriteUp;
ImageRecord **g_pBtnSpriteDownSheet;
short g_nScrollTrackOffset;
unsigned char g_saved_clip_enabled;
unsigned short g_saved_clip_ymax;
unsigned short g_saved_clip_xmin;
unsigned short g_saved_clip_xmax;
unsigned short g_saved_clip_ymin;

static char _str_name_tmpl[13] = "01234567.012";
static char _str_ext_tmpl[5] = ".bmx";

typedef struct {
    char b[13];
} NameCopy;

typedef struct {
    char b[5];
} ExtCopy;

typedef struct {
    char b[14];
} NameBuf;

typedef struct {
    char b[6];
} ExtBuf;

void widget_load_button_sprite_pair(char *filename) {
    NameBuf name;
    ExtBuf ext;
    int i;

    *(NameCopy *)name.b = *(NameCopy *)_str_name_tmpl;
    *(ExtCopy *)ext.b = *(ExtCopy *)_str_ext_tmpl;
    strcpy(name.b, filename);
    i = 0;
    do {
        if (name.b[i] == '\0')
            break;
        i++;
    } while (i < 7);
    name.b[i] = '1';
    name.b[i + 1] = '\0';
    strcat(name.b, ext.b);
    g_pButtonSpriteUp = resblit_load_asset_table(name.b, 1);
    name.b[i] = '2';
    g_pBtnSpriteDownSheet = resblit_load_asset_table(name.b, 1);
}

void widget_free_button_sprite_pair(void) {
    emsimg_free_paged(g_pButtonSpriteUp);
    emsimg_free_paged(g_pBtnSpriteDownSheet);
    return;
}

void widget_blit_button_sprite(unsigned int sprite_idx, int x, int y, int palette, int center, int rect_w,
                               int rect_h) {
    ImageRecord **sheet;

    if (0x32 < (int)sprite_idx) {
        sprite_idx = sprite_idx + 1;
    }
    if ((sprite_idx & 1) != 0) {
        sheet = g_pBtnSpriteDownSheet;
    } else {
        sheet = g_pButtonSpriteUp;
    }
    sprite_idx = (unsigned int)((int)sprite_idx >> 1);
    if (center != 0) {
        x = x + ((rect_w >> 1) - (sheet[sprite_idx]->nWidth >> 1));
        y += (rect_h >> 1) - (sheet[sprite_idx]->nHeight >> 1);
    }
    resblit_sprite_frame(sheet[sprite_idx], x, y, palette);
}

int widget_hit_test(MenuEntry *widget, int x, int y, int *out_region) {
    int m;

    x -= widget->rect.x;
    y -= widget->rect.y;
    *out_region = 0;
    if (widget->wWidget_type == 2) {
        m = (widget->rect.width < widget->rect.height ? widget->rect.width : widget->rect.height) -
            4;

        if (x < 2)
            goto outer;
        if (m + 2 <= x)
            goto outer;
        if (y < 2)
            goto outer;
        if (m + 2 <= y)
            goto outer;
        *out_region = 2;
        goto done;
    outer:
        if (widget->rect.width < widget->rect.height) {

            if (!((x >= 2) && (x < m + 2) && ((widget->rect.height - m) - 2 <= y) &&
                  (y < widget->rect.height - 2))) {
                goto narrow_r3;
            }
            *out_region = 4;
            goto done;
        narrow_r3:

            if (x < 3)
                goto done;
            if (m + 1 <= x)
                goto done;
            if (y < m + 4)
                goto done;
            if ((widget->rect.height - m) - 4 <= y)
                goto done;
            *out_region = 3;

            g_nScrollTrackOffset = (y - m) - 4;
        } else {

            if (!((((widget->rect.width - m) - 2 <= x) && (x < widget->rect.width - 2)) &&
                  ((y >= 2) && (y < m + 2)))) {
                goto wide_r3;
            }
            *out_region = 4;
            goto done;
        wide_r3:

            if (x < m + 4)
                goto done;
            if ((widget->rect.width - m) - 4 <= x)
                goto done;
            if (y < 3)
                goto done;
            if (m + 1 <= y)
                goto done;
            *out_region = 3;
            g_nScrollTrackOffset = (x - m) - 4;
        }
    } else if (((x >= 0) && (widget->rect.width > x)) && ((y >= 0) && (widget->rect.height > y))) {
        *out_region = 1;
    }
done:
    return *out_region != 0;
}

void widget_dispatch_by_type(MenuEntry *widget, int x, int y, int hover_flag) {
    if (widget->bActive_flag != 0) {
        switch (widget->wWidget_type) {
        case 3:
        case 4:
            widget_menu_draw(widget, x, y, hover_flag);
            break;
        case 6:
        case 8:
            widget_draw_text_button(widget, x, y, hover_flag);
            break;
        case 7:
            widget_render_button(widget, x, y, hover_flag);
            break;
        case 2:
            widget_draw_scrollbar(widget, x, y, hover_flag);
            break;
        case 0:
        case 1:
        case 5:
            widget_button_render_full(widget, x, y, hover_flag, 0);
            break;
        }
    }
    return;
}

void widget_toggle_state(MenuEntry *widget) {
    if (widget->wSub_state != 0)
        widget->wSub_state = 0;
    else
        widget->wSub_state = 1;
    return;
}

void far widget_list_scroll(MenuEntry *widget, int dir) {
    if (widget->wWidget_type == 2) {
        if (dir != 0) {
            if (widget->wSub_state == 0) {
                return;
            }
            widget->wSub_state--;
            if (widget->pPrimary_label != (char *)0x0) {
                goto docall;
            }
            return;
        }
        if ((int)widget->wSub_state >= (int)widget->wEnable_gate - 1) {
            return;
        }
        widget->wSub_state++;
        if (widget->pPrimary_label == (char *)0x0) {
            return;
        }
    docall:
        listwidget_ensure_visible((ListWidget *)widget->pPrimary_label);
    }
    return;
}

void far widget_scrollbar_update(MenuEntry *widget) {
    int corner2;
    int step;
    if (widget->wWidget_type == 2) {
        if (widget->wEnable_gate == 0 || widget->wEnable_gate == 1) {
            widget->wSub_state = 0;
        } else {
            if (widget->rect.width < widget->rect.height) {
                corner2 = widget->rect.width - 4;
                widget->wSub_state =
                    (g_nScrollTrackOffset + ((step = (widget->rect.height - corner2 * 2 - 8) /
                                                     ((int)widget->wEnable_gate - 1)) >>
                                             1)) /
                    step;
            } else {
                corner2 = widget->rect.height - 4;
                widget->wSub_state =
                    (g_nScrollTrackOffset + ((step = (widget->rect.width - corner2 * 2 - 8) /
                                                     ((int)widget->wEnable_gate - 1)) >>
                                             1)) /
                    step;
            }
            if ((int)widget->wSub_state >= (int)widget->wEnable_gate) {
                widget->wSub_state = widget->wEnable_gate - 1;
            }
        }
        if (widget->pPrimary_label != (char *)0x0) {
            listwidget_set_selection((ListWidget *)widget->pPrimary_label, widget->wSub_state);
        }
    }
    return;
}

void widget_menu_draw(MenuEntry *widget, int x, int y, int hover_flag) {
    if (widget->wEnable_gate != 0) {
        widget_blit_button_sprite(0x32, x + widget->rect.x, y + widget->rect.y, 0, 0, 0, 0);
        return;
    }
    if ((widget->wWidget_type == 3) || ((widget->wWidget_type == 4 && (widget->wSub_state != 0))))
        widget_blit_button_sprite(widget->wSprite_base + (unsigned int)(hover_flag != 0),
                                  x + widget->rect.x, y + widget->rect.y, 0, 0, 0, 0);
    else
        widget_blit_button_sprite(widget->wSprite_base + (unsigned int)(hover_flag != 0) + 2,
                                  x + widget->rect.x, y + widget->rect.y, 0, 0, 0, 0);
}

void widget_button_render_full(MenuEntry *button, int x, int y, int pressed, int sprite_set) {
    unsigned short base_color;
    int bx;
    int by;
    int hy;
    int hx;
    int span;
    char *text;
    int i;

    base_color = button->wBase_color;
    bx = x + button->rect.x;
    by = y + button->rect.y;

    if (button->wEnable_gate == 0 && pressed != 0 && button->wWidget_type != 5) {
        if (base_color == 0xa9) {
            uiwidget_panel_inset_inverted(bx, by, button->rect.width, button->rect.height, 1);
        } else {
            uiwidget_panel_draw_3edge_bevel(bx, by, button->rect.width, button->rect.height,
                                            base_color + 3, base_color, base_color + 2,
                                            base_color + 4, base_color + 6);
        }
    } else if (button->wWidget_type != 5) {
        base_color++;
        if (base_color == 0xaa) {
            uiwidget_panel_inset_inverted(bx, by, button->rect.width, button->rect.height, 0);
        } else {
            uiwidget_panel_draw_3edge_bevel(bx, by, button->rect.width, button->rect.height,
                                            base_color + 3, base_color + 6, base_color + 4,
                                            base_color + 2, base_color);
        }
    }

    if (button->pPrimary_label != (char *)0) {
        if (button->wWidget_type == 0 || button->wWidget_type == 5 ||
            (button->wWidget_type == 1 && button->wSub_state != 0)) {
            text = button->pPrimary_label;
        } else {
            text = button->pAlt_label;
        }
        if (button->wBase_color == 0xa9) {
            if (pressed != 0) {
                uiwidget_draw_text_shadowed(text, 0xaa, 0xae,
                                            (bx + (button->rect.width >> 1)) -
                                                (font_text_width_ds(text) >> 1) + 1,
                                            by + (button->rect.height >> 1) - 4);
            } else {
                uiwidget_draw_text_shadowed(text, 0x33, 1,
                                            (bx + (button->rect.width >> 1)) -
                                                (font_text_width_ds(text) >> 1) + 1,
                                            by + (button->rect.height >> 1) - 4);
            }
        } else {
            uiwidget_draw_text_shadowed(text, base_color + 2, base_color - 1,
                                        (bx + (button->rect.width >> 1)) -
                                            (font_text_width_ds(text) >> 1) + 1,
                                        by + (button->rect.height >> 1) - 4);
        }
    } else {
        if (button->wWidget_type == 0 || (button->wWidget_type == 1 && button->wSub_state != 0)) {
            widget_blit_button_sprite(button->wSprite_base + (pressed != 0), bx, by, sprite_set, 1,
                                      button->rect.width, button->rect.height);
        } else {
            widget_blit_button_sprite(button->wSprite_base + (pressed != 0) + 2, bx, by, sprite_set,
                                      1, button->rect.width, button->rect.height);
        }
    }

    if (button->wEnable_gate != 0) {
        g_graphics_context.bGfx_outline_color = base_color + 3;
        bx++;
        hx = bx;
        by++;
        hy = by;
        widget_push_clip_rect(bx, by, bx + button->rect.width - 3, by + button->rect.height - 3);
        span = (button->rect.width >> 1) + (button->rect.height >> 1) + 2;
        for (i = 0; i < span; i++) {
            draw_line(bx, hy, hx, by);
            hx += 2;
            hy += 2;
        }
        widget_pop_clip_rect();
    }
}

void widget_draw_text_button(MenuEntry *widget, int x, int y, int pressed) {
    int edgeColor;
    int textColor;
    int shadowColor;
    int outline_color;
    int fill_color;

    x += widget->rect.x;
    y += widget->rect.y;

    if (pressed != 0) {
        outline_color = 1;
        edgeColor = 4;
        fill_color = 0xb;
        textColor = 6;
        shadowColor = 1;
    } else {
        outline_color = 4;
        edgeColor = 1;
        fill_color = 0xe;
        textColor = 0xa;
        shadowColor = 1;
        if (widget->wWidget_type == 8) {
            textColor = 1;
            shadowColor = 0;
        }
    }

    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bGfx_fill_color = fill_color;
    g_graphics_context.bGfx_outline_color = outline_color;
    draw_rect_filled(x, y, widget->rect.width, widget->rect.height);

    g_graphics_context.bGfx_fill_enabled = 0;
    g_graphics_context.bGfx_outline_color = edgeColor;
    draw_line(x, y, x, y + widget->rect.height - 1);
    draw_line(x, y + widget->rect.height - 1, x + widget->rect.width - 1,
              y + widget->rect.height - 1);

    x += (widget->rect.width >> 1) - (font_text_width_ds(widget->pPrimary_label) >> 1);
    y += (widget->rect.height >> 1) - 4;

    if (widget->wEnable_gate != 0) {
        g_graphics_context.bText_fg_color = 0xb;
        font_draw_text_ds(widget->pPrimary_label, x, y);
    } else {
        g_graphics_context.bText_fg_color = shadowColor;
        font_draw_text_ds(widget->pPrimary_label, x, y);
        g_graphics_context.bText_fg_color = textColor;
        font_draw_text_ds(widget->pPrimary_label, x, y - 1);
    }
}

void widget_draw_iconbox(MenuEntry *widget, int x, int y, int pressed, int sprite_flags) {
    int edgeColor;
    int outline_color;
    int fill_color;

    x += widget->rect.x;
    y += widget->rect.y;
    if (pressed != 0) {
        outline_color = 1;
        edgeColor = 4;
        fill_color = 0xb;
    } else {
        outline_color = 4;
        edgeColor = 1;
        fill_color = 0xe;
    }
    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bGfx_fill_color = fill_color;
    g_graphics_context.bGfx_outline_color = outline_color;
    draw_rect_filled(x, y, widget->rect.width, widget->rect.height);
    g_graphics_context.bGfx_fill_enabled = 0;
    g_graphics_context.bGfx_outline_color = edgeColor;
    draw_line(x, y, x, y + widget->rect.height - 1);
    draw_line(x, y + widget->rect.height - 1, x + widget->rect.width - 1,
              y + widget->rect.height - 1);
    widget_blit_button_sprite(widget->wSprite_base + (unsigned int)(pressed != 0), x, y, sprite_flags, 1,
                              widget->rect.width, widget->rect.height);
    return;
}

void widget_draw_scrollbar(MenuEntry *widget, int x, int y, int pressed_part) {
    int thumbOff;
    int sprite_flags;
    int btnSize;
    MenuEntry iconBtn;
    int sx;
    int sy;
    int isVertical;
    int trackLen;

    sx = x + widget->rect.x;
    sy = y + widget->rect.y;
    g_graphics_context.bClip_enabled = 0;
    uiwidget_draw_beveled_button(sx, sy, widget->rect.width, widget->rect.height);
    g_graphics_context.bGfx_fill_enabled = 0;
    g_graphics_context.bGfx_outline_color = 1;
    if (widget->rect.width < widget->rect.height) {
        isVertical = 1;
        btnSize = widget->rect.width + -4;
        trackLen = widget->rect.height - btnSize * 2 + -6;
        draw_rect_filled(sx + 2, sy + btnSize + 3, widget->rect.width + -4, trackLen);
        iconBtn.wSprite_base = widget->wSprite_base;
    } else {
        isVertical = 0;
        btnSize = widget->rect.height + -4;
        trackLen = widget->rect.width - btnSize * 2 + -6;
        draw_rect_filled(sx + btnSize + 3, sy + 2, trackLen, widget->rect.height + -4);
        iconBtn.wSprite_base = widget->wSprite_base + 2;
    }
    iconBtn.wWidget_type = 6;
    iconBtn.bActive_flag = 1;
    iconBtn.wEnable_gate = 0;
    iconBtn.rect.x = 2;
    iconBtn.rect.y = 2;
    iconBtn.rect.width = btnSize;
    iconBtn.rect.height = btnSize;
    iconBtn.pLabel = (char *)0x0;
    iconBtn.pPrimary_label = (char *)0x0;
    iconBtn.pAlt_label = (char *)0x0;
    iconBtn.wCursor_shape = widget->wCursor_shape;
    widget_draw_iconbox(&iconBtn, sx, sy, (unsigned int)(pressed_part == 2), 0);

    if (1 < (int)widget->wEnable_gate) {
        thumbOff = (int)widget->wSub_state * (trackLen + -7) / ((int)widget->wEnable_gate - 1);
    } else {
        thumbOff = 0;
    }

    if (isVertical != 0) {
        if (widget->wEnable_gate != 0) {
            uiwidget_draw_beveled_button(sx + 3, sy + btnSize + thumbOff + 4,
                                         widget->rect.width + -6, 5);
        }
        iconBtn.rect.y = (widget->rect.height - btnSize) + -2;
        sprite_flags = 1;
    } else {
        if (widget->wEnable_gate != 0) {
            uiwidget_draw_beveled_button(sx + btnSize + thumbOff + 4, sy + 3, 5,
                                         widget->rect.height + -6);
        }
        iconBtn.rect.x = (widget->rect.width - btnSize) + -2;
        sprite_flags = 2;
    }
    widget_draw_iconbox(&iconBtn, sx, sy, (unsigned int)(pressed_part == 4), sprite_flags);
}

void widget_render_button(MenuEntry *widget, int x_off, int y_off, int hover_flag) {
    if (widget->wEnable_gate != 0) {
        widget_blit_button_sprite(widget->wSprite_base + 2, x_off + widget->rect.x,
                                  y_off + widget->rect.y, 0, 0, 0, 0);
        return;
    }
    widget_blit_button_sprite(widget->wSprite_base + (unsigned int)(hover_flag != 0),
                              x_off + widget->rect.x, y_off + widget->rect.y, 0, 0, 0, 0);
    return;
}

void widget_push_clip_rect(short xmin, short ymin, short xmax, short ymax) {
    g_saved_clip_enabled = g_graphics_context.bClip_enabled;
    g_saved_clip_ymax = g_graphics_context.clip.ymax;
    g_saved_clip_xmin = g_graphics_context.clip.xmin;
    g_saved_clip_xmax = g_graphics_context.clip.xmax;
    g_saved_clip_ymin = g_graphics_context.clip.ymin;
    g_graphics_context.bClip_enabled = 1;
    g_graphics_context.clip.ymax = ymax;
    g_graphics_context.clip.xmin = xmin;
    g_graphics_context.clip.xmax = xmax;
    g_graphics_context.clip.ymin = ymin;
}

void widget_pop_clip_rect(void) {
    g_graphics_context.bClip_enabled = g_saved_clip_enabled;
    g_graphics_context.clip.ymax = g_saved_clip_ymax;
    g_graphics_context.clip.xmin = g_saved_clip_xmin;
    g_graphics_context.clip.xmax = g_saved_clip_xmax;
    g_graphics_context.clip.ymin = g_saved_clip_ymin;
}
