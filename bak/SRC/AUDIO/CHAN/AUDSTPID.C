#include "structs.h"
#include "SRC/AUDIO/CHAN/AUDSTPID.H"
#include "SRC/AUDIO/CHAN/SFXCHAN.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

int audio_stop_sfx_all_with_id(int sfx_id) {
    AudioTrackHandle far *ptr;

    if ((ptr = sfxchan_apply_to_channels(sfx_id)) != 0) {
        while (ptr != 0) {
            midi_event_callback_thunk_0a8b((void far *)ptr, 0);
            ptr = sfxchan_apply_to_channels(-3);
        }
        return 1;
    }
    return 0;
}
