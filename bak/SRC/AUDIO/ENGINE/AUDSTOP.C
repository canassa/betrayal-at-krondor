#include "globals.h"
#include "SRC/AUDIO/ENGINE/AUDSTOP.H"
#include "SRC/STREAM/RESLOAD/RELBUF.H"
#include "SRC/AUDIO/SFX/SFXSTPAL.H"
#include "SRC/AUDIO/ENGINE/AUDDRVST.H"

int audio_stop(int what) {
    AudioListNode far *prev;
    AudioListNode far *cur;
    AudioListNode sentinel;
    int result;

    result = 0;

    prev = &sentinel;

    cur = g_pActiveAudioListHead;

    if ((what == 0) || (what == -2)) {
        sfx_stop_all();
    }

    while (cur != 0) {

        if ((what == 0) || (cur->wId == what) || (what == -1 && (cur->wFlags & 1) != 0) ||
            (what == -2 && (cur->wFlags & 1) == 0)) {

            result = 1;
            audio_driver_stop(cur->wId);

            if (cur == g_pActiveAudioListHead) {
                g_pActiveAudioListHead = cur->pNext;
            }

            prev->pNext = cur->pNext;

            if ((cur->wFlags & 1) != 0) {
                release_buffer(cur->pData, 4);
            } else {
                release_buffer(cur->pData, 7);
            }

            release_buffer(cur, 3);

            if (result != 0 && what > 0) {
                return result;
            }
        } else {
            prev = cur;
        }

        cur = prev->pNext;
    }

    return result;
}
