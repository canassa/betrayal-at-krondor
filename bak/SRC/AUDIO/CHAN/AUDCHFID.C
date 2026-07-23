#include "structs.h"
#include "SRC/AUDIO/CHAN/AUDCHFID.H"
#include "SRC/AUDIO/CHAN/SFXCHAN.H"

int audio_channel_for_id(int id) {
    AudioTrackHandle far *h;

    if ((h = sfxchan_apply_to_channels(id)) != 0)
        return (signed char)h->bActive;
    return -1;
}
