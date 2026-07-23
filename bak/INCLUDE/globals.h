#ifndef BAK_GLOBALS_H
#define BAK_GLOBALS_H
#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"

extern unsigned long g_nVec3DistResult;
extern PolyRasterState g_polyRasterState;
extern unsigned char g_bCutsceneEscPressed;

extern unsigned char g_bssgap_4863[3];
extern GameState g_gameState;
extern unsigned short g_bPaletteCycleEbActive;
extern unsigned short g_wVgaScratchPageBase;
extern unsigned short g_wGameFontSlot;
extern unsigned short *g_pSkyPanoAssetTable;
extern WorldEntity *g_render_camera_scratch;
extern ViewContext *g_active_window;
extern unsigned short g_nChapterAtLoopExit;

#endif
