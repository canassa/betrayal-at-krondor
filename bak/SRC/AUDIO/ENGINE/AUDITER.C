#include "structs.h"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/AUDIO/ENGINE/AUDITER.H"

short g_nAudioIterFilter;
AudioListNode far *g_pAudioIterCursor;

AudioListNode far *audio_iter(int filter) {
    unsigned int match;
    unsigned int mask;

    match = 0;
    mask = 1;
    if (filter != -3) {
        g_nAudioIterFilter = filter;
        g_pAudioIterCursor = g_pActiveAudioListHead;
    } else {
        if (g_pAudioIterCursor != 0)
            g_pAudioIterCursor = g_pAudioIterCursor->pNext;
    }

    switch (g_nAudioIterFilter) {
    case 0:
        mask = 0;

    case -2:
        match = 1;

    case -1:
        while (g_pAudioIterCursor != 0) {
            if ((g_pAudioIterCursor->wFlags & mask) ^ match)
                return g_pAudioIterCursor;
            g_pAudioIterCursor = g_pAudioIterCursor->pNext;
        }
        break;
    default:
        if (g_pAudioIterCursor != 0 && filter != -3) {
            while (g_pAudioIterCursor != 0 && g_pAudioIterCursor->wId != filter)
                g_pAudioIterCursor = g_pAudioIterCursor->pNext;
        } else {
            g_pAudioIterCursor = 0;
        }
        break;
    }
    return g_pAudioIterCursor;
}
