#ifndef BAK_AUDRESIN_H
#define BAK_AUDRESIN_H

#include "structs.h"

enum SoundDriverId {
    SNDDRV_STD = 0,
    SNDDRV_TAN = 1,
    SNDDRV_ADL = 2,
    SNDDRV_M32 = 3,
    SNDDRV_SBP = 4,
    SNDDRV_PS1 = 5,
    SNDDRV_PRO = 6,
    SNDDRV_GMD = 7,
    SNDDRV_NONE = 8
};
typedef enum SoundDriverId SoundDriverId;

extern SoundDriverId g_sound_driver;

extern int audio_resource_install_by_id(char *file, int *p_resource_id, int load_mode);

extern char g_szSsmTemplate[9];
extern char g_szSsmTag[9];
extern char *g_apSfxDriverTags[9];
extern char *g_apMusicDriverTags[5];
extern char g_szSfxTag_STD[5];
extern char g_szSfxTag_TAN[5];
extern char g_szSfxTag_ADL[5];
extern char g_szSfxTag_M32[5];
extern char g_szSfxTag_SBP[5];
extern char g_szSfxTag_PS1[5];
extern char g_szSfxTag_PRO[5];
extern char g_szSfxTag_GMD[5];
extern char g_szSfxTag_NLD[5];
extern char g_szMusicTag_ASB[5];
extern char g_szMusicTag_APS[5];
extern char g_szMusicTag_ATD[5];
extern char g_szMusicTag_APA[5];
extern char g_szMusicTag_ADS[5];
extern short g_nSfxDriverMode;

#endif
