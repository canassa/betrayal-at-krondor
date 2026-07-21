#include "structs.h"
#include "SRC/AUDIO/CHAN/AUDCHORD.H"
#include "SRC/AUDIO/CHAN/SFXCHAN.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

int audio_channel_apply_chord_event(int channel, int event) {
    AudioTrackHandle far *handle;

    if ((handle = sfxchan_apply_to_channels(channel)) != 0) {
        midi_chord_event_thunk_0b6e(handle->pHeader, event);
        return 1;
    }
    return 0;
}
