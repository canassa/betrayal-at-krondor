#ifndef BAK_PROXSCAN_H
#define BAK_PROXSCAN_H

#include "structs.h"

extern short g_nVisibleEntryCount;
extern unsigned short g_wVisibleEntrySegment;
extern unsigned short *g_pwVisibleEntryOffsets;
extern long g_aFilterTable[43];
extern long *g_pVisibleEntryDistances;

extern void proxscan_filter_table_load(void);
extern void proxscan_scratch_alloc(void);
extern void proxscan_scratch_free(void);
extern void proxscan_full(ViewContext *widget);
extern void proxscan_run(VisibleEntryList *list, long *party_pos);
extern void proxscan_filter_by_distance(long *origin);
extern void proxscan_object_list(long *origin);
extern void proxscan_all_zones_for_encounter(ViewContext *pContext);
extern void proxscan_encounter_records(VisibleEntryList *list, long *party_pos);
extern int proxscan_vis_rec_kind_0e3e(void);
extern int proxscan_paged_find_next_type0f(WorldObject far **out_entry);
extern void proxscan_visibility(ViewContext *pViewContext);
extern void proxscan_region_bucket(VisibleEntryList *region, long *party_pos);
extern void proxscan_world_objects(long *p_pos);
extern void proxscan_paged_dispatch_all(void);
extern void proxscan_paged_list_dispatch(VisibleEntryList *list, long *party_pos);
extern void proxscan_paged_dispatch_by_type(long *p_coords);
extern void proxscan_draw_cmap_inset_markers(void);
extern void proxscan_draw_zone_vis_marks(VisibleEntryList *list, long *position);
extern void proxscan_draw_visible_markers(long *p_position);
extern void proxscan_draw_fixed_object_marks(long *p_position);
extern void proxscan_broadcast_scene_events(void);
extern void proxscan_rndr_zone_recs_near(VisibleEntryList *list, long *position);
extern void proxscan_draw_vis_marks_near(long *position);
extern void proxscan_notify_actors_near(long *position);

#endif
