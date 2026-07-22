#ifndef BAK_POLYGON_H
#define BAK_POLYGON_H

#include "structs.h"

extern void fill_spans_dispatch(unsigned short off, unsigned short seg);
extern void blit_rect_buf_dispatch(unsigned char far *far_ptr);
extern int draw_polygon(int count, int *xs, int *ys);
extern void near draw_polygon_edges(void);
extern void near state_machine_enter_state2_a(void);
extern void near rasterize_polygon_edge(void);
extern void near state_machine_enter_state2_b(void);
extern void near rasterize_polygon_edge_steep(void);
extern void near rasterize_polygon_edge_steep_b(void);
extern void near state_machine_disp_tbl_5d80(void);

#endif
