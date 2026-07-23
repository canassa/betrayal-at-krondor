#include <dos.h>
#include "globals.h"
#include "SRC/SCREENS/MAINMENU.H"
#include "SRC/WORLD/ZONE/CZONE.H"
#include "SRC/WORLD/ZONE/PROXIM.H"
#include "structs.h"
#include "SRC/R3D/VIS/PROXSCAN.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/MEM.H"
#include "SRC/R3D/CORE/DISTDIR.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/R3D/TBLSTORE/SHAPETBL.H"
#include "SRC/R3D/VIS/VISLIST.H"
#include "SRC/R3D/SCENE/WORLDFRM.H"
#include "SRC/COMBAT/SPELL/SPELLFX.H"
#include "SRC/WORLD/ENC/RGNENC.H"
#ifdef V102CD
#include "SRC/GAME/CFGPARSE.H"
#endif

short g_nVisibleEntryCount;
unsigned short g_wVisibleEntrySegment;
unsigned short *g_pwVisibleEntryOffsets;
long g_aFilterTable[43];
long *g_pVisibleEntryDistances;

typedef struct {
    long x;
    long y;
    long z;
} OctPos;

void far proxscan_filter_table_load(void) {
    BakFile *stream;

    stream = bak_fopen("filter.dat", "rb");
    if (g_engine_prefs != (EnginePrefs *)0 && g_engine_prefs->detail_level != 0) {
        bak_fseek(stream, (unsigned long)((unsigned int)g_engine_prefs->detail_level * 0xac), 1);
    }
    bak_fread((void *)g_aFilterTable, 4, 0x2b, stream);
    bak_fclose(stream);
    return;
}

void far proxscan_scratch_alloc(void) {

    g_pwVisibleEntryOffsets = galloc_safe_zcalloc(0x4b0);
    return;
}

void proxscan_scratch_free(void) {
    galloc_zfree(g_pwVisibleEntryOffsets);
    return;
}

void proxscan_full(ViewContext *widget) {
    int i;
    long *party_pos;

    party_pos = &widget->camera->base.pos.xy.nWorld_x;
    g_wVisibleEntrySegment = FP_SEG(g_apCombat_zone_actor_lists[0]->pEntries);
    g_nVisibleEntryCount = 0;
    for (i = 0; i < g_nCombat_zone_count; i = i + 1) {
        proxscan_run(g_apCombat_zone_actor_lists[i], party_pos);
    }
    proxscan_filter_by_distance(party_pos);
    proxscan_object_list(party_pos);
    return;
}

void proxscan_run(VisibleEntryList *list, long *party_pos) {
    short count;
    int i;
    WorldObject far *entry_ptr;
    Shape far *prec;
    long threshold;
    long metric;
    unsigned short *puOff;
    OctPos local_pos;
    register long *plDist;

    count = list->wEntry_count;
    entry_ptr = list->pEntries;
    plDist = g_pVisibleEntryDistances + g_nVisibleEntryCount;
    puOff = g_pwVisibleEntryOffsets + g_nVisibleEntryCount;

    for (i = 0; g_nVisibleEntryCount < 600 && i < count; i++) {
        prec = ts_get_shape(entry_ptr->shapeId);
        if (prec->kind != 7 && (g_game_mode != 1 || entry_ptr->shapeId != 0xb5) &&
            (threshold = g_aFilterTable[prec->kind], threshold) != -1) {
            local_pos = *(OctPos far *)&entry_ptr->pos;
            *plDist = distdir_octagonal_distance(party_pos, (long *)&local_pos);
            if (threshold != 1) {
                metric = *plDist;
                metric -= (long)((int)prec->radius << prec->shift);
            } else {
                metric = 0;
            }
            if (g_game_mode == 2 && *plDist < 0x640 &&
                (prec->kind == 0xe || prec->kind == 0xf || prec->kind == 0x14 ||
                 prec->kind == 0x17) &&
                g_pEncounterTable != 0) {
                worldframe_enc_rec_prox(&list->bZone, i);
            }
            if (metric < threshold) {
                *puOff = FP_OFF(entry_ptr);
                puOff++;
                plDist++;
                g_nVisibleEntryCount++;
            }
        }
        entry_ptr++;
    }
}

