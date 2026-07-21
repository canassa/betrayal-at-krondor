#include "structs.h"
#include "SRC/AUDIO/CHAN/AUDCHWRD.H"
#include "SRC/AUDIO/CHAN/SFXCHAN.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

int audio_channel_set_word_bc(int channel, int word_val, int voice_slot) {
    AudioTrackHandle far *handle_fp;

    if ((handle_fp = sfxchan_apply_to_channels(channel)) != 0) {
        midi_track_set_word_bc_far(handle_fp->pHeader, word_val, voice_slot);
        return 1;
    }
    return 0;
}
