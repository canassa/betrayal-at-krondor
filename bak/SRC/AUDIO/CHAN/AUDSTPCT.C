#include "globals.h"
#include "SRC/AUDIO/CHAN/AUDSTPCT.H"
#include "SRC/AUDIO/CHAN/SFXCHAN.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

int audio_stop_category(int category) {
    AudioTrackHandle far *ptr;

    if ((ptr = sfxchan_apply_to_channels(category)) != 0) {
        while (ptr != 0) {
            midi_event_callback_thunk_0a8b((void far *)ptr, 1);
            ptr = sfxchan_apply_to_channels(-3);
        }
        return 1;
    }
    return 0;
}
