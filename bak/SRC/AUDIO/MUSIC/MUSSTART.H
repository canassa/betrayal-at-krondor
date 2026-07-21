#ifndef BAK_MUSSTART_H
#define BAK_MUSSTART_H

#include "structs.h"

extern AudioTrackHandle far *music_handle_start(AudioTrackHandle far *handle, int advance_n,
                                                int volume);

#endif
