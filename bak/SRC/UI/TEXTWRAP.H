#ifndef BAK_TEXTWRAP_H
#define BAK_TEXTWRAP_H

#include "structs.h"

extern int textwrap_compute_lines(long text, int max_width, int *out_lines, int max_lines);
extern void textwrap_draw_aligned(long text, int x, int y, int max_width, int max_height,
                                  int line_spacing, uint flags, int first_line);

#endif
