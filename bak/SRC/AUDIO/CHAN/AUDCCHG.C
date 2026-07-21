#include "globals.h"
#include "SRC/AUDIO/CHAN/AUDCCHG.H"
#include "SRC/AUDIO/CHAN/SFXCHAN.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

int audio_chan_apply_ctrl_change(int channel, int ctrlNum, int value, int midiChannel) {
    AudioTrackHandle far *state;

    if ((state = sfxchan_apply_to_channels(channel)) != 0) {
        midi_apply_ctrl_change_thunk(state, ctrlNum, value, midiChannel);
        return 1;
    }
    return 0;
}
