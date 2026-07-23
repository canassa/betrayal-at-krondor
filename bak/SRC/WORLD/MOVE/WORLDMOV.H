#ifndef BAK_WORLDMOV_H
#define BAK_WORLDMOV_H

#include "structs.h"

extern unsigned short g_bWorldCrossing;
extern unsigned short g_nWorldCrossingKind;
extern unsigned long g_dwWorldCrossingCoord;
extern short g_nWorldStepSpeed;
extern short g_nWorldGridStride;
extern long g_lWorldTimePerStep;

extern void worldmove_dat_load(void);
extern void worldmove_combat_zone_snap_pos(void);
extern void worldmove_rgn_chap_trans_apply(void);
extern int worldmove_party_attempt_move(int mode);
extern void worldmove_apply_turn_step(short direction);
extern void worldmove_animate_hdg_tgt(int hdg_step, int hdg_target);
extern void worldmove_plr_hdg_align_grid(void);
extern void worldmove_camera_crossing_apply(void);
extern int worldmove_aabb_outcode_rotated(unsigned char *tile_rect);
extern int worldmove_sweep_alt_headings(WorldPos *pos, int heading, long step, int mode,
                                        int *out_dir, int *out_heading);
extern int worldmove_step_free_move(WorldPos *pos, int heading, long step, int mode);
extern int worldmove_crossing_check_8dir(WorldPos *pos, int heading, long step, int mode,
                                         int *out_dir, int *out_target);
extern void worldmove_heading_step(short *heading, short step, short direction);
extern int worldmove_align_to_grid_stride(unsigned int *value);
extern void worldmove_vec2_rotate_add_q14(long *out, int angle, long scale);
extern void worldmove_crossing_apply_offset(WorldPos *pPos, int wDir, int delta);
extern int worldmove_probe_walkable_at(WorldPos *pos, int angle, long scale, unsigned int *out_kind,
                                       long *out_coord);
extern int worldmove_prox_query_at_cell(WorldPos *pos, unsigned int *out_type, long *out_coord);
extern int worldmove_probe_adjacent_cell(WorldPos *pos, int dir, unsigned int *out_type, long *out_coord);
extern int worldmove_sweep_adjacent_cells(WorldPos *pos, unsigned int dir, int mode, int *out_result);
extern int worldmove_prox_find_near_pos(WorldPos *pos);
extern void worldmove_cross_get_probe_result(unsigned short *out_kind, unsigned long *out_coord);
extern int worldmove_cross_walkable_kind(void);
extern void worldmove_step_pending_clear(void);
extern int worldmove_step_once_along_axis(void);
extern short worldmove_step_pending_get(void);
extern int worldmove_try_step_along_axis(void);
extern void worldmove_step_tick_reset(void);
extern unsigned short worldmove_step_tick_get(void);
extern void worldmove_step_tick_advance(void);
extern unsigned short worldmove_step_ticks_per_step(void);

#endif
