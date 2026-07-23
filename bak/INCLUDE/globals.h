#ifndef BAK_GLOBALS_H
#define BAK_GLOBALS_H
#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"

extern unsigned short g_wRandIdxJ;
extern unsigned short g_wRandIdxI;
extern unsigned short g_wRandLastVal;
extern unsigned short g_wRandTable[56];
extern unsigned long g_nVec3DistResult;
extern PolyRasterState g_polyRasterState;
extern unsigned char g_bCutsceneEscPressed;
extern Vec3Short g_aActorBoxCornerOffsets[8];
extern unsigned short g_awBoxBorderChars[9];
extern int g_nEmsInit;
extern int g_nEmsResourcesEnabled;
extern unsigned short g_wEmmPagesFree;
extern char g_szVmcodeOvl[11];
extern unsigned char __dat_1466[10];

extern char g_szHealthStamina[15];
extern char g_szRations[8];
extern char g_szEncampOfSep[6];
extern GraphicsContext g_graphics_context;
extern unsigned short g_wScreen_width;
extern unsigned short g_wScreen_height;
extern unsigned short g_pRow_offset_lut[200];
extern GraphicsContextRender g_graphics_context_render;
extern GfxDefaultFn far *g_gfx_default_fptr;
extern VideoDriverImports g_video_driver_imports;
extern char s_chunk_tag_FNT[5];
extern char s_open_mode_r[2];
extern void *_realcvt;
extern void *__ScanTodVector;
extern void *__scanrslt;
extern void *__scanpop;

extern unsigned short g_wTimerTickRegistrySlot;
extern short g_nWorldViewYawNormal;
extern short g_nWorldViewYawChapter;
extern short g_nWorldViewFovNormal;
extern unsigned char g_bssgap_4c53;
extern unsigned char g_nWorldViewFovChapter;
extern unsigned char g_bssgap_4863[3];
extern GameState g_gameState;
extern unsigned short g_bPaletteCycleEbActive;
extern unsigned short g_wVgaScratchPageBase;
extern unsigned short g_wGameFontSlot;
extern unsigned short *g_pSkyPanoAssetTable;
extern WorldEntity *g_render_camera_scratch;
extern ViewContext *g_active_window;
extern unsigned short g_nChapterAtLoopExit;

extern unsigned short g_wGfxBlitDstPage;

extern void(far *g_pfn_blit_stretched)(void);

#endif
