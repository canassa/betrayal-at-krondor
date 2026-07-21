; ============================================================================
; R3DDATA.ASM  --  renderer state and lookup tables
;
; Everything the 3-D renderer keeps in its own segment: the camera state,
; the actor/mesh transform scratch, the per-vertex transform and clip
; arrays, the polygon buffers, and the cosine and lighting-ramp tables.
; Data only, no code. The sibling code modules read it with DS=CS (plain
; '[label]' operands) or explicit cs:/es: overrides -- see R3D.ASM for
; the conventions.
;
; The '_'-prefixed aliases at the end are the linkage names other
; segments (and the C code) reach this state through; the actor-render
; code addresses them as far data.
;
; One of the four source files of segment S233E_TEXT; the link order is
; fixed by KRONDOR.RSP.
; ============================================================================

.286

S233E_TEXT	segment word public use16 'CODE'
	assume cs:S233E_TEXT, ds:S233E_TEXT

; ============================================================================
; DATA BLOCK  0x3784 .. 0x60db
; CS-resident renderer state variables and lookup tables.
; All zero-init state items are uninitialised at load time (BSS-like).
; ============================================================================

; 0x3784: base of the whole CS-resident renderer-state struct. These scalars are
; accessed as fields of one far struct (R3dRendererState): bc31 loads SEG once and
; reuses ES across a run of field accesses. The zero-width base label here (same
; offset as the first datum) lets r3d.h's `extern R3dRendererState far g_abR3dState;`
; resolve to 233e:3784, and `g_abR3dState.<field>` derives the segment-relative
; displacement. Zero-width => no storage.  [g_abR3dState]
_g_abR3dState	label byte	; struct-base export alias (r3d.h; ACTRENDR/WORLDRND field-access reuse)
; 0x3784-0x3785: uint: far ptr cache lo word  [g_dwMeshVertexFarPtrCache]
_g_dwMeshVertexFarPtrCache	label dword	; <-- export alias (read by actorrender_entity)
g_dwMeshVertexFarPtrCache	dw 0

; 0x3786-0x3787: ushort: far ptr cache segment  [g_wMeshVertexCacheSeg]
g_wMeshVertexCacheSeg	dw 0

; 0x3788-0x3789: ushort: vertex pool offset  [g_wMeshVertexPoolOff]
_g_wMeshVertexPoolOff	label word	; <-- export alias
g_wMeshVertexPoolOff	dw 0

; 0x378a-0x378b: ushort: vertex count for current part  [g_nMeshPartVertexCount]
_g_nMeshPartVertexCount	label word	; <-- export alias
g_nMeshPartVertexCount	dw 0

; 0x378c-0x378d: ushort: scale right-shift count  [g_wMeshScaleShift]
_g_wMeshScaleShift	label word	; <-- export alias (read by actorrender_entity)
g_wMeshScaleShift	dw 0

; 0x378e-0x378f: ushort: scale residual  [g_wMeshScaleResidual]
_g_wMeshScaleResidual	label word	; <-- export alias
g_wMeshScaleResidual	dw 0

; 0x3790-0x3791: byte: renorm count  [g_bMeshRenormCount]
; Semantic width is a byte (C reads g_bMeshRenormCount); the producer intentionally
; stores a full word here, zeroing the pad byte at 0x3791.
_g_bMeshRenormCount	label byte	; <-- export alias (read by actorrender_entity)
g_bMeshRenormCount	dw 0

; 0x3792-0x3792: byte: current LOD index  [g_bCurMeshLod]
_g_bCurMeshLod	label byte	; <-- export alias
g_bCurMeshLod	db 0

; 0x3793-0x3793: uchar: camera-setup reset flag (write-only here; cleared to 0
; by r3d_camera_setup_view alongside g_bSkipFarEdgeCull; no reader in this build,
; so its exact predicate is unconfirmed)  [g_bCamSetupResetFlag]
g_bCamSetupResetFlag	db 0

; 0x3794-0x3794: uchar: skip far edge culling flag  [g_bSkipFarEdgeCull]
_g_bSkipFarEdgeCull	label byte	; <-- export alias
g_bSkipFarEdgeCull	db 0

; 0x3795-0x3795: uchar: actor viewport clip flag  [g_bActorViewportClip]
_g_bActorViewportClip	label byte	; <-- export alias
g_bActorViewportClip	db 0

; 0x3796-0x3796: byte: gap (zero-init)
	db 0

; 0x3797-0x3797: uchar: polygon normal flip flag  [g_bPolyNormalFlipped]
g_bPolyNormalFlipped	db 0

; 0x3798-0x37aa: 19 bytes: view rotation matrix (3x3 short + type byte)  [g_mat3x3ViewRot]
_g_mat3x3ViewRot	label byte	; <-- export alias (C: r3d.h, project_world_to_screen)
g_mat3x3ViewRot	db 19 dup(0)

; 0x37ab-0x37ac: 19 bytes: actor rotation matrix start  [g_mat3x3ActorRot]
_g_mat3x3ActorRot	label byte	; <-- export alias (read by worldrender_sprite_billboard)
	public g_mat3x3ActorRot
g_mat3x3ActorRot	dw 0

; 0x37ad-0x37ae: field +2 of g_mat3x3ActorRot = m[0][1] (column-1 X coeff)  [g_nActorRotM01]
g_nActorRotM01	dw 0

; 0x37af-0x37b2: 4 bytes: g_mat3x3ActorRot fields +4..+7
	dd 0

; 0x37b3-0x37b4: field +8 of g_mat3x3ActorRot = m[1][1] (column-1 Y coeff)  [g_nActorRotM11]
g_nActorRotM11	dw 0

; 0x37b5-0x37b8: 4 bytes: g_mat3x3ActorRot fields +a..+d
	dd 0

; 0x37b9-0x37ba: field +e of g_mat3x3ActorRot = m[2][1] (column-1 Z coeff)  [g_nActorRotM21]
g_nActorRotM21	dw 0

; 0x37bb-0x37bd: 3 bytes: g_mat3x3ActorRot fields +10..+12 (type byte)
	db 3 dup(0)

; 0x37be-0x37d0: 19 bytes: temp output matrix (3x3 short + type byte)  [g_mat3x3TempOut]
g_mat3x3TempOut	db 19 dup(0)

; 0x37d1-0x37d4: long lo: actor-relative world X delta  [g_lActorRelX]
_g_lActorRelX	label dword	; <-- export alias (cross-seg, no bytes)
g_lActorRelX	dw 0

; 0x37d3-0x37d4: long hi: actor-relative world X delta
	dw 0

; 0x37d5-0x37d8: long lo: actor-relative world Y delta  [g_lActorRelY]
_g_lActorRelY	label dword	; <-- export alias
g_lActorRelY	dw 0

; 0x37d7-0x37d8: long hi: actor-relative world Y delta
	dw 0

; 0x37d9-0x37da: long lo: actor-relative world Z delta  [g_lActorRelZ]
g_lActorRelZ	dw 0

; 0x37db-0x37dc: long hi: actor-relative world Z delta
	dw 0

; 0x37dd-0x37de: long lo: actor cam-space X  [g_dwActorCamX]
_g_dwActorCamX	label dword		; <-- export alias (cross-seg, no bytes)
g_dwActorCamX	dw 0

; 0x37df-0x37e0: long hi: actor cam-space X  [g_dwActorCamX_hi]
g_dwActorCamX_hi	dw 0

; 0x37e1-0x37e2: long lo: actor cam-space Z  [g_dwActorCamZ]
_g_dwActorCamZ	label dword		; <-- export alias
g_dwActorCamZ	dw 0

; 0x37e3-0x37e4: long hi: actor cam-space Z  [g_dwActorCamZ_hi]
g_dwActorCamZ_hi	dw 0

; 0x37e5-0x37e6: long lo: actor cam-space Y  [g_dwActorCamY]
_g_dwActorCamY	label dword		; <-- export alias
g_dwActorCamY	dw 0

; 0x37e7-0x37e8: long hi: actor cam-space Y  [g_dwActorCamY_hi]
g_dwActorCamY_hi	dw 0

; 0x37e9-0x37ea: short: mesh origin X in cam coords  [g_nMeshCamOriginX]
_g_nMeshCamOriginX	label word	; <-- export alias
g_nMeshCamOriginX	dw 0

