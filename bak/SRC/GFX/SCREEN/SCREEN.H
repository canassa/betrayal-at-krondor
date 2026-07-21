#ifndef BAK_SCREEN_H
#define BAK_SCREEN_H

#include "structs.h"

extern int screen_cursor_get_position(short *out_x, short *out_y);
extern int screen_cursor_set_position(int x, int y);
extern void screen_cursor_set_hidden_flag(int hidden);
extern short screen_cursor_get_x(void);
extern short screen_cursor_get_y(void);
extern ImageRecord **screen_cursor_state_get(void);
extern void screen_cur_set_shape_remember(int shape_id);
extern void screen_cursor_set_shape(int shape_id);
extern int screen_input_poll_confirm_cancel(void);
extern void screen_cursor_load_pack(int pack_id);
extern void screen_cursor_unload_pack(void);
extern void screen_cursor_state_push_pop(int restore);
extern void screen_cursor_hide(void);
extern void screen_cursor_draw(CursorState *cursor_rec, unsigned char far *buf);
extern void screen_cursor_restore_background(CursorState *cur, uchar far *pBgBuffer);
extern void screen_cur_refr_during_long_op(void);
extern void screen_frame_present(void);
extern void screen_frame_sync_buffers_rect(int row_start, int row_count);
extern void screen_clear_both_pages(void);
extern void screen_clear_back_buffer(void);
extern void screen_render_main_frame(char *menu_only);
extern void screen_cursor_show_busy(void);
extern void screen_cursor_restore_shape(void);
extern void screen_scene_reset_clip_cur(void);
extern void screen_wipe_horizontal(int x, int y, int w, int h);
extern void screen_frame_flip(void);

#endif
