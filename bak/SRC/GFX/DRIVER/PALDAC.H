#ifndef BAK_PALDAC_H
#define BAK_PALDAC_H

#include "structs.h"

extern uchar bios_palette_read(int reg_index);
extern void vga_read_palette(uchar *buf, int start, int count);
extern void vga_write_palette(uchar *src, int start_index, int num_colors);

#endif
