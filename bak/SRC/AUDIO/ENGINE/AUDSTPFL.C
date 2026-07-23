#include "structs.h"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/AUDIO/ENGINE/AUDSTPFL.H"
#include "SRC/AUDIO/ENGINE/AUDITER.H"
#include "SRC/AUDIO/CHAN/SFXCHAN.H"
#include "SRC/AUDIO/ENGINE/AUDDRVST.H"

int audio_stop_filter(int filter_mode) {
    AudioListNode far *node;
    short prev_mode;

    prev_mode = g_nAudioFilterMode;
    if (filter_mode > 0)
        return 0;
    if (filter_mode != -1) {
        audio_driver_stop(-2);
    }
    if (g_nAudioFilterMode == -4 || filter_mode == 0) {
        g_nAudioFilterMode = filter_mode;
    } else if (filter_mode != g_nAudioFilterMode) {
        g_nAudioFilterMode = 0;
    }
    if (prev_mode != g_nAudioFilterMode && (node = audio_iter(filter_mode)) != 0) {
        while (node != 0) {
            if (sfxchan_handle_channel(node) != 0) {
                audio_driver_stop(node->wId);
                if ((node->wFlags & 1) || (node->wFlags & 2))
                    node->wFlags |= 0x10;
            }
            node = audio_iter(-3);
        }
    }
    return 1;
}
