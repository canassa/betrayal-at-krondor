#ifndef BAK_ADSCRIPT_H
#define BAK_ADSCRIPT_H

#include "structs.h"

extern void adscript_set_dbb_if_202d_eq_0c(void);
extern int adscript_resource_load(BakFileRef *file);
extern int adscript_select_object(int id);
extern short adscript_channel_dispatch_loop(unsigned short script_obj_id);
extern void adscript_object_unload(int param_1);
extern void adscript_renderer_reset(void);
extern int adscript_run_then_apply_palette(int block_index);
extern int adscript_run_by_index(int block_index);
extern void adscript_drain_object_list(void);
extern void adscript_apply_pending_palette(void);
extern void adscript_op_noop(int a, int b, int c, int d);
extern void adscript_blit_full_other_page(void);
extern void adscript_rndr_blit_other_page(int x, int y, int w, int h);
extern char far *adscript_skip_aligned_cstring(char far *p);

#endif
