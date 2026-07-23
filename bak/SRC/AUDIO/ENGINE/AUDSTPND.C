#include "structs.h"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/AUDIO/ENGINE/AUDSTPND.H"
#include "SRC/AUDIO/ENGINE/AUDITER.H"
#include "SRC/AUDIO/ENGINE/AUDSTART.H"

int audio_start_pending(int filter) {
    AudioListNode far *node;

    if (filter > 0) {
        return 0;
    }

    if (filter == 0 || filter == g_nAudioFilterMode) {
        g_nAudioFilterMode = -4;
    } else if (g_nAudioFilterMode == 0) {
        if (filter == -1) {
            g_nAudioFilterMode = -2;
        } else {
            g_nAudioFilterMode = -1;
        }
    }

    node = audio_iter(filter);
    while (node != 0) {
        if ((node->wFlags & 0x10) != 0) {
            node->wFlags &= ~0x10;
            audio_start_by_id(node->wId);
        }
        node = audio_iter(-3);
    }
    return 1;
}
