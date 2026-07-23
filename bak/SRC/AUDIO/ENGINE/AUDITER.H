#ifndef BAK_AUDITER_H
#define BAK_AUDITER_H

#include "structs.h"

extern short g_nAudioIterFilter;
extern AudioListNode far *g_pAudioIterCursor;

extern AudioListNode far *audio_iter(int filter);

#endif
