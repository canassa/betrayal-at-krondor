#ifndef BAK_ACTOROVL_H
#define BAK_ACTOROVL_H

#include "structs.h"

extern unsigned char g_nEncounterMarkerColorIdx;
extern unsigned char g_render_actor_wstate_scratch[2];
extern unsigned short g_bShakeActorEnabled;
extern unsigned char g_bShakeJitterX;
extern unsigned char g_bShakeJitterY;
extern ImageRecord **g_pAssetTable2;
extern unsigned char g_bOverlaySpriteIdxScratch;

extern void actoroverlay_image_1ff4_load(void);
extern void actoroverlay_image_1ff4_free(void);
extern void actoroverlay_render_actor(WorldObject far *visible_entry);

#endif
