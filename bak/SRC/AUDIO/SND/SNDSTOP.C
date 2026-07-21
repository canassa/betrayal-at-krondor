#include "globals.h"
#include "SRC/AUDIO/SND/SNDSTOP.H"
#include "SRC/AUDIO/DRIVER/MUSDISP.H"
#include "SRC/STREAM/RESLOAD/RELBUF.H"
#include "SRC/INPUT/TIMER.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

short g_nSpinWaitTicks;

void audioteardown_rel_strm_bufs(void) {
    if (g_pSfxDriver != 0) {
        midi_init_thunk_0678();
        if (g_nSfxSampleSlot == 0) {
            midi_task_scheduler_tick();
            midi_task_scheduler_tick();
        } else {
            audioteardown_spin_wait_drain();
        }
    }
    if (g_pMusicDriver != 0) {
        audio_driver_disp_seg1000_far();
    }
    if (g_pSfxDriver != 0) {
        release_buffer(g_pSfxDriver, 1);
        g_pSfxDriver = 0;
    }
    if (g_pMusicDriver != 0) {
        release_buffer(g_pMusicDriver, 1);
        g_pMusicDriver = 0;
    }
    return;
}

void audioteardown_spin_wait_drain(void) {
    int slot;

    g_nSpinWaitTicks = 5;
    slot = registry_slot_alloc(audioteardown_drain_sem_dec, 4);
    do {
    } while (g_nSpinWaitTicks > 0);
    registry_slot_free(slot);
    return;
}

void audioteardown_drain_sem_dec(void) {
    --g_nSpinWaitTicks;
}
