#ifndef BAK_GMAIN_H
#define BAK_GMAIN_H

#include "structs.h"

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

extern int gmain_start_dispatch(int mode);
extern void gmain_play_intro_animation(void);
extern int gmain_play_chapter_intro(int chapter, int part);
extern int gmain_play_chapter_cutscene(int chapter_num, int channel_1, int channel_2);
extern void gmain_screen_fade_to_black(void);
extern void gmain_cutsc_play_fullmap_scene(int scene_index);
extern void gmain_restart_from_save_flow(void);
extern void gmain_parse_cmdline_sound_flag(int argc, char **argv);


#endif
