#ifndef BAK_RGNENC_H
#define BAK_RGNENC_H

#include "structs.h"

extern short g_nEncounter_record_count;
extern short g_nFixed_object_count;
extern short g_nVisible_entry_count;
extern unsigned short *g_pZoneShapeIndex;
extern unsigned short *g_pChapterShapeIds;
extern EncounterRecordTemplate *g_pEncounterRecordTemplates;
extern long g_anEncounterRecordIds[5];
extern WorldObject far *g_pFixed_object_entries;
extern WorldObject far *g_pVisible_entry_pool;
extern EncounterObjectState *g_pEncounterObjectState;
extern int g_nCombatTempZoneEncounterCount;
extern unsigned char g_bCombatTempZoneRefPair;

extern void rgnenc_alloc_3bufs_init(void);
extern void rgnenc_free_3bufs_clear(void);
extern int rgnenc_load_zone_shape_index(char *filename);
extern int rgnenc_rel_object_state_group(void);
extern void rgnenc_savefile_init_35slot_tbl(void);
extern void rgnenc_load_encounter_actors(void);
extern void rgnenc_release_anim_images_slot4(void);
extern void rgnenc_zone_rectr_save_objects(void);
extern void rgnenc_persist_zone_snapshot(void);
extern int rgnenc_persist_actor_placed(long record_id, int slot_index,
                                       EncounterObjectState *src_partial);
extern int rgnenc_persist_actor_removed(long record_id, int slot_index);
extern void rgnenc_reset_and_save(void);
extern void rgnenc_mark_defended(unsigned long filter_encounter_id);
extern void rgnenc_complete_consume(unsigned long encounter_id);
extern void rgnenc_render_object(WorldObject far *entry, int bAnimTick);
extern void rgnenc_corpse_tbl_iterate_22byte(void);
extern int rgnenc_slot_actor_kind_eq_placed(WorldObject far *pSlot);
extern void rgnenc_world_objects_reset_spawn(void);
extern int rgnenc_visible_pool_append_spawn(unsigned char far *pEntry);
extern void rgnenc_vis_pool_remove_matching(unsigned char far *pKey);
extern int rgnenc_chap_shp_init(void);
extern int rgnenc_release_sfx_slot_table(void);
extern int rgnenc_global_flag_tbl_contains(unsigned short id);

#endif
