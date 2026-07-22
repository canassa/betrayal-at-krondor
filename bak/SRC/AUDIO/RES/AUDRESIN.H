#ifndef BAK_AUDRESIN_H
#define BAK_AUDRESIN_H

#include "structs.h"

#define SNDDRV_STD 0
#define SNDDRV_TAN 1
#define SNDDRV_ADL 2
#define SNDDRV_M32 3
#define SNDDRV_SBP 4
#define SNDDRV_PS1 5
#define SNDDRV_PRO 6
#define SNDDRV_GMD 7
#define SNDDRV_NONE 8

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
