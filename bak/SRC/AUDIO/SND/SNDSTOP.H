#ifndef BAK_SNDSTOP_H
#define BAK_SNDSTOP_H

#include "structs.h"

extern short g_nSpinWaitTicks;

extern void audioteardown_rel_strm_bufs(void);
extern void audioteardown_spin_wait_drain(void);
extern void audioteardown_drain_sem_dec(void);

#endif
