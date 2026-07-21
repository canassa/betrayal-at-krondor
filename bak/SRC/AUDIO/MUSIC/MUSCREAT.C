#include "globals.h"
#include "structs.h"
#include "SRC/AUDIO/MUSIC/MUSCREAT.H"
#include "SRC/SYS/POOL.H"
#include "SRC/AUDIO/RES/PASCREC.H"

AudioTrackHandle far *music_handle_create(unsigned char far *track_data) {
    AudioTrackHandle far *handle;

    if ((handle = (AudioTrackHandle far *)pool_acquire_buffer(sizeof(AudioTrackHandle), 2)) != 0) {

        handle->pScript = track_data;
        handle->pPosition = advance_pascal_record(track_data);
        handle->pSubBuffer = (unsigned char far *)&handle->pPosition;
        handle->bVolume = 0x7f;
        handle->pNext = 0;

        return handle;
    }

    return 0;
}
