#include "globals.h"
#include "SRC/AUDIO/SND/SFXTERM.H"
#include "SRC/STREAM/RESLOAD/RELBUF.H"
#include "SRC/INPUT/TIMER.H"
#include "SRC/STREAM/RESLOAD/IFFREAD.H"
#include "SRC/AUDIO/SND/SNDBUFFR.H"
#include "SRC/AUDIO/ENGINE/AUDSTOP.H"
#include "SRC/AUDIO/SND/SNDSTOP.H"

void sfx_subsystem_teardown(void) {
    if (g_pSfxDriver != 0 || g_pMusicDriver != 0) {
        audio_stop(0);
        if (g_pMusicChunkBuf != 0) {
            release_buffer(g_pMusicChunkBuf, 10);
        }
        if (g_music_archive != 0 && g_music_archive_owned != 0) {
            cached_file_close(g_music_archive);
        }
        if (g_nSfxSampleSlot != 0) {
            registry_slot_free(g_nSfxSampleSlot);
            g_nSfxSampleSlot = 0;
        }
        if (g_nSfxWorkSlot != 0) {
            registry_slot_free(g_nSfxWorkSlot);
            g_nSfxWorkSlot = 0;
        }
        if (g_bAudioTimerInstalled != 0) {
            timer_restore_default();
            g_bAudioTimerInstalled = 0;
        }
        audio_buffers_release_all();
        audioteardown_rel_strm_bufs();
    }
}
