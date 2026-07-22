#include <dos.h>
#include "globals.h"
#include "structs.h"
#include "SRC/WORLD/ZONE/PROXIM.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"
#include "SRC/SYS/PANICF.H"
#include "SRC/STREAM/BUFLOAD/CHUNKRD.H"

ProximityZoneSettings far *g_pCurProximityZoneRec;
unsigned short g_nProximityTableCount;
ProximityZone far *far *g_pProximityTable;

void far proximity_table_load(char *file) {
    ProximityZone far *far *cursor;

    g_pProximityTable = chunkread_read_all_far(file, "GID:");
    if (g_pProximityTable == (ProximityZone far *far *)0)
        panic("cannot load gi block");
    if (FP_OFF(g_pProximityTable) != 0)
        panic("offset != 0");

    cursor = g_pProximityTable;
    g_nProximityTableCount = 0;
    for (; *cursor != (ProximityZone far *)0; cursor++) {
        *cursor = (ProximityZone far *)((long)g_pProximityTable + (long)*cursor);
        g_nProximityTableCount++;
    }
}

void far proximity_table_free(void) {
    _freemem(g_pProximityTable);
    return;
}

unsigned char far proximity_scan_list(ProximityScanHit *out_hit, WorldPos2 *pos, unsigned short record_seg,
                              unsigned short *record_offsets, int count) {
    int i;
    ProximityRecord far *pRecord;
    unsigned short *pOffset;

    pOffset = record_offsets + (count - 1);
    if (g_pProximityTable != (ProximityZone far *far *)0) {
        out_hit->pZone_rec = (ProximityZone far *)0;
        out_hit->pRecord = (ProximityRecord far *)0;
        for (i = count - 1; i >= 0; i--) {
            pRecord = (ProximityRecord far *)MK_FP(record_seg, *pOffset);
            pOffset--;
            if ((int)pRecord->wRecord_id < (int)g_nProximityTableCount) {
                if (proximity_check_index(out_hit, pos, pRecord))
                    return 1;
            }
        }
    }
    return 0;
}

char far proximity_check_index(ProximityScanHit *out_hit, WorldPos2 *pos,
                               ProximityRecord far *pRecord) {
    ProximityZone far *zone;

    zone = g_pProximityTable[pRecord->wRecord_id];
    g_pCurProximityZoneRec = (ProximityZoneSettings far *)ts_get_shape(pRecord->wRecord_id);
    if (!zone->bVertex_count)
        return 0;
    if (proximity_point_test(out_hit, pos, zone, pRecord, 0))
        return 1;
    return 0;
}

void proximity_vec2_long_rotate_q14(long *xy, int angle) {
    long sin;
    long cos;
    long xp;

    if (angle != 0) {
        cos = r3d_tbl_cos(angle);
        sin = r3d_tbl_sin(angle);
        xp = (xy[0] * cos + xy[1] * -sin) >> 14;
        xy[1] = (xy[0] * sin + xy[1] * cos) >> 14;
        xy[0] = xp;
    }
}

unsigned char far *proximity_record_vertex_ptr(ProximityZone far *zone, int vertex_idx) {
    unsigned char far *result;
    int stride;

    result = (unsigned char far *)MK_FP(FP_SEG(zone), zone->wVertex_table_offset);
    stride = (zone->bFlags & 2) ? 10 : 6;
    result = result + vertex_idx * stride;
    return result;
}

