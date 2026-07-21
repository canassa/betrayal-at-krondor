#include "structs.h"
#include "SRC/AUDIO/MUSIC/SNDLADV.H"

AudioTrackHandle far *sound_list_advance_n(AudioTrackHandle far *node, int n) {
    while (node != 0 && n != 0) {
        node = node->pNext;
        n--;
    }
    return node;
}
