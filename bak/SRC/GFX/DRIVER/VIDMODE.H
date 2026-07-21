#ifndef BAK_VIDMODE_H
#define BAK_VIDMODE_H

#include "structs.h"

extern void near bios_set_video_mode_bits(uchar mode_bits);
extern int near bios_get_video_mode_bits(void);
extern void near bios_video_int10_helper(void);

#endif
