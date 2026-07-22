#include "globals.h"
#include "structs.h"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/SYS/RAND.H"
#include "SRC/AUDIO/RES/POOL.H"
#include "SRC/AUDIO/ENGINE/AUDITER.H"
#include "SRC/AUDIO/RES/AUDRESLD.H"
#include "SRC/AUDIO/ENGINE/AUDSTOP.H"
#include "SRC/AUDIO/CHAN/AUDSETIN.H"
#include "SRC/AUDIO/MUSIC/MUSFADE.H"
#include "SRC/AUDIO/ENGINE/AUDSTART.H"
#include "SRC/AUDIO/ENGINE/AUDDRVST.H"
#include "SRC/AUDIO/CHAN/AUDCHFID.H"
#include "SRC/GAME/GSTATE.H"

/* Music-engine state.  g_alloc_to_pool routes alloc_far into the resource
 * pool while a music chunk loads (POOL.C flips it too, during pool sizing). */
short g_alloc_to_pool = 0;
short g_current_music_track = -1;
unsigned short g_nMusicVolume = 0x7f;

void far audio_ambient_tick(void) {
    int sfx_id;

    if (g_game_mode != 2) {
        if (g_gameState.nChapter == 8)
            return;
        if (g_gameState.nZoneId == 6)
            return;
        if (RND(0x6e) != 0)
            return;

        if (gstate_event_read(0x753a)) {
            if (g_gameState.nZoneId != 2) {
                sfx_id = RNDR(52, 54);
            } else {
                if (RND(100) <= 50)
                    sfx_id = 0x85;
                else
                    sfx_id = RND2(2) + 0x35;
            }
        } else {
            if (RND(100) <= 5)
                sfx_id = 0x5a;
            else
                sfx_id = 0x33;
        }

        audio_play(sfx_id);
        audio_set_intensity(sfx_id, RNDR(10, 63));
        return;
    }

    if (RND(0xb4) != 0)
        return;
    audio_play(3);
    audio_set_intensity(3, RNDR(10, 59));
}

int audio_music_play(int track_id) {
    short prev;
    int music_enabled;

    if ((g_sound_driver == 8) || (track_id == g_current_music_track) || (track_id == -999)) {
        return g_current_music_track;
    }

    if (g_engine_prefs && (g_engine_prefs->flags & 2)) {
        music_enabled = 1;
    } else {
        music_enabled = 0;
    }
    g_alloc_to_pool = 1;
    if (g_current_music_track != -1) {
        if (music_enabled) {
            music_fade(g_current_music_track, 0, 0x32);

            g_nFrameTickCountdown = 0x15e;
            while (g_nFrameTickCountdown != 0) {
            }
            audio_driver_stop(g_current_music_track);
        }
        audio_stop(g_current_music_track);
    }
    prev = g_current_music_track;
    if (track_id != -1) {
        pool_reset();
        audio_resource_load_chunk(g_pSfxArchiveStream, track_id);
        if (music_enabled) {
            audio_start_by_id(track_id);
        }
        g_nMusicVolume = 0x7f;
    }
    g_alloc_to_pool = 0;
    g_current_music_track = track_id;
    return prev;
}

void audio_music_fade_in_current(void) {
    if (g_current_music_track != -1) {
        audio_start_by_id(g_current_music_track);
        audio_set_intensity(g_current_music_track, 0);
        music_fade(g_current_music_track, g_nMusicVolume, 0x32);
    }
}

void audio_music_fade_out_and_stop(void) {
    if (g_current_music_track == -1) {
        return;
    }
    music_fade(g_current_music_track, 0, 0x32);
    g_nFrameTickCountdown = 0x15e;
    while (g_nFrameTickCountdown != 0) {
    }
    audio_driver_stop(g_current_music_track);
}

int far audio_music_set_volume(int volume) {
    if (volume >= 0 && volume <= 0x7f) {
        if (g_engine_prefs != (EnginePrefs *)0 && (g_engine_prefs->flags & 2) != 0 &&
            g_current_music_track != -1) {
            audio_set_intensity(g_current_music_track, volume);
        }
        g_nMusicVolume = volume;
    }
    return g_nMusicVolume;
}

