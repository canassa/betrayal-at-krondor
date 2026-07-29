#ifndef BAK_GMAIN_H
#define BAK_GMAIN_H

#include "structs.h"

/** Size of the recruitable character pool. */
#define CHARACTER_POOL_SIZE 6

/** Maximum members in the active/traveling party. */
#define MAX_ACTIVE_PARTY 3

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
    char characterNames[CHARACTER_POOL_SIZE][10];

    /**
     * The six recruitable characters' persistent @ref Combatant records,
     * indexed by character id (0..5). The active traveling subset is chosen
     * by @ref GameState::activeParty; each record is copied to and from the
     * combat grid at combat start and end.
     */
    Combatant characters[CHARACTER_POOL_SIZE];

    /**
     * Number of members in the active/traveling party — the count of
     * valid @ref GameState::activeParty entries (0..3), not the 6-member
     * character pool (@ref GameState::characters).
     */
    char partySize;

    /**
     * Pool indices (0..5, into @ref GameState::characters) of the active
     * traveling party; @ref GameState::partySize entries are valid, and 0xFF
     * marks an empty slot.
     */
    char activeParty[MAX_ACTIVE_PARTY];

    struct Actor far *shared_inventory;
    struct Actor far *ground_pile;
    unsigned char bPartyDirtyFlags;
    unsigned int dwPopup_retry_state;
    unsigned short aConditionTickAdvance[CHARACTER_POOL_SIZE];
    unsigned char abActorStatusRanks[CHARACTER_POOL_SIZE][7];
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