; 0x37eb-0x37ec: short: mesh origin Y in cam coords  [g_nMeshCamOriginY]
_g_nMeshCamOriginY	label word	; <-- export alias
g_nMeshCamOriginY	dw 0

; 0x37ed-0x37ee: short: mesh origin Z in cam coords  [g_nMeshCamOriginZ]
_g_nMeshCamOriginZ	label word	; <-- export alias
g_nMeshCamOriginZ	dw 0

; 0x37ef-0x37f0: short: mesh origin X (screen)  [g_nMeshOriginX]
_g_nMeshOriginX	label word	; <-- export alias (read by worldrender_sprite_billboard)
	public g_nMeshOriginX
g_nMeshOriginX	dw 0

; 0x37f1-0x37f2: short: mesh origin Y (screen)  [g_nMeshOriginY]
_g_nMeshOriginY	label word	; <-- export alias (read by actorrender_entity)
g_nMeshOriginY	dw 0

; 0x37f3-0x37f4: short: mesh origin Z (screen)  [g_nMeshOriginZ]
_g_nMeshOriginZ	label word	; <-- export alias (read by actorrender_entity)
g_nMeshOriginZ	dw 0

; 0x37f5-0x3800: CameraWorldPos: 3x dword world coords  [g_camCurWorldPos]
g_camCurWorldPos	dw 6 dup(0)

; 0x3801-0x3802: short: camera yaw angle  [g_camViewYaw]
_g_camViewAngles	label word	; <-- export alias for struct {yaw,pitch} (read by world_render_frame)
_g_camViewYaw	label word	; <-- export alias (read by world_render_frame)
g_camViewYaw	dw 0

; 0x3803-0x3804: short: camera pitch angle  [g_camViewPitch]
_g_camViewPitch	label word	; <-- export alias (read by world_render_frame)
g_camViewPitch	dw 0

; 0x3805-0x3806: short: camera heading angle  [g_camViewHeading]
g_camViewHeading	dw 0

; 0x3807-0x3808: int: current model index  [g_nCurModelIdx]
_g_nCurModelIdx	label word	; <-- export alias
g_nCurModelIdx	dw 0

; 0x3809-0x380c: undefined1 *32: far ptr to actor paged record (dword)  [g_pCurActorPagedRec]
; (exported as _g_pCurActorPagedRec in the cross-segment export block at EOF)
_g_pCurActorPagedRec	label dword	; <-- export alias
g_pCurActorPagedRec	dd 0

; 0x380d-0x380e: uchar *: near ptr to visibility table  [g_pCurMeshPartVisTable]
; (exported as _g_pCurMeshPartVisTable in the cross-segment export block at EOF)
_g_pCurMeshPartVisTable	label word	; <-- export alias
g_pCurMeshPartVisTable	dw 0

; 0x380f-0x3810: long lo: mesh bounding sphere half-extent  [g_dwMeshBoundHalfExtent]
_g_dwMeshBoundHalfExtent	label dword	; <-- export alias
g_dwMeshBoundHalfExtent	dw 0

; 0x3811-0x3812: long hi: mesh bounding sphere half-extent  [g_dwMeshBoundHalfExtent_hi]
g_dwMeshBoundHalfExtent_hi	dw 0

; 0x3813-0x3814: ulong lo: actor bounding extent  [g_dwActorBoundExtent]
_g_dwActorBoundExtent	label dword	; <-- export alias (read by actorrender_entity)
g_dwActorBoundExtent	dw 0

; 0x3815-0x3816: ulong hi: actor bounding extent  [g_dwActorBoundExtent_hi]
g_dwActorBoundExtent_hi	dw 0

; 0x3817-0x3818: long lo: actor LOD Z distance  [g_lActorLodZ]
_g_lActorLodZ	label dword	; <-- export alias (read by actorrender_entity)
g_lActorLodZ	dw 0

; 0x3819-0x381a: long hi: actor LOD Z distance  [g_lActorLodZ_hi]
g_lActorLodZ_hi	dw 0

; 0x381b-0x381c: ushort: actor projection scale  [g_wActorProjScale]
_g_wActorProjScale	label word	; <-- export alias
g_wActorProjScale	dw 0

; 0x381d-0x3822: 6 bytes: object-space directional-light vector (3 shorts) --
; g_vec3LightDirWorld rotated through the transposed actor matrix; dotted against face
; normals by the shader  [g_vec3LightDirObj]
g_vec3LightDirObj	dw 3 dup(0)

; 0x3823-0x3824: long lo: actor clamped cam-space Z  [g_lActorClampedCamZ]
_g_lActorClampedCamZ	label dword	; <-- export alias (read by actorrender_entity)
g_lActorClampedCamZ	dw 0

; 0x3825-0x3826: long hi: actor clamped cam-space Z  [g_lActorClampedCamZ_hi]
g_lActorClampedCamZ_hi	dw 0

; 0x3827-0x3828: short: mesh norm origin X  [g_nMeshNormOriginX]
_g_nMeshNormOriginX	label word	; <-- export alias (read by actorrender_entity)
g_nMeshNormOriginX	dw 0

; 0x3829-0x382a: word: view-plane distance = 1<<screenShift  [g_nViewPlaneDist]
; One word, written once by r3d_camera_setup_view as 1<<g_nScreenShift. It doubles
; as the near-plane CamY threshold (three mesh producers + both near-Z clippers) and
; as the projection view-distance numerator (perspective divide / proj scale / calc_isect).
; The PUBLIC export alias _g_nActorFarClipThreshold below is the DGROUP-visible name that
; WORLDRND.C / r3d.h read; that C-side name is a misnomer -- internal ASM code uses the
; accurate g_nViewPlaneDist label for the same word.
_g_nActorFarClipThreshold	label word	; <-- export alias (C: r3d.h g_nActorFarClipThreshold)
g_nViewPlaneDist	dw 0

; 0x382b-0x382b: uchar: screen shift count  [g_nScreenShift]
_g_nScreenShift	label byte	; <-- export alias (cross-seg, no bytes)
g_nScreenShift	db 0

; 0x382c-0x382c: 1 byte: alignment gap
	db 0

; 0x382d-0x382e: short: viewport center X  [g_nViewportCenterX]
_g_viewportCenter	label word	; <-- export alias for struct {x,y} (C: r3d.h; world_render_record_marker_dot)
_g_nViewportCenterX	label word	; <-- export alias (C: r3d.h)
g_nViewportCenterX	dw 0

; 0x382f-0x3830: short: viewport center Y  [g_nViewportCenterY]
_g_nViewportCenterY	label word	; <-- export alias (C: r3d.h)
g_nViewportCenterY	dw 0

; 0x3831-0x3858: short[20]: polygon input X (low words; hi at g_aPolyInXHi)  [g_aPolyInX]
; The mesh producers fill this from g_aVertexScrX; the 2D clippers read it as their input pool.
g_aPolyInX	dw 20 dup(0)

; 0x3859-0x3880: short[20]: polygon input Y (low words; hi at g_aPolyInYHi)  [g_aPolyInY]
g_aPolyInY	dw 20 dup(0)

; 0x3881-0x38a8: short[20]: polygon clip-scratch X (low words; hi at g_aPolyClipXHi)  [g_aPolyClipX]
; Ping-pong clip output that swaps roles with g_aPolyInX pass-to-pass.
g_aPolyClipX	dw 20 dup(0)

; 0x38a9-0x38d0: short[20]: polygon clip-scratch Y (low words; hi at g_aPolyClipYHi)  [g_aPolyClipY]
g_aPolyClipY	dw 20 dup(0)

; 0x38d1-0x38d2: int: current polygon vertex count  [g_nMeshPolyVertexCount]
g_nMeshPolyVertexCount	dw 0

; 0x38d3-0x38fa: ushort[20]: polygon vertex index array  [g_polygon_vertices]
g_polygon_vertices	dw 20 dup(0)

; 0x38fb-0x3af8: byte[510]: polygon clip state per vertex  [g_abPolygonClipState]
g_abPolygonClipState	db 0

; 0x38fc-0x3af8: 509 bytes: g_abPolygonClipState rest
	db 509 dup(0)

; 0x3af9-0x3afa: short[255]: vertex cam-space X per vertex  [g_aVertexCamX]
g_aVertexCamX	dw 0

