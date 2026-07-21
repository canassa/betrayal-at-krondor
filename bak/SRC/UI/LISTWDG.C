#include <string.h>
#include "globals.h"
#include "structs.h"
#include "SRC/UI/LISTWDG.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/WIDGET.H"
#include "SRC/UI/UIWIDGET.H"

ListWidget *far listwidget_attach(short x, short y, short width, short line_count, short capacity,
                                  MenuPage *parent, short child_idx) {
    ListWidget *ptr;
    void *labels;
    void *values;
    MenuEntry *entry;

    if (parent != (MenuPage *)0x0) {
        if (child_idx < (int)parent->wEntry_count) {
            entry = parent->pEntries + child_idx;
            if (entry->wWidget_type == 2) {
                ptr = galloc_safe_zcalloc(sizeof(ListWidget));
                if (ptr != (ListWidget *)0x0) {
                    labels = galloc_safe_zcalloc(capacity << 1);
                    if (labels != (void *)0x0) {
                        values = galloc_safe_zcalloc(capacity << 1);
                        if (values != (void *)0x0) {
                            ptr->nX = x;
                            ptr->nY = y;
                            ptr->nInner_w = width - 16;
                            ptr->nPixel_h = line_count * (font_height_get(0) + 5) + 2;
                            ptr->nVisible_rows = line_count;
                            ptr->nAnchor_x = parent->rect.x;
                            ptr->nAnchor_y = parent->rect.y;
                            ptr->wCapacity = capacity;
                            ptr->wCount = 0;
                            ptr->wScroll_offset = 0;
                            ptr->pLabels = labels;
                            ptr->pValues = values;
                            ptr->pParent = entry;
                            entry->rect.x = ptr->nX + ptr->nInner_w;
                            entry->rect.y = ptr->nY;
                            entry->rect.width = 0x10;
                            entry->rect.height = ptr->nPixel_h;
                            entry->wEnable_gate = 0;
                            entry->wSub_state = 0;
                            if (entry->pPrimary_label == (char *)0x0) {
                                entry->pPrimary_label = (char *)ptr;
                            }
                            return ptr;
                        }
                        galloc_zfree(labels);
                    }
                    galloc_zfree(ptr);
                }
            }
        }
    }
    return (ListWidget *)0x0;
}

ListWidget *far listwidget_load(char *filename, MenuPage *parent, short child_idx) {
    BakFile *stream;
    short x;
    short y;
    short width;
    short line_count;
    short capacity;
    int len;
    ListWidget *widget;
    char buf[256];
    int pos;

    widget = (ListWidget *)0;
    stream = bak_fopen(filename, "rb");
    if (stream != (BakFile *)0) {
        bak_fread(&x, 2, 1, stream);
        bak_fread(&y, 2, 1, stream);
        bak_fread(&width, 2, 1, stream);
        bak_fread(&line_count, 2, 1, stream);
        bak_fread(&capacity, 2, 1, stream);
        widget = listwidget_attach(x, y, width, line_count, capacity, parent, child_idx);
        if (widget != (ListWidget *)0) {
            pos = 0;
            while (pos < capacity) {
                bak_fread(&len, 2, 1, stream);
                bak_fread(buf, 1, len, stream);
                listwidget_insert_item(widget, pos, buf, 0);
                pos++;
            }
        }
        bak_fclose(stream);
    }
    return widget;
}

int far listwidget_destroy(ListWidget *list) {
    int idx;

    if (list != (ListWidget *)0x0) {
        if ((ListWidget *)list->pParent->pPrimary_label == list) {
            list->pParent->pPrimary_label = (char *)0x0;
        }
        for (idx = (int)list->wCount - 1; idx >= 0; idx--) {
            listwidget_remove_item(list, idx);
        }
        galloc_zfree(list->pValues);
        galloc_zfree(list->pLabels);
        galloc_zfree(list);
        return 1;
    }
    return 0;
}

int listwidget_capacity(ListWidget *list) {
    return list ? list->wCapacity : 0xffff;
}

int listwidget_count(ListWidget *list) {
    return list ? list->wCount : -1;
}