void proxscan_filter_by_distance(long *origin) {
    short max_count;
    int i;
    WorldObject far *entry_ptr;
    Shape far *prec;
    long threshold;
    long metric;
    OctPos local_pos;
    register long *plDist;
    register unsigned short *puOff;

    max_count = g_nVisible_entry_count;
    entry_ptr = (WorldObject far *)g_pVisible_entry_pool;
    plDist = g_pVisibleEntryDistances + g_nVisibleEntryCount;
    puOff = g_pwVisibleEntryOffsets + g_nVisibleEntryCount;
    for (i = 0; g_nVisibleEntryCount < 600 && i < max_count; i++) {
        prec = ts_get_shape(entry_ptr->shapeId);
        threshold = g_aFilterTable[prec->kind];
        if (threshold != -1) {
            local_pos = *(OctPos far *)&entry_ptr->pos;
            *plDist = distdir_octagonal_distance(origin, (long *)&local_pos);
            if (threshold != 1) {
                metric = *plDist;
                metric -= (long)((int)prec->radius << prec->shift);
            } else {
                metric = 0;
            }
            if (metric < threshold) {
                *puOff = FP_OFF(entry_ptr);
                puOff++;
                plDist++;
                g_nVisibleEntryCount++;
            }
        }
        entry_ptr++;
    }
}

void proxscan_object_list(long *origin) {
    short max_count;
    int i;
    WorldObject far *record_ptr;
    long score;
    long metric;
    OctPos local_pos;
    register long *plDist;
    register unsigned short *puOff;

    max_count = g_nFixed_object_count;
    record_ptr = g_pFixed_object_entries;
    plDist = g_pVisibleEntryDistances + g_nVisibleEntryCount;
    score = g_aFilterTable[16];
    puOff = g_pwVisibleEntryOffsets + g_nVisibleEntryCount;
    for (i = 0; g_nVisibleEntryCount < 600 && i < max_count; i++) {
        if (score != -1) {
            local_pos = *(OctPos far *)&record_ptr->pos.xy.nWorld_x;
            *plDist = distdir_octagonal_distance(origin, (long *)&local_pos);
            if (score != 1) {
                metric = *plDist;
            } else {
                metric = 0;
            }
            if (metric < score) {
                *puOff = FP_OFF(record_ptr);
                puOff++;
                plDist++;
                g_nVisibleEntryCount++;
            }
        }
        record_ptr++;
    }
}

void proxscan_all_zones_for_encounter(ViewContext *pContext) {
    long *party_pos;
    int i;

    party_pos = &pContext->camera->base.pos.xy.nWorld_x;
    g_wVisibleEntrySegment = FP_SEG(g_apCombat_zone_actor_lists[0]->pEntries);
    g_nVisibleEntryCount = 0;
    for (i = 0; i < g_nCombat_zone_count; i = i + 1) {
        proxscan_encounter_records(g_apCombat_zone_actor_lists[i], party_pos);
    }
    return;
}

void proxscan_encounter_records(VisibleEntryList *list, long *party_pos) {
    short count;
    int i;
    WorldObject far *entry_ptr;
    Shape far *prec;
    long threshold;
    long metric;
    unsigned short *puOff;
    OctPos local_pos;
    register long *plDist;

    count = list->wEntry_count;
    entry_ptr = list->pEntries;
    plDist = g_pVisibleEntryDistances + g_nVisibleEntryCount;
    puOff = g_pwVisibleEntryOffsets + g_nVisibleEntryCount;
    for (i = 0; g_nVisibleEntryCount < 600 && i < count; i++) {
        prec = ts_get_shape(entry_ptr->shapeId);
        if ((prec->kind <= 4 || prec->kind == 7 || prec->kind == 10 || prec->kind == 0xe ||
             prec->kind == 0xf || prec->kind == 0x14 || prec->kind == 0x17 || prec->kind == 0x26 ||
             prec->kind == 0x27) &&
            (threshold = g_aFilterTable[prec->kind], threshold) != -1) {
            local_pos = *(OctPos far *)&entry_ptr->pos;
            *plDist = distdir_octagonal_distance(party_pos, (long *)&local_pos);
            if (threshold != 1) {
                metric = *plDist;
                metric -= (long)((int)prec->radius << prec->shift);
            } else {
                metric = 0;
            }
            if (g_game_mode == 2 && *plDist < 0x640 &&
                (prec->kind == 0xe || prec->kind == 0xf || prec->kind == 0x14 ||
                 prec->kind == 0x17) &&
                g_pEncounterTable != 0) {
                worldframe_enc_rec_prox(&list->bZone, i);
            }
            if (metric < threshold) {
                *puOff = FP_OFF(entry_ptr);
                puOff++;
                plDist++;
                g_nVisibleEntryCount++;
            }
        }
        entry_ptr++;
    }
}

