#include "structs.h"
#include "globals.h"
#include "SRC/AUDIO/SFX/SFXSTPAL.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

void sfx_stop_all(void) {
    int i;

    for (i = 0; i < 7; i++) {
        if (g_apSfxSlotPool[i]->bActive != 0xff) {
            midi_active_release_thunk(g_apSfxSlotPool[i]);
            g_apSfxSlotPool[i]->bActive = 0xff;
        }
    }
}
