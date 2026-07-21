#ifndef BAK_SPRTHNKS_H
#define BAK_SPRTHNKS_H

#include "structs.h"

extern void blit_sprite(void);
extern void blit_sprite_indirect(ushort sprite_desc_offset, short x, short y, ushort flip_flags);
extern void gfx_putsprite_fp(ImageRecord *sprite, int x, int y);
extern void blit_stretched_dispatch(void);

#endif