int proxscan_vis_rec_kind_0e3e(void) {
    WorldObject far *entry_ptr;
    unsigned short *puOff;
    long *plDist;
    register int i;

    puOff = g_pwVisibleEntryOffsets;
    plDist = g_pVisibleEntryDistances;
    proxscan_full(g_world_widget);
    vislist_sort(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets, g_pVisibleEntryDistances,
                 g_nVisibleEntryCount);
    i = 0;
    if (i < g_nVisibleEntryCount) {
        do {
            entry_ptr = MK_FP(g_wVisibleEntrySegment, *puOff);
            if (g_game_mode != 2 || *plDist <= 0x2134) {
                if (entry_ptr->shapeId == g_nProximityTableCount) {
                    if (rgnenc_slot_actor_kind_eq_placed(entry_ptr) != 0) {
                        return 1;
                    }
                }
            }
            i++;
            puOff++;
            plDist++;
        } while (i < g_nVisibleEntryCount);
    }
    return 0;
}

int far proxscan_paged_find_next_type0f(WorldObject far **out_entry) {
    int i;

    for (i = g_nVisibleEntryCount - 1; i >= 0; i--) {
        *out_entry = MK_FP(g_wVisibleEntrySegment, g_pwVisibleEntryOffsets[i]);
        if (ts_get_shape((*out_entry)->shapeId)->kind == 0x0f) {
            return 1;
        }
    }
    return 0;
}

void proxscan_visibility(ViewContext *pViewContext) {
    int i;
    long *party_pos;

    party_pos = &pViewContext->camera->base.pos.xy.nWorld_x;
    g_wVisibleEntrySegment = FP_SEG(g_apCombat_zone_actor_lists[0]->pEntries);
    g_nVisibleEntryCount = 0;
    for (i = 0; i < g_nCombat_zone_count; i = i + 1) {
        proxscan_region_bucket(g_apCombat_zone_actor_lists[i], party_pos);
    }
    proxscan_world_objects(party_pos);
    return;
}

void proxscan_region_bucket(VisibleEntryList *region, long *party_pos) {
    short count;
    int i;
    int keep;
    WorldObject far *entry_ptr;
    Shape far *prec;
    long threshold;
    long metric;
    int view_xy[3];
    OctPos local_pos;
    register long *plDist;
    register unsigned short *puOff;

    count = region->wEntry_count;
    entry_ptr = region->pEntries;
    plDist = g_pVisibleEntryDistances + g_nVisibleEntryCount;
    puOff = g_pwVisibleEntryOffsets + g_nVisibleEntryCount;
    for (i = 0; g_nVisibleEntryCount < 600 && i < count; i++) {
        prec = ts_get_shape(entry_ptr->shapeId);
        local_pos = *(OctPos far *)&entry_ptr->pos;
        keep = 1;
        if (combatgrid_obj_kind_prox_actv(prec->kind) != 0) {
            combatgrid_world_to_view_2d(&g_world_camera->base.pos.xy,
                                        g_world_camera->base.orientation.yaw,
                                        (WorldPos2 far *)&local_pos, view_xy);
            if (view_xy[0] != -1 ||
                distdir_octagonal_distance(party_pos, (long *)&local_pos) < 4000)
                keep = 0;
        } else {
            if (prec->kind == 0x2a || entry_ptr->shapeId == 0x7f)
                keep = 0;
        }
        if (keep != 0 && (threshold = g_aFilterTable[prec->kind], threshold) != -1) {
            *plDist = distdir_octagonal_distance(party_pos, (long *)&local_pos);
            if (threshold != 1) {
                metric = *plDist;
                metric -= (long)((int)prec->radius << prec->shift);
            } else {
                metric = 0;
            }
            if (metric < threshold) {
                *puOff = FP_OFF(entry_ptr);
                puOff++;
                plDist++;
                g_nVisibleEntryCount++;
            }
        }
        entry_ptr++;
    }
}

