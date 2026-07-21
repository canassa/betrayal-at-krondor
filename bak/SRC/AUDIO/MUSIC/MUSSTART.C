#include "structs.h"
#include "SRC/AUDIO/MUSIC/MUSSTART.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"
#include "SRC/AUDIO/MUSIC/SNDLADV.H"

AudioTrackHandle far *music_handle_start(AudioTrackHandle far *handle, int advance_n, int volume) {
    if ((handle = sound_list_advance_n(handle, advance_n)) != 0) {
        handle->bVolume = volume;
        midi_track_init_thunk(handle, 1);
        return handle;
    }
    return 0;
}
