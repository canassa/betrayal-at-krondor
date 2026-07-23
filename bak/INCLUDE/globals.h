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
extern unsigned short g_bCombatGridTerrainFeaturesEnabled;
extern unsigned short g_bCombatGridLinesEnabled;
extern unsigned short g_bShowActorRosterIndex;
extern unsigned short g_bStormAmplify;
extern unsigned short **g_pTerrainBackupGrid;
extern unsigned short g_awQuarrelKindItemIdTable[8];
extern unsigned short g_quarrel_kind_field19_table[8];
extern unsigned char __dat_1466[10];

extern char g_szHealthStamina[15];
extern char g_szRations[8];
extern char g_szEncampOfSep[6];
extern unsigned short g_wZoneFlags;
extern char g_szZoneRefFilenameTmpl[11];
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

extern short g_game_mode;
extern WorldEntity *g_world_camera;
extern ViewContext *g_world_widget;
extern unsigned char g_bZoneSkyColor;
extern unsigned char g_bZoneGroundColor;
extern void *g_pZoneGridData;
extern short g_nZoneRenderTableCount;
extern char g_szZoneMapFilename[13];
extern CombatActor *g_current_actor;
extern CombatActor *g_picked_actor;
extern unsigned short g_acting_actor_speed;
extern int g_grid_tile_size;
extern short g_cursor_tile_x;
extern short g_cursor_tile_y;
extern unsigned short g_wInCombatMode;
extern MenuPage *g_combat_menu;
extern MenuPage *g_shoot_menu;
extern unsigned short g_combat_menu_selected_item;
extern unsigned short g_combat_menu_current_page;
extern short g_nCurrentQuarrelKindIdx;
extern unsigned short g_combat_cancelled;
extern unsigned short g_combat_music_handle;
extern CombatActor *g_acting_actor;
extern unsigned short g_traps_loaded_flag;
extern unsigned short g_encounter_id;
extern CombatActor *g_pCombatActiveActors;
extern AnimSlot *g_pCombatActiveAnimPool;
extern int g_nCombatActiveCount;
extern CombatActor *g_pCombatOtherActors;
extern AnimSlot *g_pCombatOtherAnimPool;
extern int g_nCombatOtherCount;
extern ImageRecord **g_combat_sprites;
extern ImageRecord **g_parch_bmx;
extern ImageRecord **g_combat_render_table_prev;
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
