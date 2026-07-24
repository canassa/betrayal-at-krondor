#include "structs.h"
#include "SRC/AUDIO/RES/AUDRESIN.H"
#include "SRC/GAME/MAINDATA.H"

short g_nPolygonTextureMode = 1;
unsigned short g_nWorldRenderJitter = 0x0000;
#ifdef V102CD
char *g_versionBanner = "Version 1.02 CD";
#else
char *g_versionBanner = "Version 1.00";
#endif
unsigned char _dgroup_gap_3e8[4] = {0, 0, 0, 0};
SoundDriverId g_sound_driver = SNDDRV_NONE;
IoFile *g_pSfxArchiveStream = {0};
unsigned int _ovrbuffer = 0x0d48;
unsigned char far *g_pMainScratchBuf = {0};
