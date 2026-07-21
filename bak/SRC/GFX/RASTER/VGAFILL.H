#ifndef BAK_VGAFILL_H
#define BAK_VGAFILL_H

#include "structs.h"

extern void vgaplanar_clear_column_strip(int vga_base_offset, int row_count);
extern void vgaplanar_fill_band(int start_row, int row_count, int color);

#endif
