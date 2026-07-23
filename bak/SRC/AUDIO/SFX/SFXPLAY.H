#ifndef BAK_SFXPLAY_H
#define BAK_SFXPLAY_H

#include "structs.h"

extern AudioTrackHandle far *g_apSfxSlotPool[7];

extern AudioTrackHandle far *sfx_play_in_slot(unsigned char far *script_data, int sfx_id, unsigned char loop);

#endif
