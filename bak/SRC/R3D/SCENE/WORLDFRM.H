#ifndef BAK_WORLDFRM_H
#define BAK_WORLDFRM_H

#include "structs.h"

extern EncounterTable *g_pEncounterTable;

extern void worldframe_encounter_table_load(void);
extern void worldframe_encounter_table_apply(void);
extern void worldframe_enc_tbl_reapply_chap(void);
extern void worldframe_enc_rec_prox(unsigned char *record, int direction);
extern int worldframe_enc_check_visited(unsigned char *pRecord, int bitIndex);
extern void worldframe_debug_print_compass(WorldObject far *entry);
extern void worldframe_vislist_cull_occl(unsigned short seg, unsigned short *offsets, long *data, int *count);
extern void worldframe_render_chapter_full(void);
extern void worldframe_render_chapter(int animate);
extern void worldframe_chapter_tick_objects(void);
extern void worldframe_vislist_reorder(unsigned short visible_seg, unsigned short *visible_offsets, int count);

#endif