void audio_sfx_stop_combat_bank(void) {
    if (g_sound_driver != 8) {
        audio_sfx_stop(0x41);
        audio_sfx_stop(10);
        audio_sfx_stop(0x4f);
        audio_sfx_stop(6);
        audio_sfx_stop(4);
        audio_sfx_stop(0x4e);
        audio_sfx_stop(0x50);
        audio_sfx_stop(0x3f);
        audio_sfx_stop(0x15);
        audio_sfx_stop(0x11);
        audio_sfx_stop(0x51);
        audio_sfx_stop(0x4d);
        audio_sfx_stop(0x3a);
        audio_sfx_stop(0x4b);
        audio_sfx_stop(0x4c);
        audio_sfx_stop(1);
        audio_sfx_stop(0x1a);
        audio_sfx_stop(0x4a);
        audio_sfx_stop(0x49);
        audio_sfx_stop(0x48);
        audio_sfx_stop(0x47);
        audio_sfx_stop(0x45);
        audio_sfx_stop(0x1d);
        audio_sfx_stop(0x44);
        audio_sfx_stop(0x43);
        audio_sfx_stop(7);
        audio_sfx_stop(0x13);
        audio_sfx_stop(0x42);
    }
    return;
}

void audio_sfx_register_combat_bank(void) {
    if (g_sound_driver != 8) {
        audio_sfx_register(g_pSfxArchiveStream, 0x42);
        audio_sfx_register(g_pSfxArchiveStream, 0x13);
        audio_sfx_register(g_pSfxArchiveStream, 7);
        audio_sfx_register(g_pSfxArchiveStream, 0x43);
        audio_sfx_register(g_pSfxArchiveStream, 0x44);
        audio_sfx_register(g_pSfxArchiveStream, 0x1d);
        audio_sfx_register(g_pSfxArchiveStream, 0x45);
        audio_sfx_register(g_pSfxArchiveStream, 0x47);
        audio_sfx_register(g_pSfxArchiveStream, 0x48);
        audio_sfx_register(g_pSfxArchiveStream, 0x49);
        audio_sfx_register(g_pSfxArchiveStream, 0x4a);
        audio_sfx_register(g_pSfxArchiveStream, 0x1a);
        audio_sfx_register(g_pSfxArchiveStream, 1);
        audio_sfx_register(g_pSfxArchiveStream, 0x4c);
        audio_sfx_register(g_pSfxArchiveStream, 0x4b);
        audio_sfx_register(g_pSfxArchiveStream, 0x3a);
        audio_sfx_register(g_pSfxArchiveStream, 0x4d);
        audio_sfx_register(g_pSfxArchiveStream, 0x51);
        audio_sfx_register(g_pSfxArchiveStream, 0x11);
        audio_sfx_register(g_pSfxArchiveStream, 0x15);
        audio_sfx_register(g_pSfxArchiveStream, 0x3f);
        audio_sfx_register(g_pSfxArchiveStream, 0x50);
        audio_sfx_register(g_pSfxArchiveStream, 0x4e);
        audio_sfx_register(g_pSfxArchiveStream, 4);
        audio_sfx_register(g_pSfxArchiveStream, 6);
        audio_sfx_register(g_pSfxArchiveStream, 0x4f);
        audio_sfx_register(g_pSfxArchiveStream, 0xa);
        audio_sfx_register(g_pSfxArchiveStream, 0x41);
    }
}

void audio_preload_ui_sfx(void) {
    if (g_sound_driver != 8) {
        audio_sfx_register(g_pSfxArchiveStream, 0x53);
        audio_sfx_register(g_pSfxArchiveStream, 0x30);
        audio_sfx_register(g_pSfxArchiveStream, 0x3d);
        audio_sfx_register(g_pSfxArchiveStream, 0x3c);
    }
}

void audio_sfx_stop_environment_set(void) {
    if (g_sound_driver != 8) {
        audio_sfx_stop(0x3c);
        audio_sfx_stop(0x3d);
        audio_sfx_stop(0x30);
        audio_sfx_stop(0x53);
    }
    return;
}

void audio_sfx_register_world_bank(void) {
    if (g_sound_driver != 8) {
        audio_sfx_register(g_pSfxArchiveStream, 0x31);
        audio_sfx_register(g_pSfxArchiveStream, 5);
        audio_sfx_register(g_pSfxArchiveStream, 0x2b);
        audio_sfx_register(g_pSfxArchiveStream, 0x1e);
        audio_sfx_register(g_pSfxArchiveStream, 0x29);
        audio_sfx_register(g_pSfxArchiveStream, 0x3a);
        audio_sfx_register(g_pSfxArchiveStream, 0x3b);
        audio_sfx_register(g_pSfxArchiveStream, 0x51);
        audio_sfx_register(g_pSfxArchiveStream, 0xc);
        audio_sfx_register(g_pSfxArchiveStream, 0xd);
        if (g_game_mode == 2) {
            audio_sfx_register(g_pSfxArchiveStream, 3);
            return;
        }
        audio_sfx_register(g_pSfxArchiveStream, 0x33);
        audio_sfx_register(g_pSfxArchiveStream, 0x34);
        audio_sfx_register(g_pSfxArchiveStream, 0x35);
        audio_sfx_register(g_pSfxArchiveStream, 0x36);
        audio_sfx_register(g_pSfxArchiveStream, 0x5a);
        if (g_gameState.nZoneId != 2) {
            return;
        }
        audio_sfx_register(g_pSfxArchiveStream, 0x85);
    }
}

