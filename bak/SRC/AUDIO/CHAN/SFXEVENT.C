#include "SRC/AUDIO/CHAN/SFXEVENT.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

int sfx_event_call_32c8_0063(int voice_count) {
    midi_cmd6_far_wrapper(voice_count);
    return 1;
}