unsigned char far proximity_point_test(ProximityScanHit *out_hit, WorldPos2 *pos, ProximityZone far *zone,
                               ProximityRecord far *pRecord, char check_first_vertex) {
    int xi;
    int yi;
    long lx;
    long ly;
    unsigned int idx;
    ProximityPolygon far *polyIter;
    int stride;
    long vec[3];

    vec[0] = (pos->nWorld_x - pRecord->nWorld_x) >> g_pCurProximityZoneRec->bResolution_shift;
    vec[1] = (pos->nWorld_y - pRecord->nWorld_y) >> g_pCurProximityZoneRec->bResolution_shift;
    proximity_vec2_long_rotate_q14(vec, -pRecord->nAngle);
    xi = lx = vec[0];
    yi = ly = vec[1];
    if (lx < 0) {
        lx = -lx;
    }
    if (ly < 0) {
        ly = -ly;
    }
    if ((zone->nMax_x < lx) || (zone->nMax_y < ly)) {
        return '\0';
    }
    idx = 0;
    polyIter = MK_FP(FP_SEG(zone), zone->wVertex_table_offset);
    stride = (zone->bFlags & 2) ? 10 : 6;
    if (!(zone->bFlags & 1)) {
        if (check_first_vertex != '\0') {
            polyIter = (ProximityPolygon
                        far *)proximity_record_vertex_ptr(zone, (unsigned int)out_hit->bHit_index);
            if ((char)proximity_polygon_contains(polyIter, xi, yi) != '\0') {
                idx = (unsigned int)out_hit->bHit_index;
                goto hit_found;
            }
            polyIter = MK_FP(FP_SEG(zone), zone->wVertex_table_offset);
        }
        while ((int)idx < (int)(unsigned int)zone->bVertex_count) {
            if ((char)proximity_polygon_contains(polyIter, xi, yi) != '\0') {
                break;
            }
            polyIter = (ProximityPolygon far *)((unsigned char far *)polyIter + stride);
            idx++;
        }
        if (zone->bVertex_count == idx) {
            return '\0';
        }
    }
hit_found:
    out_hit->pZone_rec = zone;
    out_hit->pRecord = pRecord;
    out_hit->bHit_index = (unsigned char)idx;
    if (g_pCurProximityZoneRec->bFlat_flag != 0) {
        out_hit->nZ_delta = 0;
    } else {
        if ((zone->bFlags & 2) != 0) {
            out_hit->nZ_delta = (long)proximity_interp_height(polyIter, xi, yi);
        } else {
            out_hit->nZ_delta = (long)polyIter->nBase_height;
        }
        out_hit->nZ_delta <<= g_pCurProximityZoneRec->bResolution_shift;
        out_hit->nZ_delta += pRecord->nZ_base;
    }
    return '\x01';
}

unsigned char proximity_polygon_contains(ProximityPolygon far *poly, int point_x, int point_y) {
    long side;
    ProximityVertex far *v;
    int count;
    int i;
    int dy;
    int cy;
    unsigned char agree_y;
    register int dx;
    register int cx;
    unsigned char agree_x;

    if (g_pProximityTable == (ProximityZone far *far *)0)
        return 0;

    if ((count = poly->bVertex_count) == 0)
        return 0;
    if (count > 0x20)
        panic("too many edges");

    v = (ProximityVertex far *)MK_FP(FP_SEG(poly), poly->wVertex_list_offset);
    for (i = 0; i < count; i++) {
        side = 0;
        if ((cy = (int)(signed char)v->cCy) != 0 && (dy = point_y - v->nY) != 0) {
            agree_y = (unsigned char)((0 < cy) == (0 < dy));
            if ((cx = (int)(signed char)v->cCx) != 0 && (dx = point_x - v->nX) != 0) {
                agree_x = (unsigned char)((0 < cx) == (0 < dx));
                if (agree_x == agree_y) {
                    side = (long)(agree_x ? 1 : -1);
                } else {
                    side = r3d_imul_full32(cy, dy) + r3d_imul_full32(cx, dx);
                }
            } else {
                side = (long)(agree_y ? 1 : -1);
            }
        } else {
            if ((cx = (int)(signed char)v->cCx) != 0 && (dx = point_x - v->nX) != 0) {
                side = (long)(((0 < cx) == (0 < dx)) ? 1 : -1);
            }
        }
        if (side > 0)
            return 0;
        v++;
    }
    return 1;
}

int far proximity_interp_height(ProximityPolygon far *poly, int point_x, int point_y) {
    ProximityVertex far *ref;
    long accum;
    int cx, cy;
    int height;

    if (g_pProximityTable == (ProximityZone far *far *)0)
        return 0;

    ref = (ProximityVertex far *)MK_FP(FP_SEG(poly), poly->wReference_vertex_offset);
    accum = 0;
    if ((cx = (int)(signed char)ref->cCx) != 0) {
        accum = r3d_imul_full32(cx, ref->nX - point_x);
    }
    if ((cy = (int)(signed char)ref->cCy) != 0) {
        accum += r3d_imul_full32(cy, ref->nY - point_y);
    }
    if (accum != 0) {
        height = (int)((long)(accum * (unsigned long)poly->bShift) >> 12);
    } else {
        height = 0;
    }
    return poly->nBase_height + height;
}