void proxscan_world_objects(long *p_pos) {
    register long *plDist;
    register unsigned short *puOff;
    short count;
    int i;
    int keep;
    WorldObject far *entry_ptr;
    Shape far *prec;
    long threshold;
    long metric;
    int view_xy[3];
    OctPos local_pos;

    count = g_nVisible_entry_count;
    entry_ptr = (WorldObject far *)g_pVisible_entry_pool;
    plDist = g_pVisibleEntryDistances + g_nVisibleEntryCount;
    puOff = g_pwVisibleEntryOffsets + g_nVisibleEntryCount;
    for (i = 0; g_nVisibleEntryCount < 600 && i < count; i++) {
        prec = ts_get_shape(entry_ptr->shapeId);
        local_pos = *(OctPos far *)&entry_ptr->pos;
        keep = 1;
        if (combatgrid_obj_kind_prox_actv(prec->kind) != 0) {
            combatgrid_world_to_view_2d(&g_world_camera->base.pos.xy,
                                        g_world_camera->base.orientation.yaw,
                                        (WorldPos2 far *)&local_pos, view_xy);
            if (view_xy[0] != -1 || distdir_octagonal_distance(p_pos, (long *)&local_pos) < 4000)
                keep = 0;
        } else {
            if (prec->kind == 0x2a || entry_ptr->shapeId == 0x7f)
                keep = 0;
        }
        if (keep != 0) {
            threshold = g_aFilterTable[prec->kind];
            if (threshold != -1) {
                *plDist = distdir_octagonal_distance(p_pos, (long *)&local_pos);
                if (threshold != 1) {
                    metric = *plDist;
                    metric -= (long)((int)prec->radius << prec->shift);
                } else {
                    metric = 0;
                }
                if (metric < threshold) {
                    *puOff = FP_OFF(entry_ptr);
                    puOff++;
                    plDist++;
                    g_nVisibleEntryCount++;
                }
            }
            entry_ptr++;
        }
    }
}

void proxscan_paged_dispatch_all(void) {
    int i;
    long *party_pos;
#ifdef V102CD
    short saved_heading;
#endif

    party_pos = &g_world_camera->base.pos.xy.nWorld_x;
#ifdef V102CD
    saved_heading = g_world_camera->base.orientation.yaw;
    if (g_cfgNonRotatingMap) {
        g_world_camera->base.orientation.yaw = 0;
    }
#endif
    for (i = 0; i < g_nCombat_zone_count; i++) {
        proxscan_paged_list_dispatch(g_apCombat_zone_actor_lists[i], party_pos);
    }
    proxscan_paged_dispatch_by_type(party_pos);
#ifdef V102CD
    g_world_camera->base.orientation.yaw = saved_heading;
#endif
}

void proxscan_paged_list_dispatch(VisibleEntryList *list, long *party_pos) {
    WorldObject far *entry_ptr;
    Shape far *prec;
    long metric;
    WorldPos local_pos;

    register int i;
    int count;

    count = (int)list->wEntry_count;
    entry_ptr = list->pEntries;
    i = 0;
    if (i < count) {
        do {
            prec = ts_get_shape(entry_ptr->shapeId);
            switch ((unsigned int)prec->kind) {
            case 0x06:
            case 0x0a:
            case 0x11:
            case 0x1d:
            case 0x1e:
            case 0x1f:
            case 0x21:
            case 0x24:
            case 0x29:
                local_pos = *(WorldPos far *)&entry_ptr->pos;
                metric = distdir_octagonal_distance(party_pos, (long *)&local_pos) -
                         ((int)prec->radius << prec->shift);
                if (metric < 64000) {
                    world_render_record_marker_dot(entry_ptr);
                }
                break;
            }
            entry_ptr++;
            i++;
        } while (i < count);
    }
}