void audio_sfx_stop_scene_sounds(void) {
    if (g_sound_driver != 8) {
        if (g_game_mode == 2) {
            audio_sfx_stop(3);
        } else {
            if (g_gameState.nZoneId == 2) {
                audio_sfx_stop(0x85);
            }
            audio_sfx_stop(0x5a);
            audio_sfx_stop(0x36);
            audio_sfx_stop(0x35);
            audio_sfx_stop(0x34);
            audio_sfx_stop(0x33);
        }
        audio_sfx_stop(0xd);
        audio_sfx_stop(0xc);
        audio_sfx_stop(0x51);
        audio_sfx_stop(0x3b);
        audio_sfx_stop(0x3a);
        audio_sfx_stop(0x29);
        audio_sfx_stop(0x1e);
        audio_sfx_stop(0x2b);
        audio_sfx_stop(5);
        audio_sfx_stop(0x31);
    }
    return;
}

void audio_sfx_register_pair_4_18(void) {
    if (g_sound_driver != 8) {
        audio_sfx_register(g_pSfxArchiveStream, 4);
        audio_sfx_register(g_pSfxArchiveStream, 0x12);
    }
    return;
}

void audio_sfx_stop_pair_4_18(void) {
    if (g_sound_driver != 8) {
        audio_sfx_stop(0x12);
        audio_sfx_stop(4);
    }
    return;
}

void audio_sfx_register_pair_38_39(void) {
    if (g_sound_driver != 8) {
        audio_sfx_register(g_pSfxArchiveStream, 0x26);
        audio_sfx_register(g_pSfxArchiveStream, 0x27);
    }
    return;
}

void audio_sfx_stop_pair_38_39(void) {
    if (g_sound_driver != 8) {
        audio_sfx_stop(0x27);
        audio_sfx_stop(0x26);
    }
    return;
}

void audio_sfx_register_50(void) {
    if (g_sound_driver != 8) {
        audio_sfx_register(g_pSfxArchiveStream, 0x32);
    }
    return;
}

void audio_sfx_stop_50(void) {
    if (g_sound_driver != 8) {
        audio_sfx_stop(0x32);
    }
    return;
}

void audio_sfx_register_45(void) {
    if (g_sound_driver != 8) {
        audio_sfx_register(g_pSfxArchiveStream, 0x2d);
    }
    return;
}

void audio_sfx_stop_45(void) {
    if (g_sound_driver != 8) {
        audio_sfx_stop(0x2d);
    }
    return;
}

void audio_play(int sound_id) {
    if (g_sound_driver == 8) {
        return;
    }

    if (sound_id >= 0x3e9) {
        audio_music_play(sound_id);
        return;
    }
    if (g_engine_prefs != (EnginePrefs *)0 && (g_engine_prefs->flags & 1) == 0) {
        return;
    }
    audio_start_by_id(sound_id);
}

int audio_sfx_register(BakFile *file, int sfx_id) {
    return ((g_sound_driver != 8) && (sfx_id < 1001)) ? (int)audio_resource_load_chunk(file, sfx_id)
                                                      : 0;
}

int audio_sfx_stop(int sfx_id) {
    if (g_sound_driver != 8 && sfx_id < 1001)
        return audio_stop(sfx_id);
    return 0;
}

int far audio_sfx_play_n_times(int sfx_id, int extra_repeats, int blocking) {
    BakFile *pChunk;

    if (g_sound_driver == 8) {
        return 0;
    }

    if (audio_iter(sfx_id) != 0) {

        audio_play(sfx_id);
        if (blocking != 0) {
            g_nFrameTickCountdown = 5;
            while (g_nFrameTickCountdown != 0) {
            }
            while (audio_channel_for_id(sfx_id) != -1) {
            }
        }
        return 0;
    }

    pChunk = audio_resource_load_chunk(g_pSfxArchiveStream, sfx_id);
    if (pChunk != 0) {
        while (extra_repeats-- >= 0) {
            audio_play(sfx_id);
            if (blocking != 0) {
                g_nFrameTickCountdown = 5;
                while (g_nFrameTickCountdown != 0) {
                }
                while (audio_channel_for_id(sfx_id) != -1) {
                }
            }
        }

        if (blocking != 0) {
            audio_driver_stop(sfx_id);
            audio_stop(sfx_id);
            return 0;
        }
        return 1;
    }

    return 0;
}
