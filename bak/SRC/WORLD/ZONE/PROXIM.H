#ifndef BAK_PROXIM_H
#define BAK_PROXIM_H

#include "structs.h"

extern void proximity_table_load(char *file);
extern void proximity_table_free(void);
extern unsigned char proximity_scan_list(ProximityScanHit *out_hit, WorldPos2 *pos, unsigned short record_seg,
                                 unsigned short *record_offsets, int count);
extern char proximity_check_index(ProximityScanHit *out_hit, WorldPos2 *pos,
                                  ProximityRecord far *pRecord);
extern void proximity_vec2_long_rotate_q14(long *xy, int angle);
extern unsigned char far *proximity_record_vertex_ptr(ProximityZone far *zone, int vertex_idx);
extern unsigned char proximity_point_test(ProximityScanHit *out_hit, WorldPos2 *pos,
                                  ProximityZone far *zone, ProximityRecord far *pRecord,
                                  char check_first_vertex);
extern unsigned char proximity_polygon_contains(ProximityPolygon far *poly, int point_x, int point_y);
extern int proximity_interp_height(ProximityPolygon far *poly, int point_x, int point_y);

#endif
