#include "structs.h"
#include "SRC/AUDIO/MUSIC/MUSFADE.H"
#include "SRC/AUDIO/CHAN/SFXCHAN.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

int music_fade(int track_id, int target_volume, int steps) {
    AudioTrackHandle far *handle_fp;
    int step_size;
    int count;

    if ((handle_fp = sfxchan_apply_to_channels(track_id)) != 0) {
        if ((step_size = (target_volume - (signed char)handle_fp->bVolume) / steps) != 0) {
            if (step_size < 0) {
                step_size = -step_size;
            }
        } else {
            step_size = 1;
        }
        count = 1;

        while (handle_fp) {
            midi_fade_queue_handle(handle_fp, target_volume, count, step_size);
            handle_fp = sfxchan_apply_to_channels(-3);
        }
        return 1;
    }
    return 0;
}