; 0x3afb-0x3cf6: 508 bytes: g_aVertexCamX rest
	dw 254 dup(0)

; 0x3cf7-0x3cf8: short[255]: vertex cam-space Y per vertex  [g_aVertexCamY]
g_aVertexCamY	dw 0

; 0x3cf9-0x3ef4: 508 bytes: g_aVertexCamY rest
	dw 254 dup(0)

; 0x3ef5-0x3ef6: short[255]: vertex cam-space Z per vertex  [g_aVertexCamZ]
g_aVertexCamZ	dw 0

; 0x3ef7-0x40f2: 508 bytes: g_aVertexCamZ rest
	dw 254 dup(0)

; 0x40f3-0x40f4: short[255]: vertex screen X per vertex  [g_aVertexScrX]
g_aVertexScrX	dw 0

; 0x40f5-0x42f0: 508 bytes: g_aVertexScrX rest
	dw 254 dup(0)

; 0x42f1-0x42f2: short[255]: vertex screen Y per vertex  [g_aVertexScrY]
g_aVertexScrY	dw 0

; 0x42f3-0x44ee: 508 bytes: g_aVertexScrY rest
	dw 254 dup(0)

; 0x44ef-0x4501: 19 bytes: scratch 3x3 rotation MATRIX  [g_mat3x3ScratchRot]
; build_rotation_matrix writes m[0..8] (9 Q14 shorts = 18 bytes) plus the type
; byte through this label; matrix3x3_multiply and mat3_xform_vec3_wrap take it as
; the Mat3x3 arg. The matrix body spans this labeled dw 3 dup(0) plus the adjacent
; bytes below (the 11-byte gap and g_matTransformScratch's byte) up to and including
; the type byte at offset +18 (g_bScratchMatType). Only labels/comments changed here;
; the data directives are the matrix storage split across historical sub-labels.
g_mat3x3ScratchRot	dw 3 dup(0)

; 0x44f5-0x44ff: 11 bytes: continuation of g_mat3x3ScratchRot's body (pM[3..7])
	db 11 dup(0)

; 0x4500-0x4500: reserved: tail byte of g_mat3x3ScratchRot's pM[8] (the scratch
; matrix body ends here); not an independent buffer  [g_matTransformScratch]
g_matTransformScratch	db 0

; 0x4501-0x4501: byte: g_mat3x3ScratchRot's type byte (offset +18); never written
; by anyone else — camera_setup tests it for "did the view matrix come out
; non-identity"  [g_bScratchMatType]
g_bScratchMatType	db 0

; 0x4502-0x4503: short: matrix input X  [g_matXIn]
g_matXIn	dw 0

; 0x4504-0x4505: short: matrix input Y  [g_matYIn]
g_matYIn	dw 0

; 0x4506-0x4507: short: matrix input Z  [g_matZIn]
g_matZIn	dw 0

; 0x4508-0x4509: short: matrix input X secondary  [g_matXIn2]
g_matXIn2	dw 0

; 0x450a-0x450b: short: matrix input Y secondary  [g_matYIn2]
g_matYIn2	dw 0

; 0x450c-0x450d: short: matrix input Z secondary  [g_matZIn2]
g_matZIn2	dw 0

; 0x450e-0x450f: short: matrix output X (16-bit)  [g_matXOut]
g_matXOut	dw 0

; 0x4510-0x4511: short: matrix output Y (16-bit)  [g_matYOut]
g_matYOut	dw 0

; 0x4512-0x4513: short: matrix output Z (16-bit)  [g_matZOut]
g_matZOut	dw 0

; 0x4514-0x452b: 24 bytes: matrix scratch fields
	dw 12 dup(0)

; 0x452c-0x452d: ushort: matrix output X lo (32-bit)  [g_matXOut32]
g_matXOut32	dw 0

; 0x452e-0x452f: ushort: matrix output X hi  [g_matXOut32Hi]
g_matXOut32Hi	dw 0

; 0x4530-0x4531: ushort: matrix output Z lo (32-bit)  [g_matZOut32]
g_matZOut32	dw 0

; 0x4532-0x4533: ushort: matrix output Z hi  [g_matZOut32Hi]
g_matZOut32Hi	dw 0

; 0x4534-0x4535: ushort: matrix output Y lo (32-bit)  [g_matYOut32]
g_matYOut32	dw 0

; 0x4536-0x4537: ushort: matrix output Y hi  [g_matYOut32Hi]
g_matYOut32Hi	dw 0

; 0x4538-0x4539: uchar *: near ptr to per-face material-id table  [g_pFaceMaterialTable]
; The shade path derefs this (indexed by fill color); copied from the ViewContext's
; faceMaterials field.
g_pFaceMaterialTable	dw 0

; 0x453a-0x453b: uchar *: near ptr to color remap table  [g_pColorRemapTable]
_g_pColorRemapTable	label word	; <-- export alias (C: r3d.h)
g_pColorRemapTable	dw 0

; 0x453c-0x4543: 8 bytes: zero-init state
	dw 4 dup(0)

; --- 32-bit split-word HIGH-word arrays (low words live at 0x3831.. / 0x3af9..) ---
; The renderer stores each 32-bit coordinate as two parallel word arrays: a
; low-word array (earlier in this block) and the matching high-word array here.

; 0x4544-0x456b: ushort[20]: polygon input-X high words  [g_aPolyInXHi]
g_aPolyInXHi	dw 20 dup(0)

; 0x456c-0x4593: ushort[20]: polygon input-Y high words  [g_aPolyInYHi]
g_aPolyInYHi	dw 20 dup(0)

; 0x4594-0x45bb: ushort[20]: polygon clip-scratch X high words  [g_aPolyClipXHi]  (456e+38)
g_aPolyClipXHi	dw 20 dup(0)

; 0x45bc-0x45e3: ushort[20]: polygon clip-scratch Y high words  [g_aPolyClipYHi]  (456e+78)
g_aPolyClipYHi	dw 20 dup(0)

; 0x45e4-0x47e1: short[255]: vertex cam-space X high words  [g_aVertexCamXHi]  (456e+118)
g_aVertexCamXHi	dw 255 dup(0)

; 0x47e2-0x49df: short[255]: vertex cam-space Y high words  [g_aVertexCamYHi]  (456e+628)
g_aVertexCamYHi	dw 255 dup(0)

; 0x49e0-0x4bdd: short[255]: vertex cam-space Z high words  [g_aVertexCamZHi]  (456e+1138)
g_aVertexCamZHi	dw 255 dup(0)

; 0x4bde-0x4ddb: short[255]: vertex screen-X high words  [g_aVertexScrXHi]  (456e+1648)
g_aVertexScrXHi	dw 255 dup(0)

; 0x4ddc-0x4fd9: short[255]: vertex screen-Y high words  [g_aVertexScrYHi]  (456e+2158)
g_aVertexScrYHi	dw 255 dup(0)

; 0x4fda-0x50d9: byte[256]: lighting lookup table (non-zero)  [g_abLightingLut]
g_abLightingLut	dw 0ffffh, 0ffffh, 0ffffh, 0ffffh, 0ffffh, 0ffffh, 0ffffh, 0ffffh
	dw 00000h, 00000h, 00000h, 00000h, 00000h, 00000h, 00000h, 00000h
	dw 0fefeh, 0fefeh, 0fefeh, 0fefeh, 0fefeh, 0ffffh, 0ffffh, 0ffffh
	dw 00000h, 00000h, 00000h, 00101h, 00101h, 00101h, 00101h, 00101h
	dw 0fdfdh, 0fdfdh, 0fdfdh, 0fdfdh, 0fefeh, 0fefeh, 0ffffh, 0ffffh
	dw 00000h, 00000h, 00101h, 00101h, 00202h, 00202h, 00202h, 00202h
	dw 0fcfch, 0fcfch, 0fcfch, 0fdfdh, 0fdfdh, 0fefeh, 0fefeh, 0ffffh
	dw 00000h, 00101h, 00101h, 00202h, 00202h, 00303h, 00303h, 00303h
	dw 0fbfbh, 0fbfbh, 0fbfbh, 0fcfch, 0fdfdh, 0fefeh, 0ffffh, 0ffffh
	dw 00000h, 00101h, 00202h, 00303h, 00303h, 00404h, 00404h, 00404h
	dw 0fafah, 0fafah, 0fafah, 0fbfbh, 0fcfch, 0fdfdh, 0fefeh, 0ffffh
	dw 00000h, 00101h, 00202h, 00303h, 00404h, 00505h, 00505h, 00505h
	dw 0f9f9h, 0f9f9h, 0faf9h, 0fbfah, 0fcfch, 0fdfdh, 0fefeh, 0ffffh
	dw 00000h, 00101h, 00202h, 00303h, 00504h, 00605h, 00606h, 00606h
	dw 0f8f8h, 0f8f8h, 0f9f8h, 0faf9h, 0fbfbh, 0fdfch, 0fefdh, 0ffffh
	dw 00000h, 00201h, 00302h, 00404h, 00605h, 00706h, 00707h, 00707h

