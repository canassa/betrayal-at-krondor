#ifndef R3D_H
#define R3D_H

#include "structs.h"

extern R3dRendererState far g_abR3dState;

extern Mat3x3 far g_mat3x3ViewRot;
extern short far g_nViewportCenterX;
extern short far g_nViewportCenterY;

typedef struct {
    short x;
    short y;
} ViewportCenter;
extern ViewportCenter far g_viewportCenter;

extern short far g_camViewYaw;
extern short far g_camViewPitch;

typedef struct {
    short yaw;
    short pitch;
} CamViewAngles;
extern CamViewAngles far g_camViewAngles;

extern int far g_nCurModelIdx;
extern unsigned short far g_wActorProjScale;
extern long far g_lActorRelX;
extern long far g_lActorRelY;
extern short far g_nActorFarClipThreshold;
extern unsigned char far g_nScreenShift;

extern unsigned short far g_wMeshVertexPoolOff;
extern unsigned short far g_nMeshPartVertexCount;
extern unsigned char far g_bCurMeshLod;
extern unsigned short far g_wMeshScaleResidual;
extern Mat3x3 far g_mat3x3ActorRot;
extern short far g_nMeshOriginX;
extern short far g_nMeshOriginY;
extern short far g_nMeshOriginZ;

extern void far *far g_pCurActorPagedRec;
extern unsigned char *far g_pCurMeshPartVisTable;

extern unsigned char *far g_pColorRemapTable;

extern long far g_dwActorCamX;
extern long far g_dwActorCamZ;
extern long far g_dwActorCamY;
extern long far g_dwMeshBoundHalfExtent;
extern unsigned char far g_bSkipFarEdgeCull;
extern unsigned char far g_bActorViewportClip;

extern unsigned short far g_wMeshScaleShift;
extern unsigned char far g_bMeshRenormCount;
extern long far g_dwActorBoundExtent;
extern long far g_lActorLodZ;
extern long far g_lActorClampedCamZ;
extern short far g_nMeshNormOriginX;
extern unsigned long far g_dwMeshVertexFarPtrCache;

extern short far g_nMeshCamOriginX;
extern short far g_nMeshCamOriginY;
extern short far g_nMeshCamOriginZ;

#endif
