#include "SRC/AUDIO/CHAN/AUDCMD07.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

int audio_driver_cmd07_dispatch(int velocity) {
    midi_set_note_velocity_thunk(velocity);
    return 1;
}
