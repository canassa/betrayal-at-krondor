#include "structs.h"
#include "SRC/AUDIO/CHAN/SFXCHAN.H"
#include "SRC/AUDIO/ENGINE/AUDITER.H"
#include "SRC/AUDIO/SFX/SFXFIND.H"

AudioTrackHandle far *sfxchan_apply_to_channels(int channel_or_mode) {
    AudioListNode far *handle;
    AudioTrackHandle far *result;

    handle = audio_iter(channel_or_mode);

    if (channel_or_mode > 0) {
        return sfxchan_handle_channel(handle);
    }

    while (handle != 0) {
        if ((result = sfxchan_handle_channel(handle)) != 0) {
            return result;
        }
        handle = audio_iter(-3);
    }
    return 0;
}

AudioTrackHandle far *sfxchan_handle_channel(AudioListNode far *node) {
    if ((node->wFlags & 1) != 0) {
        return node->pHandle;
    }
    return sfx_find_active(node->pData);
}
