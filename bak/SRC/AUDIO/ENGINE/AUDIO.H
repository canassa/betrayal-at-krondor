#ifndef BAK_AUDIO_H
#define BAK_AUDIO_H

#include "structs.h"
#include "SRC/IO/IO.H"

extern short g_alloc_to_pool;
extern short g_current_music_track;
extern unsigned short g_nMusicVolume;

extern void audio_ambient_tick(void);
extern int audio_music_play(int track_id);
extern void audio_music_fade_in_current(void);
extern void audio_music_fade_out_and_stop(void);
extern int audio_music_set_volume(int volume);
extern void audio_sfx_stop_combat_bank(void);
extern void audio_sfx_register_combat_bank(void);
extern void audio_preload_ui_sfx(void);
extern void audio_sfx_stop_environment_set(void);
extern void audio_sfx_register_world_bank(void);
extern void audio_sfx_stop_scene_sounds(void);
extern void audio_sfx_register_pair_4_18(void);
extern void audio_sfx_stop_pair_4_18(void);
extern void audio_sfx_register_pair_38_39(void);
extern void audio_sfx_stop_pair_38_39(void);
extern void audio_sfx_register_50(void);
extern void audio_sfx_stop_50(void);
extern void audio_sfx_register_45(void);
extern void audio_sfx_stop_45(void);
extern void audio_play(int sound_id);
extern int audio_sfx_register(BakFile *file, int sfx_id);
extern int audio_sfx_stop(int sfx_id);
extern int audio_sfx_play_n_times(int sfx_id, int extra_repeats, int blocking);

#endif
