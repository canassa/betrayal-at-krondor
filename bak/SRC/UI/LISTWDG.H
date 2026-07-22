#ifndef BAK_LISTWDG_H
#define BAK_LISTWDG_H

#include "structs.h"

extern ListWidget *listwidget_attach(short x, short y, short width, short line_count,
                                     short capacity, MenuPage *parent, short child_idx);
extern ListWidget *listwidget_load(char *filename, MenuPage *parent, short child_idx);
extern int listwidget_destroy(ListWidget *list);
extern int listwidget_capacity(ListWidget *list);
extern int listwidget_count(ListWidget *list);
extern int listwidget_insert_item(ListWidget *list, int pos, char *text, unsigned short payload);
extern int listwidget_remove_item(ListWidget *list, int idx);
extern int listwidget_get_current_entry(ListWidget *list, char **out_label, unsigned short *out_value);
extern int listwidget_get_entry_at(ListWidget *list, int index, char **out_label,
                                   unsigned short *out_value);
extern int listwidget_last_index(ListWidget *list);
extern int listwidget_set_selection(ListWidget *list, int index);
extern int listwidget_scroll_up(ListWidget *list);
extern int listwidget_scroll_down(ListWidget *list);
extern int listwidget_get_selection(ListWidget *list);
extern int listwidget_handle_click(ListWidget *list, unsigned short *out_confirm);
extern int listwidget_hit_test(ListWidget *list);
extern int listwidget_ensure_visible(ListWidget *list);
extern void listwidget_draw(ListWidget *list);

#endif
