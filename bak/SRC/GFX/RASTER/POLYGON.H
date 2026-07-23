#ifndef BAK_POLYGON_H
#define BAK_POLYGON_H

#include "structs.h"

extern unsigned short g_wDrawPolyTopVertexOff;
extern unsigned short g_wDrawPolyBottomVertexOff;
extern unsigned short g_wDrawPolyChain1VertexCount;
extern unsigned short g_wDrawPolyChain2VertexCount;
extern unsigned short g_wDrawPolyChainRemaining;
extern unsigned short g_wDrawPolyEdgeWalkOff;
extern unsigned short g_wRasterEdgeColumnOff;
extern short g_nDrawPolyLastVertexX;
extern short g_nDrawPolyLastVertexY;
extern unsigned short g_wDrawPolySpanBufRetSeg;
extern unsigned short g_wDrawPolyOutlineVertexCount;
extern unsigned short g_wDrawPolyClipReplayByteCount;
extern unsigned char g_bRasterSpanDiStride;
extern unsigned char g_bDrawPolyReplayPending;

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
