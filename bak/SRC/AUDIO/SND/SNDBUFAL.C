#include "structs.h"
#include "SRC/AUDIO/SFX/SFXPLAY.H"
#include "SRC/AUDIO/SND/SNDBUFAL.H"
#include "SRC/AUDIO/RES/POOL.H"
#include "SRC/AUDIO/SND/SNDBUFFR.H"

int audio_buffers_alloc_all(void) {
    AudioTrackHandle far *buf;
    int i;

    if (g_apSfxSlotPool[0] == 0) {
        for (i = 0; i < 7; i++) {
            if ((g_apSfxSlotPool[i] = (AudioTrackHandle far *)pool_acquire_buffer(
                     sizeof(AudioTrackHandle), 2)) == 0) {
                audio_buffers_release_all();
                return 0;
            }
            buf = g_apSfxSlotPool[i];
            buf->bActive = 0xff;
            buf->pSubBuffer = (unsigned char far *)&buf->pPosition;
        }
        return 1;
    }
    return 0;
}
