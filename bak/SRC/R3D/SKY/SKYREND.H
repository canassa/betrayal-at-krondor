#ifndef BAK_SKYREND_H
#define BAK_SKYREND_H

#include "structs.h"

extern short g_nHorizonScratchW;
extern unsigned char g_bCurSkyColorR;
extern unsigned char g_bCurSkyColorG;
extern unsigned char g_bCurSkyColorB;
extern unsigned char g_bSkyBandSelectB;
extern unsigned char g_bSkyBandSelectA;
extern unsigned short g_wHorizonCamYaw;
extern unsigned short g_wHorizonCamPitch;
extern short g_nClipLineX0;
extern short g_nClipLineY0;
extern short g_nClipLineX1;
extern short g_nClipLineY1;
extern short g_nHorizonRowY;

extern void skyrender_sky_and_ground(unsigned short sky_r, unsigned short sky_g, unsigned short sky_b, unsigned short cam_yaw,
                                     unsigned short cam_pitch);

#endif
