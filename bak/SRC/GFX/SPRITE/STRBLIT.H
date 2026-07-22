#ifndef BAK_STRBLIT_H
#define BAK_STRBLIT_H

#include "structs.h"

extern int stretch_step_init(int *step, int dest_steps);
extern void blit_image_stretched(ImageRecord *image, int dst_x, int dst_y, unsigned int flags, int dst_w,
                                 int dst_h);
extern void blit_image_scaled_centered(ImageRecord *image, int cx, int cy, unsigned long scale_q16);

#endif
