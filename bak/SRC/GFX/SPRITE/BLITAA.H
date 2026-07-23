#ifndef BAK_BLITAA_H
#define BAK_BLITAA_H

#include "structs.h"

extern unsigned long g_pAaPaletteBuf;

extern void blit_sprite_aa_edges(ImageRecord *sprite, int dst_x, int dst_y, unsigned char far *palette);

#endif
