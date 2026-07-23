#ifndef BAK_VIDDRV_H
#define BAK_VIDDRV_H

#include "structs.h"
#include "SRC/IO/IO.H"

extern void huge *g_pVideoDriverTemplate;
extern char g_szDrvSuffix_BAD[3];
extern unsigned short g_apVideoDriverChunkNames[13];
extern char g_szVideoChunkName[10];
extern char g_szDrvSuffix_CGA[5];
extern char g_szDrvSuffix_EGA[5];
extern char g_szDrvSuffix_TAN[5];
extern char g_szDrvSuffix_HER[5];
extern char g_szDrvSuffix_MCG[5];
extern char g_szDrvSuffix_EVA[5];
extern char g_szDrvSuffix_VGA[5];
extern char g_szDrvSuffix_EVG[5];
extern char g_szDrvSuffix_HVG[5];
extern char g_szDrvSuffix_HEG[5];
extern char g_szDrvSuffix_NEW[5];

extern unsigned long far *video_driver_load(int mode, BakFileRef *file);

#endif