; 0x50da-0x60db: short[2049]: Q14 cosine table, entry[0]=16384  [g_awCosTable]
	public g_awCosTable	; read cross-module by R3DTRIG.OBJ (r3d_tbl_sin/cos)
g_awCosTable	dw 04000h, 03fffh, 03fffh, 03fffh, 03fffh, 03fffh, 03fffh, 03fffh
	dw 03ffeh, 03ffeh, 03ffeh, 03ffdh, 03ffdh, 03ffch, 03ffch, 03ffbh
	dw 03ffbh, 03ffah, 03ff9h, 03ff9h, 03ff8h, 03ff7h, 03ff6h, 03ff5h
	dw 03ff4h, 03ff3h, 03ff2h, 03ff1h, 03ff0h, 03fefh, 03feeh, 03fedh
	dw 03fech, 03febh, 03fe9h, 03fe8h, 03fe7h, 03fe5h, 03fe4h, 03fe2h
	dw 03fe1h, 03fdfh, 03fdeh, 03fdch, 03fdah, 03fd8h, 03fd7h, 03fd5h
	dw 03fd3h, 03fd1h, 03fcfh, 03fcdh, 03fcbh, 03fc9h, 03fc7h, 03fc5h
	dw 03fc3h, 03fc1h, 03fbfh, 03fbch, 03fbah, 03fb8h, 03fb5h, 03fb3h
	dw 03fb1h, 03faeh, 03fach, 03fa9h, 03fa6h, 03fa4h, 03fa1h, 03f9eh
	dw 03f9ch, 03f99h, 03f96h, 03f93h, 03f90h, 03f8dh, 03f8ah, 03f87h
	dw 03f84h, 03f81h, 03f7eh, 03f7bh, 03f78h, 03f74h, 03f71h, 03f6eh
	dw 03f6ah, 03f67h, 03f64h, 03f60h, 03f5dh, 03f59h, 03f55h, 03f52h
	dw 03f4eh, 03f4ah, 03f47h, 03f43h, 03f3fh, 03f3bh, 03f37h, 03f33h
	dw 03f2fh, 03f2bh, 03f27h, 03f23h, 03f1fh, 03f1bh, 03f17h, 03f13h
	dw 03f0eh, 03f0ah, 03f06h, 03f01h, 03efdh, 03ef8h, 03ef4h, 03eefh
	dw 03eebh, 03ee6h, 03ee1h, 03eddh, 03ed8h, 03ed3h, 03eceh, 03ecah
	dw 03ec5h, 03ec0h, 03ebbh, 03eb6h, 03eb1h, 03each, 03ea7h, 03ea1h
	dw 03e9ch, 03e97h, 03e92h, 03e8ch, 03e87h, 03e82h, 03e7ch, 03e77h
	dw 03e71h, 03e6ch, 03e66h, 03e61h, 03e5bh, 03e55h, 03e50h, 03e4ah
	dw 03e44h, 03e3eh, 03e38h, 03e33h, 03e2dh, 03e27h, 03e21h, 03e1bh
	dw 03e14h, 03e0eh, 03e08h, 03e02h, 03dfch, 03df5h, 03defh, 03de9h
	dw 03de2h, 03ddch, 03dd6h, 03dcfh, 03dc9h, 03dc2h, 03dbbh, 03db5h
	dw 03daeh, 03da7h, 03da1h, 03d9ah, 03d93h, 03d8ch, 03d85h, 03d7eh
	dw 03d77h, 03d70h, 03d69h, 03d62h, 03d5bh, 03d54h, 03d4dh, 03d45h
	dw 03d3eh, 03d37h, 03d2fh, 03d28h, 03d21h, 03d19h, 03d12h, 03d0ah
	dw 03d02h, 03cfbh, 03cf3h, 03cech, 03ce4h, 03cdch, 03cd4h, 03ccch
	dw 03cc5h, 03cbdh, 03cb5h, 03cadh, 03ca5h, 03c9dh, 03c95h, 03c8ch
	dw 03c84h, 03c7ch, 03c74h, 03c6ch, 03c63h, 03c5bh, 03c53h, 03c4ah
	dw 03c42h, 03c39h, 03c31h, 03c28h, 03c20h, 03c17h, 03c0eh, 03c06h
	dw 03bfdh, 03bf4h, 03bebh, 03be2h, 03bdah, 03bd1h, 03bc8h, 03bbfh
	dw 03bb6h, 03badh, 03ba3h, 03b9ah, 03b91h, 03b88h, 03b7fh, 03b75h
	dw 03b6ch, 03b63h, 03b59h, 03b50h, 03b47h, 03b3dh, 03b34h, 03b2ah
	dw 03b20h, 03b17h, 03b0dh, 03b03h, 03afah, 03af0h, 03ae6h, 03adch
	dw 03ad2h, 03ac8h, 03abeh, 03ab4h, 03aaah, 03aa0h, 03a96h, 03a8ch
	dw 03a82h, 03a78h, 03a6dh, 03a63h, 03a59h, 03a4fh, 03a44h, 03a3ah
	dw 03a2fh, 03a25h, 03a1ah, 03a10h, 03a05h, 039fbh, 039f0h, 039e5h
	dw 039dah, 039d0h, 039c5h, 039bah, 039afh, 039a4h, 03999h, 0398eh
	dw 03983h, 03978h, 0396dh, 03962h, 03957h, 0394ch, 03941h, 03935h
	dw 0392ah, 0391fh, 03913h, 03908h, 038fdh, 038f1h, 038e6h, 038dah
	dw 038cfh, 038c3h, 038b7h, 038ach, 038a0h, 03894h, 03889h, 0387dh
	dw 03871h, 03865h, 03859h, 0384dh, 03841h, 03835h, 03829h, 0381dh
	dw 03811h, 03805h, 037f9h, 037edh, 037e0h, 037d4h, 037c8h, 037bbh
	dw 037afh, 037a3h, 03796h, 0378ah, 0377dh, 03771h, 03764h, 03757h
	dw 0374bh, 0373eh, 03731h, 03725h, 03718h, 0370bh, 036feh, 036f1h
	dw 036e5h, 036d8h, 036cbh, 036beh, 036b1h, 036a4h, 03696h, 03689h
	dw 0367ch, 0366fh, 03662h, 03654h, 03647h, 0363ah, 0362ch, 0361fh
	dw 03612h, 03604h, 035f7h, 035e9h, 035dch, 035ceh, 035c0h, 035b3h
	dw 035a5h, 03597h, 03589h, 0357ch, 0356eh, 03560h, 03552h, 03544h
	dw 03536h, 03528h, 0351ah, 0350ch, 034feh, 034f0h, 034e2h, 034d4h
	dw 034c6h, 034b7h, 034a9h, 0349bh, 0348ch, 0347eh, 03470h, 03461h
	dw 03453h, 03444h, 03436h, 03427h, 03419h, 0340ah, 033fbh, 033edh
	dw 033deh, 033cfh, 033c1h, 033b2h, 033a3h, 03394h, 03385h, 03376h
	dw 03367h, 03358h, 03349h, 0333ah, 0332bh, 0331ch, 0330dh, 032feh
	dw 032eeh, 032dfh, 032d0h, 032c1h, 032b1h, 032a2h, 03293h, 03283h
	dw 03274h, 03264h, 03255h, 03245h, 03236h, 03226h, 03216h, 03207h
	dw 031f7h, 031e7h, 031d8h, 031c8h, 031b8h, 031a8h, 03198h, 03188h
	dw 03179h, 03169h, 03159h, 03149h, 03138h, 03128h, 03118h, 03108h
	dw 030f8h, 030e8h, 030d8h, 030c7h, 030b7h, 030a7h, 03096h, 03086h
	dw 03076h, 03065h, 03055h, 03044h, 03034h, 03023h, 03013h, 03002h
	dw 02ff1h, 02fe1h, 02fd0h, 02fbfh, 02fafh, 02f9eh, 02f8dh, 02f7ch
	dw 02f6bh, 02f5ah, 02f49h, 02f38h, 02f28h, 02f16h, 02f05h, 02ef4h
	dw 02ee3h, 02ed2h, 02ec1h, 02eb0h, 02e9fh, 02e8dh, 02e7ch, 02e6bh
	dw 02e5ah, 02e48h, 02e37h, 02e25h, 02e14h, 02e03h, 02df1h, 02de0h
	dw 02dceh, 02dbch, 02dabh, 02d99h, 02d88h, 02d76h, 02d64h, 02d52h
	dw 02d41h, 02d2fh, 02d1dh, 02d0bh, 02cf9h, 02ce8h, 02cd6h, 02cc4h
	dw 02cb2h, 02ca0h, 02c8eh, 02c7ch, 02c6ah, 02c57h, 02c45h, 02c33h
	dw 02c21h, 02c0fh, 02bfch, 02beah, 02bd8h, 02bc6h, 02bb3h, 02ba1h
	dw 02b8eh, 02b7ch, 02b6ah, 02b57h, 02b45h, 02b32h, 02b20h, 02b0dh
	dw 02afah, 02ae8h, 02ad5h, 02ac2h, 02ab0h, 02a9dh, 02a8ah, 02a77h
	dw 02a65h, 02a52h, 02a3fh, 02a2ch, 02a19h, 02a06h, 029f3h, 029e0h
	dw 029cdh, 029bah, 029a7h, 02994h, 02981h, 0296eh, 0295ah, 02947h
	dw 02934h, 02921h, 0290eh, 028fah, 028e7h, 028d4h, 028c0h, 028adh
	dw 02899h, 02886h, 02872h, 0285fh, 0284bh, 02838h, 02824h, 02811h
	dw 027fdh, 027eah, 027d6h, 027c2h, 027afh, 0279bh, 02787h, 02773h
	dw 0275fh, 0274ch, 02738h, 02724h, 02710h, 026fch, 026e8h, 026d4h
	dw 026c0h, 026ach, 02698h, 02684h, 02670h, 0265ch, 02648h, 02634h
	dw 0261fh, 0260bh, 025f7h, 025e3h, 025cfh, 025bah, 025a6h, 02592h
	dw 0257dh, 02569h, 02554h, 02540h, 0252ch, 02517h, 02503h, 024eeh
	dw 024dah, 024c5h, 024b0h, 0249ch, 02487h, 02473h, 0245eh, 02449h
	dw 02434h, 02420h, 0240bh, 023f6h, 023e1h, 023cdh, 023b8h, 023a3h
	dw 0238eh, 02379h, 02364h, 0234fh, 0233ah, 02325h, 02310h, 022fbh
	dw 022e6h, 022d1h, 022bch, 022a7h, 02292h, 0227dh, 02267h, 02252h
	dw 0223dh, 02228h, 02212h, 021fdh, 021e8h, 021d2h, 021bdh, 021a8h
	dw 02192h, 0217dh, 02168h, 02152h, 0213dh, 02127h, 02112h, 020fch
	dw 020e7h, 020d1h, 020bbh, 020a6h, 02090h, 0207bh, 02065h, 0204fh
	dw 02039h, 02024h, 0200eh, 01ff8h, 01fe2h, 01fcdh, 01fb7h, 01fa1h
	dw 01f8bh, 01f75h, 01f5fh, 01f49h, 01f34h, 01f1eh, 01f08h, 01ef2h
	dw 01edch, 01ec6h, 01eb0h, 01e99h, 01e83h, 01e6dh, 01e57h, 01e41h
	dw 01e2bh, 01e15h, 01dfeh, 01de8h, 01dd2h, 01dbch, 01da6h, 01d8fh
	dw 01d79h, 01d63h, 01d4ch, 01d36h, 01d20h, 01d09h, 01cf3h, 01cdch
	dw 01cc6h, 01cafh, 01c99h, 01c83h, 01c6ch, 01c55h, 01c3fh, 01c28h
	dw 01c12h, 01bfbh, 01be5h, 01bceh, 01bb7h, 01ba1h, 01b8ah, 01b73h
	dw 01b5dh, 01b46h, 01b2fh, 01b18h, 01b02h, 01aebh, 01ad4h, 01abdh
	dw 01aa6h, 01a8fh, 01a79h, 01a62h, 01a4bh, 01a34h, 01a1dh, 01a06h
	dw 019efh, 019d8h, 019c1h, 019aah, 01993h, 0197ch, 01965h, 0194eh
	dw 01937h, 01920h, 01908h, 018f1h, 018dah, 018c3h, 018ach, 01895h
	dw 0187dh, 01866h, 0184fh, 01838h, 01820h, 01809h, 017f2h, 017dah
	dw 017c3h, 017ach, 01794h, 0177dh, 01766h, 0174eh, 01737h, 0171fh
	dw 01708h, 016f1h, 016d9h, 016c2h, 016aah, 01693h, 0167bh, 01664h
	dw 0164ch, 01634h, 0161dh, 01605h, 015eeh, 015d6h, 015beh, 015a7h
	dw 0158fh, 01577h, 01560h, 01548h, 01530h, 01519h, 01501h, 014e9h
	dw 014d1h, 014bah, 014a2h, 0148ah, 01472h, 0145ah, 01443h, 0142bh
	dw 01413h, 013fbh, 013e3h, 013cbh, 013b3h, 0139bh, 01383h, 0136ch
	dw 01354h, 0133ch, 01324h, 0130ch, 012f4h, 012dch, 012c4h, 012ach
	dw 01294h, 0127bh, 01263h, 0124bh, 01233h, 0121bh, 01203h, 011ebh
	dw 011d3h, 011bbh, 011a2h, 0118ah, 01172h, 0115ah, 01142h, 0112ah
	dw 01111h, 010f9h, 010e1h, 010c9h, 010b0h, 01098h, 01080h, 01068h
	dw 0104fh, 01037h, 0101fh, 01006h, 00feeh, 00fd6h, 00fbdh, 00fa5h
	dw 00f8ch, 00f74h, 00f5ch, 00f43h, 00f2bh, 00f12h, 00efah, 00ee2h
	dw 00ec9h, 00eb1h, 00e98h, 00e80h, 00e67h, 00e4fh, 00e36h, 00e1eh
	dw 00e05h, 00dedh, 00dd4h, 00dbch, 00da3h, 00d8bh, 00d72h, 00d59h
	dw 00d41h, 00d28h, 00d10h, 00cf7h, 00cdeh, 00cc6h, 00cadh, 00c95h
	dw 00c7ch, 00c63h, 00c4bh, 00c32h, 00c19h, 00c01h, 00be8h, 00bcfh
	dw 00bb6h, 00b9eh, 00b85h, 00b6ch, 00b54h, 00b3bh, 00b22h, 00b09h
	dw 00af1h, 00ad8h, 00abfh, 00aa6h, 00a8dh, 00a75h, 00a5ch, 00a43h
	dw 00a2ah, 00a11h, 009f9h, 009e0h, 009c7h, 009aeh, 00995h, 0097ch
	dw 00964h, 0094bh, 00932h, 00919h, 00900h, 008e7h, 008ceh, 008b5h
	dw 0089ch, 00884h, 0086bh, 00852h, 00839h, 00820h, 00807h, 007eeh
	dw 007d5h, 007bch, 007a3h, 0078ah, 00771h, 00758h, 0073fh, 00726h
	dw 0070dh, 006f4h, 006dbh, 006c2h, 006a9h, 00690h, 00677h, 0065eh
	dw 00645h, 0062ch, 00613h, 005fah, 005e1h, 005c8h, 005afh, 00596h
	dw 0057dh, 00564h, 0054bh, 00532h, 00519h, 00500h, 004e7h, 004ceh
	dw 004b5h, 0049ch, 00483h, 0046ah, 00451h, 00437h, 0041eh, 00405h
	dw 003ech, 003d3h, 003bah, 003a1h, 00388h, 0036fh, 00356h, 0033dh
	dw 00323h, 0030ah, 002f1h, 002d8h, 002bfh, 002a6h, 0028dh, 00274h
	dw 0025bh, 00241h, 00228h, 0020fh, 001f6h, 001ddh, 001c4h, 001abh
	dw 00192h, 00178h, 0015fh, 00146h, 0012dh, 00114h, 000fbh, 000e2h
	dw 000c9h, 000afh, 00096h, 0007dh, 00064h, 0004bh, 00032h, 00019h
	dw 00000h, 0ffe6h, 0ffcdh, 0ffb4h, 0ff9bh, 0ff82h, 0ff69h, 0ff50h
	dw 0ff36h, 0ff1dh, 0ff04h, 0feebh, 0fed2h, 0feb9h, 0fea0h, 0fe87h
	dw 0fe6dh, 0fe54h, 0fe3bh, 0fe22h, 0fe09h, 0fdf0h, 0fdd7h, 0fdbeh
	dw 0fda4h, 0fd8bh, 0fd72h, 0fd59h, 0fd40h, 0fd27h, 0fd0eh, 0fcf5h
	dw 0fcdch, 0fcc2h, 0fca9h, 0fc90h, 0fc77h, 0fc5eh, 0fc45h, 0fc2ch
	dw 0fc13h, 0fbfah, 0fbe1h, 0fbc8h, 0fbaeh, 0fb95h, 0fb7ch, 0fb63h
	dw 0fb4ah, 0fb31h, 0fb18h, 0faffh, 0fae6h, 0facdh, 0fab4h, 0fa9bh
	dw 0fa82h, 0fa69h, 0fa50h, 0fa37h, 0fa1eh, 0fa05h, 0f9ech, 0f9d3h
	dw 0f9bah, 0f9a1h, 0f988h, 0f96fh, 0f956h, 0f93dh, 0f924h, 0f90bh
	dw 0f8f2h, 0f8d9h, 0f8c0h, 0f8a7h, 0f88eh, 0f875h, 0f85ch, 0f843h
	dw 0f82ah, 0f811h, 0f7f8h, 0f7dfh, 0f7c6h, 0f7adh, 0f794h, 0f77bh
	dw 0f763h, 0f74ah, 0f731h, 0f718h, 0f6ffh, 0f6e6h, 0f6cdh, 0f6b4h
	dw 0f69bh, 0f683h, 0f66ah, 0f651h, 0f638h, 0f61fh, 0f606h, 0f5eeh
	dw 0f5d5h, 0f5bch, 0f5a3h, 0f58ah, 0f572h, 0f559h, 0f540h, 0f527h
	dw 0f50eh, 0f4f6h, 0f4ddh, 0f4c4h, 0f4abh, 0f493h, 0f47ah, 0f461h
	dw 0f449h, 0f430h, 0f417h, 0f3feh, 0f3e6h, 0f3cdh, 0f3b4h, 0f39ch
	dw 0f383h, 0f36ah, 0f352h, 0f339h, 0f321h, 0f308h, 0f2efh, 0f2d7h
	dw 0f2beh, 0f2a6h, 0f28dh, 0f274h, 0f25ch, 0f243h, 0f22bh, 0f212h
	dw 0f1fah, 0f1e1h, 0f1c9h, 0f1b0h, 0f198h, 0f17fh, 0f167h, 0f14eh
	dw 0f136h, 0f11dh, 0f105h, 0f0edh, 0f0d4h, 0f0bch, 0f0a3h, 0f08bh
	dw 0f073h, 0f05ah, 0f042h, 0f029h, 0f011h, 0eff9h, 0efe0h, 0efc8h
	dw 0efb0h, 0ef97h, 0ef7fh, 0ef67h, 0ef4fh, 0ef36h, 0ef1eh, 0ef06h
	dw 0eeeeh, 0eed5h, 0eebdh, 0eea5h, 0ee8dh, 0ee75h, 0ee5dh, 0ee44h
	dw 0ee2ch, 0ee14h, 0edfch, 0ede4h, 0edcch, 0edb4h, 0ed9ch, 0ed84h
	dw 0ed6bh, 0ed53h, 0ed3bh, 0ed23h, 0ed0bh, 0ecf3h, 0ecdbh, 0ecc3h
	dw 0ecabh, 0ec93h, 0ec7ch, 0ec64h, 0ec4ch, 0ec34h, 0ec1ch, 0ec04h
	dw 0ebech, 0ebd4h, 0ebbch, 0eba5h, 0eb8dh, 0eb75h, 0eb5dh, 0eb45h
	dw 0eb2eh, 0eb16h, 0eafeh, 0eae6h, 0eacfh, 0eab7h, 0ea9fh, 0ea88h
	dw 0ea70h, 0ea58h, 0ea41h, 0ea29h, 0ea11h, 0e9fah, 0e9e2h, 0e9cbh
	dw 0e9b3h, 0e99bh, 0e984h, 0e96ch, 0e955h, 0e93dh, 0e926h, 0e90eh
	dw 0e8f7h, 0e8e0h, 0e8c8h, 0e8b1h, 0e899h, 0e882h, 0e86bh, 0e853h
	dw 0e83ch, 0e825h, 0e80dh, 0e7f6h, 0e7dfh, 0e7c7h, 0e7b0h, 0e799h
	dw 0e782h, 0e76ah, 0e753h, 0e73ch, 0e725h, 0e70eh, 0e6f7h, 0e6dfh
	dw 0e6c8h, 0e6b1h, 0e69ah, 0e683h, 0e66ch, 0e655h, 0e63eh, 0e627h
	dw 0e610h, 0e5f9h, 0e5e2h, 0e5cbh, 0e5b4h, 0e59dh, 0e586h, 0e570h
	dw 0e559h, 0e542h, 0e52bh, 0e514h, 0e4fdh, 0e4e7h, 0e4d0h, 0e4b9h
	dw 0e4a2h, 0e48ch, 0e475h, 0e45eh, 0e448h, 0e431h, 0e41ah, 0e404h
	dw 0e3edh, 0e3d7h, 0e3c0h, 0e3aah, 0e393h, 0e37ch, 0e366h, 0e350h
	dw 0e339h, 0e323h, 0e30ch, 0e2f6h, 0e2dfh, 0e2c9h, 0e2b3h, 0e29ch
	dw 0e286h, 0e270h, 0e259h, 0e243h, 0e22dh, 0e217h, 0e201h, 0e1eah
	dw 0e1d4h, 0e1beh, 0e1a8h, 0e192h, 0e17ch, 0e166h, 0e14fh, 0e139h
	dw 0e123h, 0e10dh, 0e0f7h, 0e0e1h, 0e0cbh, 0e0b6h, 0e0a0h, 0e08ah
	dw 0e074h, 0e05eh, 0e048h, 0e032h, 0e01dh, 0e007h, 0dff1h, 0dfdbh
	dw 0dfc6h, 0dfb0h, 0df9ah, 0df84h, 0df6fh, 0df59h, 0df44h, 0df2eh
	dw 0df18h, 0df03h, 0deedh, 0ded8h, 0dec2h, 0deadh, 0de97h, 0de82h
	dw 0de6dh, 0de57h, 0de42h, 0de2dh, 0de17h, 0de02h, 0ddedh, 0ddd7h
	dw 0ddc2h, 0ddadh, 0dd98h, 0dd82h, 0dd6dh, 0dd58h, 0dd43h, 0dd2eh
	dw 0dd19h, 0dd04h, 0dcefh, 0dcdah, 0dcc5h, 0dcb0h, 0dc9bh, 0dc86h
	dw 0dc71h, 0dc5ch, 0dc47h, 0dc32h, 0dc1eh, 0dc09h, 0dbf4h, 0dbdfh
	dw 0dbcbh, 0dbb6h, 0dba1h, 0db8ch, 0db78h, 0db63h, 0db4fh, 0db3ah
	dw 0db25h, 0db11h, 0dafch, 0dae8h, 0dad3h, 0dabfh, 0daabh, 0da96h
	dw 0da82h, 0da6dh, 0da59h, 0da45h, 0da30h, 0da1ch, 0da08h, 0d9f4h
	dw 0d9e0h, 0d9cbh, 0d9b7h, 0d9a3h, 0d98fh, 0d97bh, 0d967h, 0d953h
	dw 0d93fh, 0d92bh, 0d917h, 0d903h, 0d8efh, 0d8dbh, 0d8c7h, 0d8b3h
	dw 0d8a0h, 0d88ch, 0d878h, 0d864h, 0d850h, 0d83dh, 0d829h, 0d815h
	dw 0d802h, 0d7eeh, 0d7dbh, 0d7c7h, 0d7b4h, 0d7a0h, 0d78dh, 0d779h
	dw 0d766h, 0d752h, 0d73fh, 0d72bh, 0d718h, 0d705h, 0d6f1h, 0d6deh
	dw 0d6cbh, 0d6b8h, 0d6a5h, 0d691h, 0d67eh, 0d66bh, 0d658h, 0d645h
	dw 0d632h, 0d61fh, 0d60ch, 0d5f9h, 0d5e6h, 0d5d3h, 0d5c0h, 0d5adh
	dw 0d59ah, 0d588h, 0d575h, 0d562h, 0d54fh, 0d53dh, 0d52ah, 0d517h
	dw 0d505h, 0d4f2h, 0d4dfh, 0d4cdh, 0d4bah, 0d4a8h, 0d495h, 0d483h
	dw 0d471h, 0d45eh, 0d44ch, 0d439h, 0d427h, 0d415h, 0d403h, 0d3f0h
	dw 0d3deh, 0d3cch, 0d3bah, 0d3a8h, 0d395h, 0d383h, 0d371h, 0d35fh
	dw 0d34dh, 0d33bh, 0d329h, 0d317h, 0d306h, 0d2f4h, 0d2e2h, 0d2d0h
	dw 0d2beh, 0d2adh, 0d29bh, 0d289h, 0d277h, 0d266h, 0d254h, 0d243h
	dw 0d231h, 0d21fh, 0d20eh, 0d1fch, 0d1ebh, 0d1dah, 0d1c8h, 0d1b7h
	dw 0d1a5h, 0d194h, 0d183h, 0d172h, 0d160h, 0d14fh, 0d13eh, 0d12dh
	dw 0d11ch, 0d10bh, 0d0fah, 0d0e9h, 0d0d7h, 0d0c7h, 0d0b6h, 0d0a5h
	dw 0d094h, 0d083h, 0d072h, 0d061h, 0d050h, 0d040h, 0d02fh, 0d01eh
	dw 0d00eh, 0cffdh, 0cfech, 0cfdch, 0cfcbh, 0cfbbh, 0cfaah, 0cf9ah
	dw 0cf89h, 0cf79h, 0cf69h, 0cf58h, 0cf48h, 0cf38h, 0cf27h, 0cf17h
	dw 0cf07h, 0cef7h, 0cee7h, 0ced7h, 0cec7h, 0ceb6h, 0cea6h, 0ce96h
	dw 0ce86h, 0ce77h, 0ce67h, 0ce57h, 0ce47h, 0ce37h, 0ce27h, 0ce18h
	dw 0ce08h, 0cdf8h, 0cde9h, 0cdd9h, 0cdc9h, 0cdbah, 0cdaah, 0cd9bh
	dw 0cd8bh, 0cd7ch, 0cd6ch, 0cd5dh, 0cd4eh, 0cd3eh, 0cd2fh, 0cd20h
	dw 0cd11h, 0cd01h, 0ccf2h, 0cce3h, 0ccd4h, 0ccc5h, 0ccb6h, 0cca7h
	dw 0cc98h, 0cc89h, 0cc7ah, 0cc6bh, 0cc5ch, 0cc4dh, 0cc3eh, 0cc30h
	dw 0cc21h, 0cc12h, 0cc04h, 0cbf5h, 0cbe6h, 0cbd8h, 0cbc9h, 0cbbbh
	dw 0cbach, 0cb9eh, 0cb8fh, 0cb81h, 0cb73h, 0cb64h, 0cb56h, 0cb48h
	dw 0cb39h, 0cb2bh, 0cb1dh, 0cb0fh, 0cb01h, 0caf3h, 0cae5h, 0cad7h
	dw 0cac9h, 0cabbh, 0caadh, 0ca9fh, 0ca91h, 0ca83h, 0ca76h, 0ca68h
	dw 0ca5ah, 0ca4ch, 0ca3fh, 0ca31h, 0ca23h, 0ca16h, 0ca08h, 0c9fbh
	dw 0c9edh, 0c9e0h, 0c9d3h, 0c9c5h, 0c9b8h, 0c9abh, 0c99dh, 0c990h
	dw 0c983h, 0c976h, 0c969h, 0c95bh, 0c94eh, 0c941h, 0c934h, 0c927h
	dw 0c91ah, 0c90eh, 0c901h, 0c8f4h, 0c8e7h, 0c8dah, 0c8ceh, 0c8c1h
	dw 0c8b4h, 0c8a8h, 0c89bh, 0c88eh, 0c882h, 0c875h, 0c869h, 0c85ch
	dw 0c850h, 0c844h, 0c837h, 0c82bh, 0c81fh, 0c812h, 0c806h, 0c7fah
	dw 0c7eeh, 0c7e2h, 0c7d6h, 0c7cah, 0c7beh, 0c7b2h, 0c7a6h, 0c79ah
	dw 0c78eh, 0c782h, 0c776h, 0c76bh, 0c75fh, 0c753h, 0c748h, 0c73ch
	dw 0c730h, 0c725h, 0c719h, 0c70eh, 0c702h, 0c6f7h, 0c6ech, 0c6e0h
	dw 0c6d5h, 0c6cah, 0c6beh, 0c6b3h, 0c6a8h, 0c69dh, 0c692h, 0c687h
	dw 0c67ch, 0c671h, 0c666h, 0c65bh, 0c650h, 0c645h, 0c63ah, 0c62fh
	dw 0c625h, 0c61ah, 0c60fh, 0c604h, 0c5fah, 0c5efh, 0c5e5h, 0c5dah
	dw 0c5d0h, 0c5c5h, 0c5bbh, 0c5b0h, 0c5a6h, 0c59ch, 0c592h, 0c587h
	dw 0c57dh, 0c573h, 0c569h, 0c55fh, 0c555h, 0c54bh, 0c541h, 0c537h
	dw 0c52dh, 0c523h, 0c519h, 0c50fh, 0c505h, 0c4fch, 0c4f2h, 0c4e8h
	dw 0c4dfh, 0c4d5h, 0c4cbh, 0c4c2h, 0c4b8h, 0c4afh, 0c4a6h, 0c49ch
	dw 0c493h, 0c48ah, 0c480h, 0c477h, 0c46eh, 0c465h, 0c45ch, 0c452h
	dw 0c449h, 0c440h, 0c437h, 0c42eh, 0c425h, 0c41dh, 0c414h, 0c40bh
	dw 0c402h, 0c3f9h, 0c3f1h, 0c3e8h, 0c3dfh, 0c3d7h, 0c3ceh, 0c3c6h
	dw 0c3bdh, 0c3b5h, 0c3ach, 0c3a4h, 0c39ch, 0c393h, 0c38bh, 0c383h
	dw 0c37bh, 0c373h, 0c36ah, 0c362h, 0c35ah, 0c352h, 0c34ah, 0c342h
	dw 0c33ah, 0c333h, 0c32bh, 0c323h, 0c31bh, 0c313h, 0c30ch, 0c304h
	dw 0c2fdh, 0c2f5h, 0c2edh, 0c2e6h, 0c2deh, 0c2d7h, 0c2d0h, 0c2c8h
	dw 0c2c1h, 0c2bah, 0c2b2h, 0c2abh, 0c2a4h, 0c29dh, 0c296h, 0c28fh
	dw 0c288h, 0c281h, 0c27ah, 0c273h, 0c26ch, 0c265h, 0c25eh, 0c258h
	dw 0c251h, 0c24ah, 0c244h, 0c23dh, 0c236h, 0c230h, 0c229h, 0c223h
	dw 0c21dh, 0c216h, 0c210h, 0c20ah, 0c203h, 0c1fdh, 0c1f7h, 0c1f1h
	dw 0c1ebh, 0c1e4h, 0c1deh, 0c1d8h, 0c1d2h, 0c1cch, 0c1c7h, 0c1c1h
	dw 0c1bbh, 0c1b5h, 0c1afh, 0c1aah, 0c1a4h, 0c19eh, 0c199h, 0c193h
	dw 0c18eh, 0c188h, 0c183h, 0c17dh, 0c178h, 0c173h, 0c16dh, 0c168h
	dw 0c163h, 0c15eh, 0c158h, 0c153h, 0c14eh, 0c149h, 0c144h, 0c13fh
	dw 0c13ah, 0c135h, 0c131h, 0c12ch, 0c127h, 0c122h, 0c11eh, 0c119h
	dw 0c114h, 0c110h, 0c10bh, 0c107h, 0c102h, 0c0feh, 0c0f9h, 0c0f5h
	dw 0c0f1h, 0c0ech, 0c0e8h, 0c0e4h, 0c0e0h, 0c0dch, 0c0d8h, 0c0d4h
	dw 0c0d0h, 0c0cch, 0c0c8h, 0c0c4h, 0c0c0h, 0c0bch, 0c0b8h, 0c0b5h
	dw 0c0b1h, 0c0adh, 0c0aah, 0c0a6h, 0c0a2h, 0c09fh, 0c09bh, 0c098h
	dw 0c095h, 0c091h, 0c08eh, 0c08bh, 0c087h, 0c084h, 0c081h, 0c07eh
	dw 0c07bh, 0c078h, 0c075h, 0c072h, 0c06fh, 0c06ch, 0c069h, 0c066h
	dw 0c063h, 0c061h, 0c05eh, 0c05bh, 0c059h, 0c056h, 0c053h, 0c051h
	dw 0c04eh, 0c04ch, 0c04ah, 0c047h, 0c045h, 0c043h, 0c040h, 0c03eh
	dw 0c03ch, 0c03ah, 0c038h, 0c036h, 0c034h, 0c032h, 0c030h, 0c02eh
	dw 0c02ch, 0c02ah, 0c028h, 0c027h, 0c025h, 0c023h, 0c021h, 0c020h
	dw 0c01eh, 0c01dh, 0c01bh, 0c01ah, 0c018h, 0c017h, 0c016h, 0c014h
	dw 0c013h, 0c012h, 0c011h, 0c010h, 0c00fh, 0c00eh, 0c00dh, 0c00ch
	dw 0c00bh, 0c00ah, 0c009h, 0c008h, 0c007h, 0c006h, 0c006h, 0c005h
	dw 0c004h, 0c004h, 0c003h, 0c003h, 0c002h, 0c002h, 0c001h, 0c001h
	dw 0c001h, 0c000h, 0c000h, 0c000h, 0c000h, 0c000h, 0c000h, 0c000h
	dw 0c000h

