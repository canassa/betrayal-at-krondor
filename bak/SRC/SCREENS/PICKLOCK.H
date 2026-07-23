#ifndef BAK_PICKLOCK_H
#define BAK_PICKLOCK_H

#include "structs.h"
#include "SRC/WORLD/ACTOR/ACTOR.H"

extern unsigned char g_bInventoryShopMode;
extern unsigned char g_abInvQuizAnswerTable[13];
extern unsigned char g_bPicklockSuccess;
extern short g_nPicklockMode;
extern unsigned char far *g_pPicklockWorkingInv;
extern Actor far *g_pPicklockOwnerActor;
extern short g_nPicklockScore;
extern short g_nPicklockDiffTier;

extern int picklock_screen_run(int score, int mode, Actor far *record);
extern void picklock_lock_slide_animation(int dir);
extern int picklock_screen_handle_drop(int item_kind, int slot);
extern void picklock_inv_info_query_disp(void);

#endif
