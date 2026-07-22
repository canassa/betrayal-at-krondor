#include "globals.h"
#include "SRC/AUDIO/SND/SNDINST.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/AUDIO/DRIVER/MUSDISP.H"
#include "SRC/STREAM/RESLOAD/RELBUF.H"
#include "SRC/STREAM/BUFLOAD/LOADCHNK.H"
#include "SRC/AUDIO/DRIVER/MIDI.H"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/AUDIO/DRIVER/SNDDRV.H"

int sndinst_drivers(int sfx_driver, int music_driver, unsigned int p3, char *fileName) {
    int failed;

    failed = 0;

    if (music_driver != -2) {
        my_strcpy(g_szSsmTag + 4, g_apMusicDriverTags[music_driver]);
        if ((g_pMusicDriver = bak_load_chunk(fileName, g_szSsmTag, 0)) != (void far *)0) {
            g_bMusicDriverInstalled = 1;
            snddrv_patch_farptr((unsigned)g_pMusicDriver, ((unsigned *)&g_pMusicDriver)[1]);
            if (audio_driver_disp_seg1000_alt(p3, 1) == 0) {
                g_bMusicDriverInstalled = 0;
                audio_driver_disp_seg1000_far();
                release_buffer(g_pMusicDriver, 1);
                g_pMusicDriver = (void far *)0;
                failed = 1;
            }
        } else {
            failed = 1;
        }
    }

    if (sfx_driver != -2) {
        my_strcpy(g_szSsmTag + 4, g_apSfxDriverTags[sfx_driver]);
        if ((g_pSfxDriver = bak_load_chunk(fileName, g_szSsmTag, 0)) != (void far *)0) {
            g_nSfxResourceId = midi_driver_install_dispatch(
                (unsigned)g_pSfxDriver, (unsigned)((unsigned long)g_pSfxDriver >> 16));
            if (audio_resource_install_by_id(fileName, (int *)&g_nSfxResourceId, 0) == 0) {
                release_buffer(g_pSfxDriver, 1);
                g_pSfxDriver = (void far *)0;
                failed = 1;
            }
        } else {
            failed = 1;
        }
        sfx_driver = (sfx_driver == SNDDRV_NONE) ? SNDDRV_M32 : sfx_driver;
    }

    g_nSfxDriverMode = sfx_driver;
    return !failed;
}
