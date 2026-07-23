#include "globals.h"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "structs.h"
#include "SRC/AUDIO/SFX/SFXPLAY.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"
#include "SRC/AUDIO/RES/PASCREC.H"

AudioTrackHandle far *g_apSfxSlotPool[7];

AudioTrackHandle far *sfx_play_in_slot(unsigned char far *script_data, int sfx_id, unsigned char loop) {
    int i;
    AudioTrackHandle far *h = 0;

    if (script_data != 0) {
        for (i = 0; i < 7; i++) {
            h = g_apSfxSlotPool[i];
            if (h->bActive == 0xff) {
                h->pScript = script_data;
                h->pPosition = advance_pascal_record(script_data);
                if (g_pSfxLoopPriorityTable != 0) {
                    h->bLoop = g_pSfxLoopPriorityTable[sfx_id].bLoop;
                    h->bPriority = g_pSfxLoopPriorityTable[sfx_id].bPriority;
                    h->bVolume = 0x7f;
                } else {
                    h->bLoop = loop;
                    h->bPriority = 1;
                    h->bVolume = (unsigned char)sfx_id;
                }
                midi_track_init_thunk(h, 0);
                return h;
            }
        }
    }
    return 0;
}
