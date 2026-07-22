#ifndef BAK_TTM_H
#define BAK_TTM_H

#include "structs.h"

extern int ttmscript_interpret_loop(int block_index);
extern int ttmscript_find_block_by_tag(int tag_arg);
extern char *ttmscript_strcpy_to_scratch(int param_1, char far *param_2);
extern ScriptObject far *ttmscript_body_after_args(void);
extern void ttmscript_vport_set_large_enough(int x, int y, int w, int h);
extern void ttmscript_pal_cycle_band_add(int param_1, int param_2);
extern void ttmscript_screen_trans_disp(unsigned short param_1, unsigned short param_2, int param_3, int param_4,
                                        unsigned short param_5, unsigned short param_6);
extern unsigned short ttmscript_lookup_coord_global(unsigned short idx);
extern void ttmscript_vports_reset_all_100(void);
extern void ttmscript_sfx_channels_stop_all(void);

#endif
