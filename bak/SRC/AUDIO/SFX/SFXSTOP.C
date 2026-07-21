#include "globals.h"
#include "structs.h"
#include "SRC/AUDIO/SFX/SFXSTOP.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

void sfx_stop_in_slot(uchar far *script) {
    int i;
    AudioTrackHandle far *h;

    for (i = 0; i < 7; i++) {
        h = g_apSfxSlotPool[i];
        if (h->pScript == script) {
            midi_active_release_thunk(h);
            h->bActive = 0xff;
            return;
        }
    }
}
