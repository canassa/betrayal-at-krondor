#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "structs.h"
#include "SRC/AUDIO/CHAN/AUDSETIN.H"
#include "SRC/AUDIO/CHAN/SFXCHAN.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"

int audio_set_intensity(int id, int intensity) {
    AudioTrackHandle far *track;

    intensity = intensity > 0x3f ? 0x3f : intensity;
    intensity = intensity < 0 ? 0 : intensity;

    if ((track = sfxchan_apply_to_channels(id)) != 0) {
        while (track != 0) {
            midi_track_apply_intensity(track->pHeader, g_abIntensityCurve[intensity]);
            track = sfxchan_apply_to_channels(-3);
        }
        return 1;
    }
    return 0;
}