; ============================================================================
; CROSS-SEGMENT DATA EXPORTS
; ----------------------------------------------------------------------------
; The actor-render code (ACTRENDR.C and friends) reads part of this state
; from outside the segment, through an ES far pointer (MOV ES,SEG _sym ;
; ES:[OFF _sym]). Each item it needs is exported as a `_`-prefixed PUBLIC,
; established with a `LABEL` directive placed immediately before the data
; definition it aliases (search `<-- export alias`); a LABEL emits no bytes.
;
; NB: `LABEL`, not `EQU` -- TASM 3.1 silently truncates the PUBLIC name of an
; EQU-to-data-label alias to 13 chars (`_g_dwActorCamX` -> `_g_dwActorCam`),
; which would collapse CamX/CamY/CamZ into one colliding symbol. A
; `<name> LABEL <size>` alias at the data offset keeps the full name. The
; publics are declared here; the labels live inline next to their data.
; ----------------------------------------------------------------------------
	public _g_abR3dState
	public _g_dwActorCamX
	public _g_dwActorCamZ
	public _g_dwActorCamY
	public _g_dwMeshBoundHalfExtent
	public _g_wActorProjScale
	public _g_mat3x3ViewRot
	public _g_viewportCenter
	public _g_nViewportCenterX
	public _g_nViewportCenterY
	public _g_bActorViewportClip
	public _g_bSkipFarEdgeCull
	public _g_nCurModelIdx
	public _g_nActorFarClipThreshold
	public _g_wMeshVertexPoolOff
	public _g_nMeshPartVertexCount
	public _g_bCurMeshLod
	public _g_mat3x3ActorRot
	public _g_nMeshOriginX
	public _g_wMeshScaleShift
	public _g_dwActorBoundExtent
	public _g_dwMeshVertexFarPtrCache
	public _g_lActorClampedCamZ
	public _g_lActorLodZ
	public _g_nMeshNormOriginX
	public _g_nMeshOriginY
	public _g_nMeshOriginZ
	public _g_bMeshRenormCount
	public _g_pCurActorPagedRec
	public _g_pCurMeshPartVisTable
	public _g_wMeshScaleResidual
	public _g_nMeshCamOriginX
	public _g_nMeshCamOriginY
	public _g_nMeshCamOriginZ
	public _g_lActorRelX
	public _g_lActorRelY
	public _g_nScreenShift
	public _g_camViewAngles
	public _g_camViewYaw
	public _g_camViewPitch
	public _g_pColorRemapTable


