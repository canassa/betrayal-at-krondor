#ifndef BAK_PALETTE_H
#define BAK_PALETTE_H

#include "structs.h"

extern void palette_buffers_alloc(char *fname);
extern void palette_buffers_free(void);
extern void palette_apply_pending_load(void);
extern void palette_state_reset(void);
extern void palette_fade_in(uint palette_off, uint palette_seg, int step, int wait_each_step);
extern void palette_fade_out(uint palette_off, uint palette_seg, int step, int wait_each_step);
extern void palette_screen_clear_black(void);
extern void palette_blend_with_daynight(uchar far *pPalSrc);
extern void palette_apply_cycled(void);
extern void palette_interpolate_range(uchar far *src, uchar far *dst, char *pTarget,
                                      int range_start, int range_end, int blend);
extern void palette_build_blend_lut(int blend_factor);
extern void palette_daylight_tick(void);
extern int palette_compute_daylight(void);
extern int palette_daylight_modulate(int base_brightness);
extern TimerEventEntry *palette_fade_schedule(ushort sub_id, ulong duration);
extern void palette_fade_run_scheduled(TimerEventEntry *entry);
extern byte far *palette_set(uchar far *pal);

#endif
