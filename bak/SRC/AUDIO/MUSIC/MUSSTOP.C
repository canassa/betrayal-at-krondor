#include "structs.h"
#include "SRC/AUDIO/MUSIC/MUSSTOP.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"
#include "SRC/AUDIO/MUSIC/SNDLADV.H"

void music_handle_stop(AudioTrackHandle far *pRecord, int n) {

    if ((pRecord = sound_list_advance_n(pRecord, n)) != 0) {
        midi_active_release_thunk(pRecord);
    }
}