; ----------------------------------------------------------------------------
; PUBLICS for the split: the following CS-resident data items are read by the
; core (R3D.OBJ) and/or trig (R3DTRIG.OBJ) modules, which now live in separate
; OBJs of the same S233E_TEXT segment; these publics let the sibling code
; modules reference the state by name.
; ----------------------------------------------------------------------------
	public g_bCamSetupResetFlag
	public g_nMeshCamOriginX
	public g_nMeshCamOriginY
	public g_nMeshCamOriginZ
	public g_abLightingLut
	public g_abPolygonClipState
	public g_aPolyClipX
	public g_aPolyClipXHi
	public g_aPolyClipY
	public g_aPolyClipYHi
	public g_aPolyInX
	public g_aPolyInXHi
	public g_aPolyInY
	public g_aPolyInYHi
	public g_aVertexCamX
	public g_aVertexCamXHi
	public g_aVertexCamY
	public g_aVertexCamYHi
	public g_aVertexCamZ
	public g_aVertexCamZHi
	public g_aVertexScrX
	public g_aVertexScrXHi
	public g_aVertexScrY
	public g_aVertexScrYHi
	public g_bActorViewportClip
	public g_bCurMeshLod
	public g_bPolyNormalFlipped
	public g_bSkipFarEdgeCull
	public g_bScratchMatType
	public g_camCurWorldPos
	public g_camViewYaw
	public g_dwActorBoundExtent
	public g_dwActorCamX
	public g_dwActorCamY
	public g_dwActorCamZ
	public g_dwMeshBoundHalfExtent
	public g_dwMeshVertexFarPtrCache
	public g_lActorClampedCamZ
	public g_lActorLodZ
	public g_lActorRelX
	public g_lActorRelY
	public g_mat3x3TempOut
	public g_mat3x3ViewRot
	public g_matXIn
	public g_matXIn2
	public g_matXOut
	public g_matXOut32
	public g_matXOut32Hi
	public g_matYIn
	public g_matYIn2
	public g_matYOut
	public g_matYOut32
	public g_matYOut32Hi
	public g_matZIn
	public g_matZIn2
	public g_matZOut
	public g_matZOut32
	public g_matZOut32Hi
	public g_nMeshNormOriginX
	public g_nMeshOriginY
	public g_nMeshOriginZ
	public g_nMeshPartVertexCount
	public g_nMeshPolyVertexCount
	public g_nScreenShift
	public g_nViewPlaneDist
	public g_nViewportCenterX
	public g_nViewportCenterY
	public g_pColorRemapTable
	public g_pCurActorPagedRec
	public g_polygon_vertices
	public g_vec3LightDirObj
	public g_mat3x3ScratchRot
	public g_pFaceMaterialTable
	public g_bMeshRenormCount
	public g_wMeshScaleResidual
	public g_wMeshScaleShift
	public g_wMeshVertexCacheSeg
	public g_wMeshVertexPoolOff

S233E_TEXT	ends

	end
