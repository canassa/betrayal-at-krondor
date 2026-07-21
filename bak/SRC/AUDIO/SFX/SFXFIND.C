#include "globals.h"
#include "SRC/AUDIO/SFX/SFXFIND.H"

AudioTrackHandle far *sfx_find_active(uchar far *track_data) {
    int i;

    for (i = 0; i < 7; i++) {
        if (g_apSfxSlotPool[i]->pScript == track_data && g_apSfxSlotPool[i]->bActive != 0xff)
            return g_apSfxSlotPool[i];
    }
    return 0;
}
