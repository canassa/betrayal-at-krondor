#include "structs.h"
#include "SRC/AUDIO/ENGINE/AUDDRVST.H"
#include "SRC/STREAM/RESLOAD/RELBUF.H"
#include "SRC/AUDIO/ENGINE/AUDITER.H"
#include "SRC/AUDIO/SFX/SFXSTPAL.H"
#include "SRC/AUDIO/MUSIC/MUSSTOP.H"
#include "SRC/AUDIO/SFX/SFXSTOP.H"

int audio_driver_stop(int id) {
    AudioListNode far *p;

    switch (id) {
    case -1:
    case 0:

        p = audio_iter(-1);
        while (p != 0) {
            p->wFlags &= 0xffef;
            if (p->pHandle != 0) {
                music_handle_stop(p->pHandle, 0);
                while (p->pHandle->bActive != 0xff)
                    ;
                release_buffer(p->pHandle, 2);
                p->pHandle = 0;
                p = 0;
            } else {
                p = audio_iter(-3);
            }
        }
        if (id == -1)
            return 1;

    case -2:

        p = audio_iter(-2);
        while (p != 0) {
            p->wFlags &= 0xffef;
            p = audio_iter(-3);
        }
        sfx_stop_all();
        return 1;
    default:

        if ((p = audio_iter(id)) != 0) {
            p->wFlags &= 0xffef;
            if (p->wFlags & 1) {
                if (p->pHandle != 0) {
                    music_handle_stop(p->pHandle, 0);
                    while (p->pHandle->bActive != 0xff)
                        ;
                    release_buffer(p->pHandle, 2);
                    p->pHandle = 0;
                }
            } else {
                sfx_stop_in_slot(p->pData);
            }
            return 1;
        }
        return 0;
    }
}
