#include "structs.h"
#include "SRC/AUDIO/SND/SNDINIT.H"
#include "SRC/AUDIO/DRIVER/MUSDISP.H"
#include "SRC/INPUT/TIMER.H"
#include "SRC/AUDIO/SND/SNDBUFAL.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"
#include "SRC/AUDIO/SND/SNDINST.H"
#include "SRC/AUDIO/RES/AUDRESIN.H"

int audio_driver_init(int driver_id, int music_driver, unsigned int p3, char *fileName) {
    int install;

    install = 1;

    if (g_pSfxDriver != 0 || g_pMusicDriver != 0)
        return 1;

    if (driver_id == -1) {
        driver_id = SNDDRV_ADL;
        install = 0;
    }

    if (sndinst_drivers(driver_id, music_driver, p3, fileName) != 0) {
        if (install && !g_timer_installed) {
            timer_install(0xd);
            g_bAudioTimerInstalled = 1;
        }
        if (install) {
            if ((g_nSfxSampleSlot = registry_slot_alloc(midi_task_scheduler_tick, 4)) != 0)
                goto LAB_0087;
        }
        if (!install) {
        LAB_0087:
            if (install && g_pMusicDriver != 0) {
                g_nSfxWorkSlot = registry_slot_alloc(audio_music_tick, 2);
            }
            audio_buffers_alloc_all();
            return 1;
        }
    }
    return 0;
}