int listwidget_insert_item(ListWidget *list, int pos, char *text, ushort payload) {
    char *dest;

    if (!list)
        goto fail;
    if ((int)list->wCount >= (int)list->wCapacity)
        goto fail;
    if (pos < 0)
        goto fail;
    if ((int)list->wCount < pos)
        goto fail;
    if (!text)
        goto fail;
    dest = galloc_safe_zcalloc(strlen(text) + 1);
    if (dest != 0) {
        ushort j;
        strcpy(dest, text);
        j = list->wCount;
        while ((int)j > pos) {
            list->pLabels[j] = list->pLabels[j - 1];
            list->pValues[j] = list->pValues[j - 1];
            j--;
        }
        list->pLabels[pos] = dest;
        list->pValues[pos] = payload;
        list->wCount++;
        list->pParent->wEnable_gate++;
        return 1;
    }
fail:
    return 0;
}

int far listwidget_remove_item(ListWidget *list, int idx) {
    int i;
    if (list != (ListWidget *)0x0 && idx >= 0 && (int)list->wCount > idx) {
        galloc_zfree(list->pLabels[idx]);
        list->wCount--;
        list->pParent->wEnable_gate--;
        list->pParent->wSub_state = 0;
        list->wScroll_offset = 0;
        for (i = idx; i < (int)list->wCount; i++) {
            list->pLabels[i] = list->pLabels[i + 1];
            list->pValues[i] = list->pValues[i + 1];
        }
        return 1;
    }
    return 0;
}

int far listwidget_get_current_entry(ListWidget *list, char **out_label, ushort *out_value) {
    ushort idx;

    if (list != (ListWidget *)0x0 && list->wCount != 0) {
        idx = list->pParent->wSub_state;
        if (out_label != (char **)0x0) {
            *out_label = list->pLabels[idx];
        }
        if (out_value != (ushort *)0x0) {
            *out_value = list->pValues[idx];
        }
        return 1;
    }
    return 0;
}

int listwidget_get_entry_at(ListWidget *list, int index, char **out_label, ushort *out_value) {
    if (((list != (ListWidget *)0x0) && (0 <= index)) && (index < (int)list->wCount)) {
        if (out_label != (char **)0x0) {
            *out_label = list->pLabels[index];
        }
        if (out_value != (ushort *)0x0) {
            *out_value = list->pValues[index];
        }
        return 1;
    }
    return 0;
}

int listwidget_last_index(ListWidget *list) {
    return list ? list->wCount - 1 : -1;
}

int listwidget_set_selection(ListWidget *list, int index) {
    int vis;
    int half_vis;
    unsigned short count;

    count = list->wCount;
    vis = list->nVisible_rows;
    half_vis = vis >> 1;
    if (list != 0 && index >= 0 && index < (int)count) {
        list->pParent->wSub_state = index;
        if ((int)count <= vis || index <= half_vis) {
            list->wScroll_offset = 0;
        } else if ((int)(count - index) <= half_vis) {
            list->wScroll_offset = count - vis;
        } else {
            list->wScroll_offset = index - half_vis;
        }
        return 1;
    }
    return 0;
}

int far listwidget_scroll_up(ListWidget *list) {
    if (list != (ListWidget *)0) {
        widget_list_scroll(list->pParent, 1);
        return 1;
    }
    return 0;
}

int far listwidget_scroll_down(ListWidget *list) {
    if (list != (ListWidget *)0) {
        widget_list_scroll(list->pParent, 0);
        return 1;
    }
    return 0;
}

int listwidget_get_selection(ListWidget *list) {
    return list ? list->pParent->wSub_state : -1;
}

int far listwidget_handle_click(ListWidget *list, ushort *out_confirm) {
    int half_vis;
    int old_scroll;
    int hit;
    int count;
    int vis;

    if (list != (ListWidget *)0) {
        hit = listwidget_hit_test(list);
        if (hit != -1) {
            switch (screen_input_poll_confirm_cancel()) {
            case 1:
                if (list->pParent->wSub_state != (ushort)hit) {
                    count = list->wCount;
                    vis = list->nVisible_rows;
                    half_vis = vis >> 1;
                    old_scroll = list->wScroll_offset;
                    if (hit >= 0 && hit < count) {
                        list->pParent->wSub_state = (ushort)hit;
                        if (hit < old_scroll || old_scroll + vis <= hit) {
                            if (count <= vis || hit <= half_vis) {
                                list->wScroll_offset = 0;
                            } else if (count - hit <= half_vis) {
                                list->wScroll_offset = count - vis;
                            } else {
                                list->wScroll_offset = hit - half_vis;
                            }
                        }
                    }
                    if (out_confirm != (ushort *)0)
                        *out_confirm = 0;
                    return 1;
                } else {
                    if (out_confirm == (ushort *)0)
                        return 0;
                    *out_confirm = 1;
                    return 1;
                }
            case 2:
                return 0;
            }
        }
    }
    return 0;
}

