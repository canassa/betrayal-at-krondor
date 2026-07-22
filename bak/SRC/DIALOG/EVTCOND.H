#ifndef BAK_EVTCOND_H
#define BAK_EVTCOND_H

#include "structs.h"

extern int evtcond_range_d_read_handler(uint cond);
extern void evtcond_range_d_write_stub(uint event_id, uint value);
extern void evtcond_dialog_action_dispatch(DdxOp far *action_record);
extern void evtcond_dispatch_key_to_handler(uint event_id);
extern void evtcond_pty_inv_repair_cnt(int *count_out, int *repair_out, int do_repair);
extern void evtcond_pty_dirty_flags_process(void);

#endif
