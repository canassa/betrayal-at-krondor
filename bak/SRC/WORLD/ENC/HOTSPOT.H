#ifndef BAK_HOTSPOT_H
#define BAK_HOTSPOT_H

#include "structs.h"

extern unsigned short g_nHotspotCount;
extern unsigned short g_wHotspotIterIdx;
extern unsigned short g_wHotspotMatchIdx;
extern unsigned short g_wHotspotEventEnabled;
extern unsigned short g_bZoneEntryInProgress;
extern unsigned short g_wHotspotIterCursor;
extern char g_monst_filename_buf[12];
extern char g_aDefFileNames[12][13];
extern short g_aDefRecordSizes[12];
extern ZoneHotspot g_aZoneHotspots[10];
extern unsigned short g_awHotspotPendingFlags[10];

extern void hotspotevt_monst_load_tbl_cur_id(void);
extern void hotspotevt_flags_clear(void);
extern int hotspotevt_activate_at_player(void);
extern unsigned short hotspotevt_disp_pending_events(void);
extern int hotspotevt_dispatch_at_point(int target_type, unsigned char x, unsigned char y, int *out_flag);
extern int hotspotevt_play_sound_zone_entry(int index);
extern int hotspotevt_trap_gates_pass(int nIndex);
extern int hotspotevt_available(ZoneHotspot *pHotspot);
extern void hotspotevt_dialog_popup_run(ZoneHotspot *pHotspot, int *out_skipped,
                                        int *out_user_confirmed);
extern void hotspotevt_load_record0_town(ZoneHotspot *pHotspot);
extern void hotspotevt_skill_check_trigger(int isAuto, ZoneHotspot *pHotspot, int *out_a,
                                           int *out_b, int *out_c);
extern void hotspotevt_type1_encounter_run(ZoneHotspot *pHotspot, int *out_moved);
extern int hotspotevt_monst_load_speak(ZoneHotspot *pHotspot);
extern void hotspotevt_maybe_play_random_sfx(ZoneHotspot *pHotspot);
extern void hotspotevt_show_record_message(ZoneHotspot *pHotspot, int *out_skipped,
                                           int *out_confirmed);
extern void hotspotevt_action_enter_town(ZoneHotspot *evt);
extern void hotspotevt_trap_prefire_scout(int nReentry, ZoneHotspot *evt,
                                          int *pOut_ambush_just_armed, int *pOut_handled,
                                          int *pOut_should_fire);
extern void hotspotevt_trap_main_fire(ZoneHotspot *pHotspot, unsigned short *pOut_status);
extern void hotspotevt_action_try_enter_zone(ZoneHotspot *evt, int *pOut_handled,
                                             unsigned int *pOut_accepted);
extern void hotspotevt_action_enter_zone(ZoneHotspot *evt);
extern void hotspotevt_combat_play_sfx_voice(ZoneHotspot *evt);
extern void hotspotevt_chance_trigger(ZoneHotspot *evt);
extern void hotspotevt_dlg_run_msg_event(ZoneHotspot *evt, int *out_status);
extern ZoneHotspot *hotspotevt_find_at_player_tile(int mode);
extern ZoneHotspot *hotspotevt_find_at_point(int mode, unsigned char x, unsigned char y);
extern ZoneHotspot *hotspotevt_next_entry_19byte(int param_1);
extern void hotspotevt_done_reset_all(void);
extern void hotspotevt_done_set(void);
extern void hotspotevt_done_clear(void);
extern int hotspotevt_done_read(void);
extern void hotspotevt_scout_tried_clear_all(void);
extern void hotspotevt_scout_tried_set(void);
extern void hotspotevt_scout_tried_clear(void);
extern unsigned short hotspotevt_scout_tried_read(void);
extern void hotspotevt_scouted_clear_all(void);
extern void hotspotevt_scouted_set(void);
extern void hotspotevt_scouted_clear(void);
extern unsigned short hotspotevt_scouted_read(void);
extern void hotspotevt_enc_fought_set(unsigned long key);
extern void hotspotevt_enc_fought_clear(unsigned long key);
extern unsigned short hotspotevt_enc_fought_read(unsigned long key);
extern void hotspotevt_tile_rect_world_ctr(unsigned char *tile_rect, long *out_world_xy);
extern int hotspotevt_monst_dispatch_by_tag(long tag);
extern void hotspotevt_bak_indexed_rec_info(int record_id, char **out_filename,
                                            int *out_record_size);
extern char hotspotevt_bak_load_indexed_rec(int record_id, void *dest, long offset);

#endif
