#include "globals.h"
#include "structs.h"
#include "SRC/AUDIO/CHAN/AUDCHBYT.H"
#include "SRC/AUDIO/CHAN/SFXCHAN.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

int far audio_channel_set_byte_15a(int channel, int value) {
    AudioTrackHandle far *track;

    if ((track = sfxchan_apply_to_channels(channel)) != 0) {
        midi_track_set_byte_15a(track->pHeader, value);
        return 1;
    }
    return 0;
}