int far listwidget_hit_test(ListWidget *list) {
    short cur_x;
    int rect_x;
    int rect_y;
    int inner_w2;
    int pixel_h2;
    int line_step;
    /* `lp = list` is a distinct register local copy: it pins the widget pointer
     * into SI (a bare `register` on the param stays at [bp+6]), which frees DI
     * for `register cur_y`. */
    register ListWidget *lp;
    register int cur_y;

    lp = list;
    cur_x = screen_cursor_get_x();
    cur_y = screen_cursor_get_y();
    rect_x = lp->nAnchor_x + lp->nX + 1;
    rect_y = lp->nAnchor_y + lp->nY + 1;
    inner_w2 = lp->nInner_w - 2;
    pixel_h2 = lp->nPixel_h - 2;
    line_step = font_height_get(0) + 5;
    if (cur_x < rect_x)
        goto fail;
    if (rect_x + inner_w2 <= cur_x)
        goto fail;
    if (cur_y < rect_y)
        goto fail;
    if (rect_y + pixel_h2 <= cur_y)
        goto fail;
    {
        int row = (cur_y - rect_y) / line_step + lp->wScroll_offset;
        if ((int)lp->wCount > row)
            return row;
    }
fail:
    return -1;
}

int listwidget_ensure_visible(ListWidget *list) {
    if (list != (ListWidget *)0x0) {
        if ((int)list->pParent->wSub_state < (int)list->wScroll_offset) {
            list->wScroll_offset--;
        } else if ((int)(list->wScroll_offset + list->nVisible_rows) <=
                   (int)list->pParent->wSub_state) {
            list->wScroll_offset++;
        }
        return 1;
    }
    return 0;
}

void listwidget_draw(ListWidget *list) {
    unsigned short count;
    int vis;
    unsigned short row_idx;
    unsigned short selected;
    int rect_x;
    int rect_y;
    int w;
    int inner_ymax;
    int visible_row;
    int line_height;
    int clip_xmin;
    int clip_ymin;
    int clip_xmax;
    int clip_ymax;

    count = list->wCount;
    vis = list->nVisible_rows;
    row_idx = list->wScroll_offset;
    selected = list->pParent->wSub_state;
    rect_x = list->nAnchor_x + list->nX;
    rect_y = list->nAnchor_y + list->nY;
    w = list->nInner_w;
    inner_ymax = list->nPixel_h;

    line_height = font_height_get(0) + 5;

    g_graphics_context.bClip_enabled = 0;
    uiwidget_draw_beveled_button(rect_x, rect_y, w, inner_ymax);
    g_graphics_context.bGfx_fill_enabled = 0;

    clip_xmin = rect_x + 3;
    g_graphics_context.clip.xmin = clip_xmin;
    clip_ymin = rect_y + 3;
    g_graphics_context.clip.ymin = clip_ymin;
    clip_xmax = rect_x + w - 4;
    g_graphics_context.clip.xmax = clip_xmax;
    clip_ymax = rect_y + inner_ymax - 4;
    g_graphics_context.clip.ymax = clip_ymax;

    g_graphics_context.bClip_enabled = 1;
    g_graphics_context.bText_style_flags = 1;

    rect_x += 3;
    rect_y += 3;

    for (visible_row = 0; visible_row < (int)count && visible_row < vis; visible_row++) {
        if (row_idx == selected) {
            g_graphics_context.bClip_enabled = 0;
            uiwidget_draw_beveled_button(rect_x - 2, rect_y - 2, w - 2, line_height);
            g_graphics_context.bClip_enabled = 1;
            g_graphics_context.clip.xmin = clip_xmin;
            g_graphics_context.clip.ymin = clip_ymin;
            g_graphics_context.clip.xmax = clip_xmax;
            g_graphics_context.clip.ymax = clip_ymax;
            g_graphics_context.bText_fg_color = 1;
            font_draw_text_ds(list->pLabels[row_idx], rect_x, rect_y + 1);
            g_graphics_context.bText_fg_color = 10;
        } else {
            g_graphics_context.bText_fg_color = 0;
        }
        font_draw_text_ds(list->pLabels[row_idx], rect_x, rect_y);
        row_idx++;
        rect_y += line_height;
    }
    g_graphics_context.bClip_enabled = 0;
}
