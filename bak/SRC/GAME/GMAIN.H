#ifndef BAK_GMAIN_H
#define BAK_GMAIN_H

#include "structs.h"

typedef struct GameState {
    unsigned short nChapter;
    long nParty_gold;
    unsigned long game_time;
    unsigned long dwLastActionTimeSnapshot;
    unsigned char bCombatExitRequest;
    unsigned char nWorldLoopExitRequest;
    unsigned char rsvd_10[1];
    unsigned char nPrevZoneId;
    unsigned char nZoneId;
    unsigned char nPlayerTileX;
    unsigned char nPlayerTileY;
    WorldPos2 zoneDefaultCameraPos;
    unsigned char rsvd_1d[4];
    unsigned short wZoneDefaultCameraHeading;
    unsigned char abTeleportRecord[11];
    short nLastSeenStepSpeed;
    short nLastSeenGridStride;
    short nWorldStepPending;
    unsigned char nWorldStepTickCount;
    unsigned short world_step_tick;
    long lInsetCameraPosZ;
    char pParty_names[6][10];
    CombatActor party_members[6];
    char partySize;
    char party_roster[3];
    struct Actor far *shared_inventory;
    struct Actor far *ground_pile;
    unsigned char bPartyDirtyFlags;
    unsigned int dwPopup_retry_state;
    unsigned short aConditionTickAdvance[6];
    unsigned char abActorStatusRanks[6][7];
    ActorStatModTable aActorStatModifiers;
    short nEvtArgActor0;
    short nEvtArgActor1;
    short nEvtArgStat;
    unsigned char rsvd_59c[2];
    short nEvtArgCount;
    short nEvtArgAux1;
    short nEvtArgItemId;
    short nEvtArgDlgResult;
    long lEvtArgGoldCost;
    long lEvtArgValue;
    long lEvtArgAuxValue;
    short nTimerEventPoolCount;
    TimerEventEntry aTimerEventPool[20];
    unsigned short wPalEventMask;
    short nSpellMenuCasterSlot;
    short nSpellMenuPreselect;
    short nPalFadeDirty;
    short nPrevWorldBrightness;
    short world_brightness;
    short nPalDaynightDelta;
    short nPalAreaBrightness;
    short nPalBrightnessBoost;
    short nPalBlendWeight;
    ObjFixedLocationCacheEntry objfixed_location_cache;
    unsigned char event_bitmap_lo[1063];
    unsigned char event_bitmap_hi[50];
} GameState;

extern unsigned long g_nVec3DistResult;
extern PolyRasterState g_polyRasterState;
extern unsigned char g_bCutsceneEscPressed;
extern unsigned char g_bssgap_4863[3];
extern GameState g_gameState;
extern unsigned short g_bPaletteCycleEbActive;
extern unsigned short g_wVgaScratchPageBase;
extern unsigned short g_wGameFontSlot;
extern unsigned short *g_pSkyPanoAssetTable;
#ifdef V102CD
extern int g_cd_present;
#endif
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
