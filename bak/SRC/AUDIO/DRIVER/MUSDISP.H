#ifndef BAK_MUSDISP_H
#define BAK_MUSDISP_H

#include "structs.h"

extern int audio_driver_disp_seg1000_alt(int a, int b);
extern void FUN_1000_13d7();
extern void audio_music_tick(void);
extern void FUN_1000_13e9();
extern void FUN_1000_13f0();
extern void FUN_1000_13f7();
extern void audio_driver_disp_seg1000_far(void);
extern void FUN_1000_1405(void);
extern int near audio_driver_dispatch_seg1000(void);

#endif
