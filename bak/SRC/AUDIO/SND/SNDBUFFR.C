#include "structs.h"
#include "SRC/AUDIO/SFX/SFXPLAY.H"
#include "SRC/AUDIO/SND/SNDBUFFR.H"
#include "SRC/STREAM/RESLOAD/RELBUF.H"

int audio_buffers_release_all(void) {
    int i;

    if (g_apSfxSlotPool[0] != 0) {
        for (i = 0; i < 7; i++) {
            if (g_apSfxSlotPool[i] != 0) {
                release_buffer(g_apSfxSlotPool[i], 2);
            }
        }
        return 1;
    }
    return 0;
}