void proxscan_paged_dispatch_by_type(long *p_coords) {
    WorldObject far *entry_ptr;
    Shape far *prec;
    long metric;
    OctPos local_pos;
    int i;

    entry_ptr = (WorldObject far *)g_pVisible_entry_pool;
    i = 0;
    if (i < g_nVisible_entry_count) {
        do {
            prec = ts_get_shape(entry_ptr->shapeId);
            switch ((unsigned int)prec->kind) {
            case 6:
            case 10:
            case 17:
            case 29:
            case 30:
            case 31:
            case 33:
            case 36:
            case 41:
                local_pos = *(OctPos far *)&entry_ptr->pos;
                metric = distdir_octagonal_distance(p_coords, (long *)&local_pos) -
                         (long)((int)prec->radius << prec->shift);
                if (metric < 64000) {
                    world_render_record_marker_dot(entry_ptr);
                }
                break;
            }
            entry_ptr++;
            i++;
        } while (i < g_nVisible_entry_count);
    }
}

void far proxscan_draw_cmap_inset_markers(void) {
    long *position;
    int i;
#ifdef V102CD
    short saved_heading;
#endif

    position = &g_world_camera->base.pos.xy.nWorld_x;
#ifdef V102CD
    saved_heading = g_world_camera->base.orientation.yaw;
    if (g_cfgNonRotatingMap) {
        g_world_camera->base.orientation.yaw = 0;
    }
#endif
    for (i = 0; i < g_nCombat_zone_count; i++) {
        proxscan_draw_zone_vis_marks(g_apCombat_zone_actor_lists[i], position);
    }
    proxscan_draw_visible_markers(position);
    proxscan_draw_fixed_object_marks(position);
#ifdef V102CD
    g_world_camera->base.orientation.yaw = saved_heading;
#endif
    return;
}

void far proxscan_draw_zone_vis_marks(VisibleEntryList *list, long *position) {
    OctPos local_pos;
    WorldObject far *entry_ptr;
    Shape far *prec;
    long dist;
    int count;
    int i;

    count = (int)list->wEntry_count;
    entry_ptr = list->pEntries;
    i = 0;
    if (i < count) {
        do {
            prec = ts_get_shape(entry_ptr->shapeId);
            switch (prec->kind) {
            case 6:
            case 10:
            case 12:
            case 16:
            case 17:
            case 26:
            case 27:
            case 28:
            case 30:
            case 31:
            case 33:
            case 35:
            case 41:
                local_pos = *(OctPos far *)&entry_ptr->pos.xy.nWorld_x;
                dist = distdir_octagonal_distance(position, (long *)&local_pos) -
                       (long)((int)prec->radius << prec->shift);
                if (dist < 64000) {
                    if (spellfx_actor_has_ration(entry_ptr) != 0) {
                        world_render_record_marker_dot(entry_ptr);
                    }
                }
                break;
            }
            entry_ptr++;
            i++;
        } while (i < count);
    }
    return;
}

void far proxscan_draw_visible_markers(long *p_position) {
    WorldObject far *entry_ptr;
    Shape far *prec;
    long dist;
    OctPos local_pos;
    int i;

    entry_ptr = (WorldObject far *)g_pVisible_entry_pool;
    i = 0;
    if (i < g_nVisible_entry_count) {
        do {
            prec = ts_get_shape(entry_ptr->shapeId);
            switch (prec->kind) {
            case 6:
            case 10:
            case 12:
            case 16:
            case 17:
            case 26:
            case 27:
            case 28:
            case 30:
            case 31:
            case 33:
            case 35:
            case 41:
                local_pos = *(OctPos far *)&entry_ptr->pos.xy.nWorld_x;
                dist = distdir_octagonal_distance(p_position, (long *)&local_pos) -
                       (long)((int)prec->radius << prec->shift);
                if (dist < 64000) {
                    if (spellfx_actor_has_ration(entry_ptr) != 0) {
                        world_render_record_marker_dot(entry_ptr);
                    }
                }
                break;
            }
            entry_ptr++;
            i++;
        } while (i < g_nVisible_entry_count);
    }
    return;
}

void far proxscan_draw_fixed_object_marks(long *p_position) {
    OctPos local_pos;
    WorldObject far *record_ptr;
    int i;

    record_ptr = g_pFixed_object_entries;
    for (i = 0; i < g_nFixed_object_count; i++) {
        local_pos = *(OctPos far *)&record_ptr->pos.xy.nWorld_x;
        if (distdir_octagonal_distance(p_position, (long *)&local_pos) < 64000) {
            if (spellfx_actor_has_ration((WorldObject far *)record_ptr) != 0) {
                world_render_record_marker_dot((WorldObject far *)record_ptr);
            }
        }
        record_ptr++;
    }
    return;
}

