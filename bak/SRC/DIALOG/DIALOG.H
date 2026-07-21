#ifndef BAK_DIALOG_H
#define BAK_DIALOG_H

#include "structs.h"

extern int dialog_freemem_if_not_null(uchar far *ptr);
extern PDdxRecord dialog_load_record_by_key(ulong record_key, int use_offset);
extern uint dialog_poll_arrow_or_button(void);
extern void dialog_input_wait_release(int animate_frames, int check_keyboard);
extern int dialog_wait_for_acknowledge(uint chars, uint flags, int arg3, int arg4);
extern void dialog_input_wait_with_cooldown(int mode);
extern void dialog_cutscene_op_noop(uchar far *record, int a, unsigned int flags);
extern void dialog_apply_style_state(DDXRecord far *param_1, void far *param_2);
extern void dialog_frame_draw(DDXRecord far *param_1, int far *param_2);
extern void dialog_draw_speech_bubble(char far *text, int y_offset);
extern void dialog_cmbt_name_assign_kind(int slot, int kind, int aux, int name_token);
extern void dialog_render_text_with_tokens(DDXRecord far *param_1, char far *param_2, int param_3,
                                           int param_4, int param_5, int param_6);
extern int dialog_show_by_key(ulong key, int interactive);
extern void dialog_screen_wipe_rect_or_full(DDXRecord far *param_1);
extern void dialog_viewport_clip_point(int x, int y);
extern void dialog_animate_open(DDXRecord far *param_1, int param_2);
extern void dialog_combatant_name_table_init(void);
extern int dialog_play_record(ulong record_key, int modal_flag);

#endif
