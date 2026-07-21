#include "globals.h"
#include "structs.h"
#include "SRC/R3D/VIS/VISLIST.H"
#include "SRC/SYS/MEM.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"

#include <dos.h>

void far vislist_alloc(void) {

    g_pVisibleEntryDistances = galloc_safe_zcalloc(0x960);
    return;
}

void vislist_free(void) {
    galloc_zfree(g_pVisibleEntryDistances);
    return;
}

void vislist_sort(ushort seg, ushort *ids, long *vals, int count) {
    int far *pId;
    Shape far *rec;
    long tmpVal;
    long best;
    int pivot;
    int best_i;
    int prio;
    ushort tmpId;
    int i;
    int j;

    if (count >= 2) {
        for (i = 0, j = 0; i < count; i++) {
            pId = (int far *)MK_FP(seg, ids[i]);
            rec = ts_get_shape(*pId);
            if (rec->priority != 0) {
                tmpId = ids[j];
                ids[j] = ids[i];
                ids[i] = tmpId;
                tmpVal = vals[j];
                vals[j] = vals[i];
                vals[i] = tmpVal;
                j++;
            }
        }
        pivot = j;
        for (i = 0; i < pivot - 1; i++) {
            pId = (int far *)MK_FP(seg, ids[i]);
            rec = ts_get_shape(*pId);
            prio = rec->priority;
            best_i = i;
            for (j = i + 1; j < pivot; j++) {
                pId = (int far *)MK_FP(seg, ids[j]);
                rec = ts_get_shape(*pId);
                if (prio < rec->priority) {
                    prio = rec->priority;
                    best_i = j;
                }
            }
            if (i != best_i) {
                tmpId = ids[i];
                ids[i] = ids[best_i];
                ids[best_i] = tmpId;
                tmpVal = vals[i];
                vals[i] = vals[best_i];
                vals[best_i] = tmpVal;
            }
        }
        for (i = pivot; i < count - 1; i++) {
            best_i = i;
            best = vals[i];
            for (j = i + 1; j < count; j++) {
                if (best < vals[j]) {
                    best_i = j;
                    best = vals[j];
                }
            }
            if (i != best_i) {
                tmpId = ids[i];
                ids[i] = ids[best_i];
                ids[best_i] = tmpId;
                vals[best_i] = vals[i];
                vals[i] = best;
            }
        }
    }
    return;
}
