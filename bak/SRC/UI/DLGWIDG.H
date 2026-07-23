#ifndef BAK_DLGWIDG_H
#define BAK_DLGWIDG_H

#include "structs.h"

extern short g_text_input_drag_anchor;
extern int g_nCursorBlinkOn;
extern unsigned long g_dwCursorBlinkPhaseStart;
extern unsigned char g_key_scancode;
extern unsigned char g_key_ascii;
extern unsigned char g_key_held;
extern unsigned char g_key_shift_held;

extern Dialog *dlgwidget_dialog_load(char *filename);
extern void dlgwidget_dialog_destroy_bgs(Dialog *dialog);
extern Dialog *dlgwidget_dialog_create(int capacity);
extern void dlgwidget_dialog_destroy(Dialog *dialog);
extern int dlgwidget_dialog_add_widget(Dialog *dialog, DialogWidget *widget, char *label_text,
                                       char *label, short label_x, short label_y);
extern void dlgwidget_dialog_set_widget_text(Dialog *dialog, int widget_index, char *text);
extern int dlgwidget_dialog_focus_widget(Dialog *dialog, int widget_idx);
extern char *dlgwidget_dialog_widget_text_ptr(Dialog *dialog, int widget_idx);
extern void dlgwidget_dlg_capture_bgs(Dialog *dialog);
extern void dlgwidget_dlg_focus_first_wdg(Dialog *dialog);
extern int dlgwidget_text_input_dialog_pump(Dialog *pDialog);
extern void dlgwidget_dialog_rstrip_widgets(Dialog *dialog);
extern void dlgwidget_dialog_render(Dialog *dialog, int show_selection);
extern DialogWidget *dlgwidget_create(unsigned int capacity, short rect_x, short rect_y, short rect_w,
                                      unsigned char bg_color, unsigned char fg_color, unsigned char cursor_color,
                                      unsigned char label_fg, unsigned char selection_color, int has_fill_image);
extern void dlgwidget_destroy(DialogWidget *widget);
extern void dlgwidget_set_text(DialogWidget *widget, char *text);
extern void dlgwidget_set_label_pos(DialogWidget *widget, char *label, short label_x,
                                    short label_y);
extern void dlgwidget_capture_background(DialogWidget *widget);
extern int dlgwidget_text_char_at_point(DialogWidget *widget, int x, int y);
extern void dlgwidget_text_delete_or_bksp(DialogWidget *widget);
extern void dlgwidget_text_extend_or_end(DialogWidget *widget);
extern void dlgwidget_text_compact_delete(DialogWidget *widget);
extern void dlgwidget_text_forward_delete(DialogWidget *widget);
extern void dlgwidget_text_cursor_home(DialogWidget *widget);
extern void dlgwidget_text_cursor_end(DialogWidget *widget);
extern void dlgwidget_text_insert_char(DialogWidget *widget, unsigned char ch);
extern void dlgwidget_draw_text_input_widget(DialogWidget *widget, int in_input_mode);
extern unsigned char dlgwidget_text_input_disp_key(void);

#endif
