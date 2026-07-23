#include "globals.h"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/AUDIO/ENGINE/AUDSTART.H"
#include "SRC/AUDIO/MUSIC/MUSCREAT.H"
#include "SRC/AUDIO/SFX/SFXFIND.H"
#include "SRC/AUDIO/ENGINE/AUDDRVST.H"
#include "SRC/AUDIO/MUSIC/MUSSTART.H"
#include "SRC/AUDIO/SFX/SFXPLAY.H"

int audio_start_by_id(int id) {
    AudioListNode far *node;
    AudioListNode far *other;
    int loop_flag;

    node = g_pActiveAudioListHead;
    while (node != 0 && node->wId != id)
        node = node->pNext;

    if (node == 0) {
        return 0;
    }

    if ((node->wFlags & 0x10) != 0 || node->pData == 0 || node->pHandle != 0) {
        return 1;
    }

    if ((node->wFlags & 1) != 0) {

        for (other = g_pActiveAudioListHead; other != 0; other = other->pNext) {
            if ((other->wFlags & 1) != 0 && other->pHandle != 0 && other->wId != id) {
                audio_driver_stop(other->wId);
            }
        }

        if (g_nAudioFilterMode == 0 || g_nAudioFilterMode == -1) {

            node->wFlags |= 0x10;
            return 1;
        }

        if ((node->pHandle = music_handle_create(node->pData)) != 0) {

            node->pHandle->bLoop = (node->wFlags & 2) != 0;
            node->pHandle->bPriority = node->bPriority;

            if (music_handle_start(node->pHandle, 0, 0x7f) != 0) {
                return 1;
            }
        }
    } else {
        if (sfx_find_active(node->pData) == 0) {
            if (g_nAudioFilterMode == 0 || g_nAudioFilterMode == -2) {

                if ((node->wFlags & 2) != 0) {
                    node->wFlags |= 0x10;
                    return 1;
                }
                return 1;
            }

            loop_flag = (node->wFlags & 2) != 0;
            sfx_play_in_slot(node->pData, 0x7f, loop_flag);
            return 1;
        }
        return 1;
    }
    return 0;
}