void far proxscan_broadcast_scene_events(void) {
    long *position;
    int i;
#ifdef V102CD
    short saved_heading;
#endif

    position = &g_world_camera->base.pos.xy.nWorld_x;
#ifdef V102CD
    saved_heading = g_world_camera->base.orientation.yaw;
    if (g_cfgNonRotatingMap) {
        g_world_camera->base.orientation.yaw = 0;
    }
#endif
    for (i = 0; i < g_nCombat_zone_count; i = i + 1) {
        proxscan_rndr_zone_recs_near(g_apCombat_zone_actor_lists[i], position);
    }
    proxscan_draw_vis_marks_near(position);
    proxscan_notify_actors_near(position);
#ifdef V102CD
    g_world_camera->base.orientation.yaw = saved_heading;
#endif
    return;
}

void far proxscan_rndr_zone_recs_near(VisibleEntryList *list, long *position) {
    OctPos local_pos;
    WorldObject far *entry_ptr;
    Shape far *prec;
    long dist;
    int count;
    int i;

    count = (int)list->wEntry_count;
    entry_ptr = list->pEntries;
    i = 0;
    if (i < count) {
        do {
            prec = ts_get_shape(entry_ptr->shapeId);
            switch (prec->kind) {
            case 6:
            case 9:
            case 10:
            case 12:
            case 16:
            case 17:
            case 24:
            case 26:
            case 27:
            case 28:
            case 29:
            case 30:
            case 31:
            case 33:
            case 35:
            case 37:
            case 41:
                local_pos = *(OctPos far *)&entry_ptr->pos.xy.nWorld_x;
                dist = distdir_octagonal_distance(position, (long *)&local_pos) -
                       (long)((int)prec->radius << prec->shift);
                if (dist < 64000) {
                    if ((prec->kind == 0x1d || prec->kind == 9 || prec->kind == 0x25) ||
                        spellfx_actor_has_special_item(entry_ptr) != 0) {
                        world_render_record_marker_dot(entry_ptr);
                    }
                }
                break;
            }
            entry_ptr++;
            i++;
        } while (i < count);
    }
    return;
}

void far proxscan_draw_vis_marks_near(long *position) {
    OctPos local_pos;
    WorldObject far *entry_ptr;
    Shape far *prec;
    long dist;
    int i;

    entry_ptr = (WorldObject far *)g_pVisible_entry_pool;
    i = 0;
    if (i < g_nVisible_entry_count) {
        do {
            prec = ts_get_shape(entry_ptr->shapeId);
            switch (prec->kind) {
            case 6:
            case 9:
            case 10:
            case 12:
            case 16:
            case 17:
            case 24:
            case 26:
            case 27:
            case 28:
            case 29:
            case 30:
            case 31:
            case 33:
            case 35:
            case 37:
            case 41:
                local_pos = *(OctPos far *)&entry_ptr->pos.xy.nWorld_x;
                dist = distdir_octagonal_distance(position, (long *)&local_pos) -
                       (long)((int)prec->radius << prec->shift);
                if (dist < 64000) {
                    if ((prec->kind == 0x1d || prec->kind == 9 || prec->kind == 0x25) ||
                        spellfx_actor_has_special_item(entry_ptr) != 0) {
                        world_render_record_marker_dot(entry_ptr);
                    }
                }
                break;
            }
            entry_ptr++;
            i++;
        } while (i < g_nVisible_entry_count);
    }
    return;
}

void far proxscan_notify_actors_near(long *position) {
    OctPos local_pos;
    WorldObject far *record_ptr;
    int i;

    record_ptr = g_pFixed_object_entries;
    for (i = 0; i < g_nFixed_object_count; i++) {
        local_pos = *(OctPos far *)&record_ptr->pos.xy.nWorld_x;
        if (distdir_octagonal_distance(position, (long *)&local_pos) < 64000) {
            if (spellfx_actor_has_special_item((WorldObject far *)record_ptr) != 0) {
                world_render_record_marker_dot((WorldObject far *)record_ptr);
            }
        }
        record_ptr++;
    }
    return;
}
