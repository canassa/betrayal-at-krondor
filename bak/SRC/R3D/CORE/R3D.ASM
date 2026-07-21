; ============================================================================
; R3D.ASM  --  3-D renderer core
;
; Fixed-point 3-D pipeline for the world view. Takes a visible entity's
; shape (polygon faces over a shared vertex pool), places it in camera
; space, and draws it: the entity's orientation angles become a 3x3
; rotation matrix, composed with the camera view rotation; vertices are
; rotated, translated and perspective-projected; faces are back-face
; culled, clipped against the view plane and the viewport, shaded by the
; directional light, and handed to the polygon rasterizer.
;
; Numbers: rotations are Q14 fixed point (4000h = 1.0); angles are 16-bit
; binary (a full turn = 10000h); all trig is by table (R3DTRIG.ASM).
; Perspective and clip interpolation go through r3d_ldiv_helper, a long
; divide that preserves fractional precision.
;
; Detail levels: a shape carries up to four levels of detail. LOD 0 draws
; through r3d_mesh_part_polygons (16-bit fast path, near-plane clipping,
; textured floor special case), LODs 1-2 through r3d_mesh_polygons
; (32-bit precision), LOD 3 through r3d_mesh_part_polygons_lod3 (16-bit,
; no near clip). The pick is g_bCurMeshLod (see ACTRENDR.C).
;
; Lighting: the world light direction is set once at startup
; (r3d_light_set_direction, called from ts_init);
; r3d_compose_actor_camera_matrix rotates it into each actor's object
; space (g_vec3LightDirObj); the shade path dots face normals against it
; and picks the fill color from the material's row of the lighting ramp
; (g_abLightingLut).
;
; The segment: S233E_TEXT is built from four source files, linked in this
; order (KRONDOR.RSP):
;     R3D.ASM      code: transforms, producers, clip/shade/submit
;     R3DTRIG.ASM  code: sin/cos/asin/atan2 table trig
;     R3DDATA.ASM  data: renderer state + lookup tables
;     R3DDOT3.ASM  code: dot-product leaf helpers
;
; Conventions needed to read this code:
;   1. Far entry points end in RETF, stack args from [bp+6] (frameless
;      readers index from SP instead). Same-segment calls push CS then use
;      a near call. Internal near helpers (plain RET) pass arguments in
;      registers -- each function's Entry/Exit/Trashes banner is the
;      contract.
;   2. The renderer keeps its state in its own segment, not in DGROUP.
;      The producer entry points set DS=CS on entry and every near helper
;      inherits it, so a plain '[label]' operand reads renderer state
;      (R3DDATA.ASM). Lookup tables are read with an explicit cs:
;      override; r3d_camera_setup_view addresses a few scalars through
;      es: with ES=CS.
;   3. The few game globals that do live in DGROUP are always accessed
;      with an explicit ss: override (medium model, SS=DGROUP): the
;      g_graphics_context clip bounds and fill state, g_game_mode,
;      g_bTexturedPolyEnabled, g_nPolygonClipVertexCount.
;   4. Cross-segment calls: sky_polygon_draw_dispatch (the rasterizer)
;      and worldrender_textured_quad_lod (textured quads); everything
;      else is segment-local.
; ============================================================================

.286

; ----------------------------------------------------------------------------
; Types and constants
; ----------------------------------------------------------------------------

; FACE -- the 8-byte mesh polygon record (ES:DI points at one).
;   +0 flags byte; low 2 bits = clip/skip kind, bit5 (0x20) = simple-mesh face,
;      bit7 (0x80) = fill-enabled.
;   +1/+2 = day (renderState!=0) outline/fill color pair.
;   +3/+4 = night (renderState==0) outline/fill color pair.
;   +5 = normal-vertex index (into the per-mesh normal-vector table).
;   +6 = near offset of the vertex-index list (word).
FACE		struc
	fFlags		db	?	; +0 flags
	fDayOutline	db	?	; +1 renderState!=0 outline color
	fDayFill	db	?	; +2 renderState!=0 fill color
	fNightOutline	db	?	; +3 renderState==0 outline color
	fNightFill	db	?	; +4 renderState==0 fill color
	fNrmVert	db	?	; +5 normal-vertex index
	fVertList	dw	?	; +6 vertex-index-list near offset
FACE		ends

; MESHHDR -- the 4-byte poly-list header a mesh part points at (ES:DI on entry,
;   at poly-list block+2). The FACE array follows at hFirstPoly.
;   +0 = polygon count (drives the face loop counter).
;   +2 = near offset of the FACE array.
MESHHDR		struc
	hPolyCount	dw	?	; +0 polygon count
	hFirstPoly	dw	?	; +2 FACE-array near offset
MESHHDR		ends

; MAT3 -- the 3x3 fixed-point rotation matrix (mirrors the C Mat3x3):
;   short pM[9] at +0..+16 (Q14, row-major), then a classifier byte bType at +18
;   (0=identity, 1=Z-rotation only, 3=full). The nine element slots stay numeric
;   at their sites (an array, not named fields); only the classifier byte gets a
;   name here.
MAT3		struc
	mM		dw	9 dup(?)	; +0..+16 pM[9]
	mType		db	?		; +18 classifier (MAT3T_*)
MAT3		ends

; VROW -- one 6-byte row of a mesh vertex / normal-vector table (three Q-format
; shorts x,y,z). Row base is computed as index*6 + tableBase, then the three
; components are read via ES:[BX].vX / .vY / .vZ.
VROW		struc
	vX		dw	?	; +0
	vY		dw	?	; +2
	vZ		dw	?	; +4
VROW		ends

; Q14 fixed-point unity (1.0 == 0x4000) -- the matrix-diagonal value.
Q14_ONE		equ 4000h
; Binary angle for 90 degrees (0x4000 in the 0x10000-per-turn representation);
; same bit pattern as Q14_ONE but a distinct meaning (gimbal-lock threshold).
ANG_90DEG	equ 4000h

; MAT3.mType classifier values.
MAT3T_IDENTITY	equ 0		; identity (all Euler angles zero)
MAT3T_ZROT	equ 1		; Z-rotation only
MAT3T_FULL	equ 3		; full 3-axis rotation

; g_abPolygonClipState[] per-vertex near-Z clip cache states.
CLIPST_UNTOUCHED	equ 0	; not yet transformed this part (CLIP_UNTOUCHED)
CLIPST_PENDING		equ 1	; transform in progress (CLIP_PENDING)
CLIPST_PROJECTED	equ 2	; projected & on-screen (CLIP_ONSCREEN)
CLIPST_BEHIND		equ 3	; behind near plane, needs clip (CLIP_NEARCLIP)

; FACE.fFlags bit: this face belongs to a "simple mesh" (drives the back-face
; flip test / textured-quad path).
MESH_FLAG_SIMPLE	equ 20h

; Size of one FACE (mesh polygon record); the poly loop advances by this.
FACE_SIZE	equ 8

; ----------------------------------------------------------------------------
; Idiom macros
; ----------------------------------------------------------------------------

; Q14NORM -- renormalize a 32-bit product in DX:AX to Q14: shift the 32-bit
; value left by 2 (keep the high word) == (a*b) >> 14. This is the FMUL core.
; Expands to:  shl AX,1h / rcl DX,1h / shl AX,1h / rcl DX,1h .
Q14NORM		macro
	shl AX,1h
	rcl DX,1h
	shl AX,1h
	rcl DX,1h
	endm

; Q14NORM48 -- 48-bit Q14 renormalize: the DX:AX:BP 48-bit product is shifted
; left by 2 (keep high 32 bits in DX:AX) == (a*b) >> 14 for the wide-accumulator
; matrix-transform path. Expands to the doubled 3-word shift:
;   shl BP,1h / rcl AX,1h / rcl DX,1h  x2
Q14NORM48	macro
	shl BP,1h
	rcl AX,1h
	rcl DX,1h
	shl BP,1h
	rcl AX,1h
	rcl DX,1h
	endm

; Q14NORM48C -- as Q14NORM48 but the 48-bit value is DX:AX:CX (low word in CX).
; Used to renormalize the r3d_dot3_coeff16_vec32 result to Q14. Expands
; to the doubled 3-word shift:
;   shl CX,1h / rcl AX,1h / rcl DX,1h  x2
Q14NORM48C	macro
	shl CX,1h
	rcl AX,1h
	rcl DX,1h
	shl CX,1h
	rcl AX,1h
	rcl DX,1h
	endm

; MULSEED matElem,vecComp -- seed a 32-bit multiply-accumulate: load the Q14
; matrix element (matElem, a [BX+n] operand) and the vector component (vecComp,
; a [SI+n] operand), signed 16x16->32 multiply, and place the product in the
; CX:BP accumulator. This is the first FMUL term of a matrix row dot-product.
; Expands to:
;   mov AX,word ptr matElem / mov DX,AX / mov AX,word ptr vecComp / imul DX /
;   mov CX,AX / mov BP,DX
MULSEED		macro matElem, vecComp
	mov AX, word ptr matElem
	mov DX,AX
	mov AX, word ptr vecComp
	imul DX
	mov CX,AX
	mov BP,DX
	endm

; MULACC matElem,vecComp -- accumulate one more FMUL term: signed 16x16->32 of
; matElem*vecComp, then add the running CX:BP accumulator, leaving the sum in
; DX:AX. Expands to:
;   mov AX,word ptr matElem / mov DX,AX / mov AX,word ptr vecComp / imul DX /
;   add AX,CX / adc DX,BP
MULACC		macro matElem, vecComp
	mov AX, word ptr matElem
	mov DX,AX
	mov AX, word ptr vecComp
	imul DX
	add AX,CX
	adc DX,BP
	endm

; MULACC2 matElem,vecComp -- like MULACC but accumulate the FMUL term into the
; CX:BP accumulator (used for the middle terms of a 3-term row dot-product that
; keeps summing in CX:BP before the final MULACC lands the total in DX:AX).
; Expands to:
;   mov AX,word ptr matElem / mov DX,AX / mov AX,word ptr vecComp / imul DX /
;   add CX,AX / adc BP,DX
MULACC2		macro matElem, vecComp
	mov AX, word ptr matElem
	mov DX,AX
	mov AX, word ptr vecComp
	imul DX
	add CX,AX
	adc BP,DX
	endm

; VROWADDR -- compute the byte address of vertex/normal row index (in BX) within
; a VROW table whose base is in BP: BX = index*6 + BP  (6 = sizeof VROW), via the
; (idx + idx>>1)*2 = idx*3*2 factoring. Leaves the row base in BX for a following
; ES:[BX].vX/.vY/.vZ read. Expands to:
;   mov AX,BX / shr AX,1h / add BX,AX / shl BX,1h / add BX,BP
VROWADDR	macro
	mov AX,BX
	shr AX,1h
	add BX,AX
	shl BX,1h
	add BX,BP
	endm

; BACKFACEDOT -- compute the signed backface dot for the current face: pass the
; face's mesh-normal-vertex byte (ES:[SI]) in AH and the face's fNrmVert index
; (ES:[DI].fNrmVert) in AL to _r3d_backface_dot_indexed, then compare the DX:AX
; result's high word against 0 so the caller can branch on the sign (jl = facing
; away). Expands to:
;   mov AH,ES:byte ptr [SI] / mov AL,ES:byte ptr [DI].fNrmVert /
;   call _r3d_backface_dot_indexed / cmp DX,0h
BACKFACEDOT	macro
	mov AH, ES:byte ptr [SI]
	mov AL, ES:byte ptr [DI].fNrmVert
	call _r3d_backface_dot_indexed
	cmp DX,0h
	endm

; COPYVTX2IN -- copy vertex SI's projected 32-bit screen X and Y from the vertex
; table (g_aVertexScrX/Y + Hi, indexed by SI) into the polygon-input array
; (g_aPolyInX/Y + Hi, indexed by DI), one word at a time through AX. Expands
; to the eight-move X-lo/X-hi/Y-lo/Y-hi copy:
;   mov AX,[SI+g_aVertexScrX]  / mov [DI+g_aPolyInX],AX
;   mov AX,[SI+g_aVertexScrXHi]/ mov [DI+g_aPolyInXHi],AX
;   mov AX,[SI+g_aVertexScrY]  / mov [DI+g_aPolyInY],AX
;   mov AX,[SI+g_aVertexScrYHi]/ mov [DI+g_aPolyInYHi],AX
COPYVTX2IN	macro
	mov AX, word ptr [SI+g_aVertexScrX]
	mov word ptr [DI+g_aPolyInX], AX
	mov AX, word ptr [SI+g_aVertexScrXHi]
	mov word ptr [DI+g_aPolyInXHi], AX
	mov AX, word ptr [SI+g_aVertexScrY]
	mov word ptr [DI+g_aPolyInY], AX
	mov AX, word ptr [SI+g_aVertexScrYHi]
	mov word ptr [DI+g_aPolyInYHi], AX
	endm

; NEG32 hi,lo -- two's-complement negate of the 32-bit value in the hi:lo
; register pair (high-word-first encoding). Expands to:
;   neg hi / neg lo / sbb hi,0h
; Sites use DX:AX (NEG32 DX,AX) and BX:DX (NEG32 BX,DX).
NEG32		macro hi, lo
	neg hi
	neg lo
	sbb hi,0h
	endm

; NEG32ADC lo,hi -- two's-complement negate of the 32-bit value in the hi:lo
; register pair (low-word-first encoding, the form bcc emits for the abs of a
; divide operand). Expands to:
;   neg lo / adc hi,0h / neg hi
; Sites use AX/DX (NEG32ADC AX,DX) and BX/CX (NEG32ADC BX,CX).
NEG32ADC	macro lo, hi
	neg lo
	adc hi,0h
	neg hi
	endm

; COS -- r3d_cos() fold + Q14 cosine-table read. Takes the angle already in AX,
; produces g_awCosTable[(angle>>4) folded into first half-period] in AX (BX = idx*2).
; Expands to:
;   shr AX,1h x4 / test AX,800h / jz L / neg AX / add AX,1000h / L: /
;   mov BX,AX / shl BX,1h / mov AX,word ptr CS:[BX+g_awCosTable]
; The 0c000h sine bias (HCOS phase shift) stays as an 'add AX,0c000h' BEFORE the
; call at the sites that need it. LOCAL gives the internal jz target a unique
; name per expansion (label names emit no bytes).
COS		macro
	local skip
	shr AX,1h
	shr AX,1h
	shr AX,1h
	shr AX,1h
	test AX, 800h
	jz skip
	neg AX
	add AX, 1000h		; idx = 1000h - idx (half-period fold)
skip:
	mov BX,AX
	shl BX,1h
	mov AX,word ptr CS:[BX+g_awCosTable]
	endm

; LD32 base -- load a 32-bit lo/hi split-array element into DX:AX, indexing with
; SI (byte offset). The paired array stores the low words at 'base' and the high
; words at 'base'&Hi (the split-precision vertex/poly coordinate tables).
; Expands to:
;   mov AX, word ptr [SI+base] / mov DX, word ptr [SI+baseHi]
LD32		macro base
	mov AX, word ptr [SI+base]
	mov DX, word ptr [SI+base&Hi]
	endm

; ST32 idx,base -- store DX:AX into a 32-bit lo/hi split-array element, indexing
; with idx (BX or DI). Expands to:
;   mov word ptr [idx+base], AX / mov word ptr [idx+baseHi], DX
ST32		macro idx, base
	mov word ptr [idx+base], AX
	mov word ptr [idx+base&Hi], DX
	endm

; SUB32 base -- subtract a 32-bit lo/hi split-array element (DS:[BP+base], the
; edge/clip endpoint operand) from DX:AX. Expands to:
;   sub AX, DS:word ptr [BP+base] / sbb DX, DS:word ptr [BP+baseHi]
SUB32		macro base
	sub AX, DS:word ptr [BP+base]
	sbb DX, DS:word ptr [BP+base&Hi]
	endm

; ADD32 base -- add a 32-bit lo/hi split-array element (DS:[BP+base]) into DX:AX.
; Expands to:
;   add AX, DS:word ptr [BP+base] / adc DX, DS:word ptr [BP+baseHi]
ADD32		macro base
	add AX, DS:word ptr [BP+base]
	adc DX, DS:word ptr [BP+base&Hi]
	endm

	extrn _sky_polygon_draw_dispatch:far
	extrn _worldrender_textured_quad_lod:far

; Trailing code island split into R3DDOT3.ASM (same S233E_TEXT segment, linked
; after this module's data block). The core's near call/jmp sites reference it.
	extrn _r3d_dot3_long:near

; Trig lookup cluster split into R3DTRIG.ASM (same S233E_TEXT segment, linked
; between this module's code and its data block). r3d_matrix_to_euler calls two
; of its functions via push-CS + near call.
	extrn _r3d_tbl_asin:near
	extrn _r3d_tbl_atan2:near

; Renderer state (R3DDATA.ASM, same S233E_TEXT segment). Every data item this
; module reads is imported here; types match the defining directives.
	extrn g_bCamSetupResetFlag:byte
	extrn g_nMeshCamOriginX:word
	extrn g_nMeshCamOriginY:word
	extrn g_nMeshCamOriginZ:word
	extrn g_abLightingLut:word
	extrn g_abPolygonClipState:byte
	extrn g_aPolyClipX:word
	extrn g_aPolyClipXHi:word
	extrn g_aPolyClipY:word
	extrn g_aPolyClipYHi:word
	extrn g_aPolyInX:word
	extrn g_aPolyInXHi:word
	extrn g_aPolyInY:word
	extrn g_aPolyInYHi:word
	extrn g_aVertexCamX:word
	extrn g_aVertexCamXHi:word
	extrn g_aVertexCamY:word
	extrn g_aVertexCamYHi:word
	extrn g_aVertexCamZ:word
	extrn g_aVertexCamZHi:word
	extrn g_aVertexScrX:word
	extrn g_aVertexScrXHi:word
	extrn g_aVertexScrY:word
	extrn g_aVertexScrYHi:word
	extrn g_awCosTable:word
	extrn g_bActorViewportClip:byte
	extrn g_bCurMeshLod:byte
	extrn g_bPolyNormalFlipped:byte
	extrn g_bSkipFarEdgeCull:byte
	extrn g_bScratchMatType:byte
	extrn g_camCurWorldPos:word
	extrn g_camViewYaw:word
	extrn g_dwActorBoundExtent:word
	extrn _g_dwActorCamX:dword
	extrn g_dwActorCamX:word
	extrn g_dwActorCamY:word
	extrn g_dwActorCamZ:word
	extrn g_dwMeshBoundHalfExtent:word
	extrn g_dwMeshVertexFarPtrCache:word
	extrn g_lActorClampedCamZ:word
	extrn g_lActorLodZ:word
	extrn _g_lActorRelX:dword
	extrn g_lActorRelX:word
	extrn g_lActorRelY:word
	extrn g_mat3x3ActorRot:word
	extrn g_mat3x3TempOut:byte
	extrn _g_mat3x3ViewRot:byte
	extrn g_mat3x3ViewRot:byte
	extrn g_matXIn:word
	extrn g_matXIn2:word
	extrn g_matXOut:word
	extrn g_matXOut32:word
	extrn g_matXOut32Hi:word
	extrn g_matYIn:word
	extrn g_matYIn2:word
	extrn g_matYOut:word
	extrn g_matYOut32:word
	extrn g_matYOut32Hi:word
	extrn g_matZIn:word
	extrn g_matZIn2:word
	extrn g_matZOut:word
	extrn g_matZOut32:word
	extrn g_matZOut32Hi:word
	extrn _g_nActorFarClipThreshold:word
	extrn g_nMeshNormOriginX:word
	extrn g_nMeshOriginX:word
	extrn g_nMeshOriginY:word
	extrn g_nMeshOriginZ:word
	extrn g_nMeshPartVertexCount:word
	extrn g_nMeshPolyVertexCount:word
	extrn g_nScreenShift:byte
	extrn g_nViewPlaneDist:word
	extrn g_nViewportCenterX:word
	extrn g_nViewportCenterY:word
	extrn g_pColorRemapTable:word
	extrn g_pCurActorPagedRec:dword
	extrn g_polygon_vertices:word
	extrn g_vec3LightDirObj:word
	extrn g_mat3x3ScratchRot:word
	extrn g_pFaceMaterialTable:word
	extrn g_bMeshRenormCount:word
	extrn g_wMeshScaleResidual:word
	extrn g_wMeshScaleShift:word
	extrn g_wMeshVertexCacheSeg:word
	extrn g_wMeshVertexPoolOff:word

; Game globals in DGROUP, always accessed with an explicit SS: override
; (medium model, SS = DGROUP; the renderer's DS points at its own segment).
	extrn _g_game_mode:word                 ; DGROUP+0x524d
	extrn _g_bTexturedPolyEnabled:word      ; DGROUP+0x09b2
	; In-span graphics-context fields (structs.md §36) via gfxctx.inc: g_clip_*,
	; g_gfx_fill_enabled/color, g_gfx_outline_color, g_bGfxRenderStateFlag,
	; g_nPolygonClipVertexCount. Referenced below as ss:[_g_*] (SS=DGROUP); the
	; EQU resolves them as SS-relative offsets into _g_graphics_context.
	include gfxctx.inc

; DGROUP must be declared for the `offset DGROUP:_g_graphics_context.<field>`
; loads below (group-frame FIXUPP); the empty _DATA/_BSS pair is the standard
; medium-model declaration.
_DATA	segment word public 'DATA'
_DATA	ends
; Standard empty medium-model pair.
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S233E_TEXT	segment word public use16 'CODE'
	assume cs:S233E_TEXT, ds:S233E_TEXT
	locals			; enable @@-prefixed local labels (scoped between
				; the surrounding non-local labels, i.e. per public
				; _name proc). Label names emit no bytes.
; SEGMENT REGISTER NOTE:
; assume cs:S233E_TEXT enables correct CS-relative near calls/jumps and lets the
; in-segment data labels resolve as offsets within this segment.
; assume ds:S233E_TEXT models the renderer's runtime DS=CS inheritance: the three
; top-level producers do 'push ds; mov ax,cs; mov ds,ax' and every near helper
; runs with DS=CS, so a bare '[_label]' / 'ds:[_label]' access to in-segment data
; emits no segment-override prefix. Without this assume, TASM injects a spurious
; '2E:' (CS) override. Explicit overrides are used where needed: the 'cs:[bx +
; _table]' lookup reads (kept 'cs:'), the 'es:[_label]' CS-resident writes done
; while ES=CS in r3d_camera_setup_view (kept 'es:', 26h prefix), and the
; genuine-DGROUP 'ss:[_g_*]' accesses (36h prefix). CS-resident data is addressed
; by LABEL; genuine DGROUP via the SS-override symbols above.

; ============================================================================
; _r3d_setup_actor_in_camera_space
;
; Copies a visible actor's world coords/payload into the renderer state, converts them to
; camera-relative space, applies the view matrix, and floor-clamps the camera-space Z depth.
;
; C equivalent:
;   void far r3d_setup_actor_in_camera_space(WorldObject far *entry)
;   {
;       short far *pDst;
;       short far *pSrc;
;       long far *pWorld;
;       long far *pCam;
;       int i;
;       long z;
;
;       pSrc = (short far *)((char far *)entry + 0x0e);
;       pDst = g_matXIn;
;       for (i = 0; i < 3; i++)
;           pDst[i] = pSrc[i];
;
;       pSrc = (short far *)((char far *)entry + 0x02);
;       pDst = (short far *)&g_lActorRelX;
;       for (i = 0; i < 6; i++)
;           pDst[i] = pSrc[i];
;
;       g_lActorRelX -= g_camCurWorldPos[0];
;       g_lActorRelY -= g_camCurWorldPos[1];
;       g_lActorRelZ -= g_camCurWorldPos[2];
;
;       r3d_mat3_xform_vec3_ll(&g_lActorRelX, &g_mat3x3ViewRot, &g_dwActorCamX);
;
;       z = g_dwActorCamZ;
;       if (z < (long)(unsigned short)g_nActorFarClipThreshold)
;           z = (long)(unsigned short)g_nActorFarClipThreshold;
;       g_lActorClampedCamZ = z;
;   }
; ============================================================================
@entry equ dword ptr [bx+4]
	public _r3d_setup_actor_in_camera_space
_r3d_setup_actor_in_camera_space:
	mov BX,SP
	push SI
	push DI
	push DS
	lds BX, @entry
	mov AX,CS
	mov ES,AX
	mov SI,BX
	add SI,0eh
	mov DI,offset g_matXIn
	mov CX,3h
	rep movsw
	mov SI,BX
	add SI,2h
	mov DI,offset _g_lActorRelX
	mov CX,6h
	rep movsw
	mov AX,CS
	mov DS,AX
	mov SI,offset g_camCurWorldPos
	mov DI,offset _g_lActorRelX
	mov AX, word ptr [SI]
	mov DX, word ptr [SI+2]
	sub word ptr [DI], AX
	sbb word ptr [DI+2], DX
	mov AX, word ptr [SI+4]
	mov DX, word ptr [SI+6]
	sub word ptr [DI+4], AX
	sbb word ptr [DI+6], DX
	mov AX, word ptr [SI+8]
	mov DX, word ptr [SI+10]
	sub word ptr [DI+8], AX
	sbb word ptr [DI+10], DX
	mov AX,offset _g_lActorRelX
	mov BX,offset _g_mat3x3ViewRot
	mov CX,offset _g_dwActorCamX
	call _r3d_mat3_xform_vec3_ll
	mov SI,offset _g_dwActorCamX
	mov DI,offset g_lActorClampedCamZ
	mov AX, word ptr [SI+4]
	mov DX, word ptr [SI+6]
	mov BX, word ptr ds:[g_nViewPlaneDist]
	or DX,DX
	jg @@storeZ		; Z > 0: keep Z (above threshold)
	jl @@clampZ		; Z < 0: force to threshold
	cmp AX,BX
	jnc @@storeZ		; Z >= threshold: keep
@@clampZ:
	mov AX,BX
	xor DX,DX
@@storeZ:
	mov word ptr [DI], AX
	mov word ptr [DI+2], DX
	pop DS
	pop DI
	pop SI
	retf

; ============================================================================
; _r3d_compose_actor_camera_matrix
;
; Builds the actor->camera 3x3 matrix and rescales the actor's cam-space coordinates by a
; bounding-extent-driven shift for the mesh transform.
;
; C equivalent:
;   void r3d_compose_actor_camera_matrix(void)
;   {
;       long extent;
;       long a;
;       int shift;
;       int count;
;
;       /* actor orientation angles were left in g_matXIn by
;          r3d_setup_actor_in_camera_space; turn them into a rotation
;          matrix, fold the camera view rotation in, then transpose. */
;       r3d_build_rotation_matrix(&g_matXIn, &g_mat3x3TempOut);
;       r3d_matrix3x3_multiply(&g_mat3x3TempOut, &g_mat3x3ViewRot,
;                              &g_mat3x3ActorRot);
;       r3d_matrix3x3_transpose(&g_mat3x3TempOut);
;
;       /* bounding extent = max(|camX|, |camZ|, |camY|) */
;       extent = labs(g_dwActorCamX);
;       a = labs(g_dwActorCamZ);
;       if (a > extent)
;           extent = a;
;       a = labs(g_dwActorCamY);
;       if (a > extent)
;           extent = a;
;       g_dwActorBoundExtent = extent;
;
;       /* pre-scale by the mesh scale shift, then renormalize down until
;          the magnitude fits under 0x3fac (14-bit fixed-point headroom). */
;       a = g_dwMeshBoundHalfExtent + extent;
;       for (shift = g_wMeshScaleShift; shift != 0; shift--)
;           a >>= 1;
;       count = g_wMeshScaleShift;
;       while (a >= 0x3fac) {
;           a >>= 1;
;           count++;
;       }
;       g_bMeshRenormCount = count;
;       g_wMeshScaleResidual = g_wMeshScaleShift - count;
;
;       /* apply the renormalizing shift to every cam-space quantity */
;       g_nMeshNormOriginX = (int)(g_lActorClampedCamZ >> count);
;
;       g_nMeshOriginX = (int)(g_dwActorCamX >> count);
;       g_nMeshOriginY = (int)(g_dwActorCamZ >> count);
;       g_nMeshOriginZ = (int)(g_dwActorCamY >> count);
;
;       g_matXIn = (int)(g_lActorRelX >> count);
;       g_matYIn = (int)(g_lActorRelY >> count);
;       g_matZIn = (int)(g_lActorRelZ >> count);
;
;       /* rotate the scaled origin into the final actor->camera frame, and
;          rotate the world directional-light vector through the transposed
;          actor matrix into object space for per-face shading. */
;       r3d_matrix3x3_transform_vec3(&g_matXIn, &g_mat3x3TempOut,
;                                    &g_nMeshCamOriginX);
;       r3d_matrix3x3_transform_vec3(&g_vec3LightDirWorld, &g_mat3x3TempOut,
;                                    &g_vec3LightDirObj);
;   }
; ============================================================================
	public _r3d_compose_actor_camera_matrix
_r3d_compose_actor_camera_matrix:
	push SI
	push DI
	push DS
	mov AX,CS
	mov DS,AX
	mov AX,offset g_mat3x3TempOut
	push AX
	mov AX,offset g_matXIn
	push AX
	push CS
	call _r3d_build_rotation_matrix
	add SP,4h
	mov AX,offset g_mat3x3ActorRot
	push AX
	mov AX,offset _g_mat3x3ViewRot
	push AX
	mov AX,offset g_mat3x3TempOut
	push AX
	push CS
	call _r3d_matrix3x3_multiply
	add SP,6h
	mov AX,offset g_mat3x3TempOut
	push AX
	push CS
	call _r3d_matrix3x3_transpose
	add SP,2h
	mov SI,offset _g_dwActorCamX
	mov AX, word ptr [SI]
	mov DX, word ptr [SI+2]
	or DX,DX
	jge @@absCamX		; camX already >= 0
	NEG32 DX, AX
@@absCamX:
	mov BX,AX
	mov CX,DX
	mov AX, word ptr [SI+4]
	mov DX, word ptr [SI+6]
	or DX,DX
	jge @@absCamZ		; camZ already >= 0
	NEG32 DX, AX
@@absCamZ:
	cmp CX,DX
	jg @@keepExtentZ	; current extent > |camZ|
	jl @@newExtentZ
	cmp BX,AX
	jnc @@keepExtentZ
@@newExtentZ:
	mov BX,AX
	mov CX,DX
@@keepExtentZ:
	mov AX, word ptr [SI+8]
	mov DX, word ptr [SI+10]
	or DX,DX
	jge @@absCamY		; camY already >= 0
	NEG32 DX, AX
@@absCamY:
	cmp CX,DX
	jg @@keepExtentY	; current extent > |camY|
	jl @@newExtentY
	cmp BX,AX
	jnc @@keepExtentY
@@newExtentY:
	mov BX,AX
	mov CX,DX
@@keepExtentY:
	mov word ptr ds:[g_dwActorBoundExtent], BX
	mov word ptr ds:[g_dwActorBoundExtent+2], CX
	mov AX, word ptr ds:[g_dwMeshBoundHalfExtent]
	mov DX, word ptr ds:[g_dwMeshBoundHalfExtent+2]
	add AX,BX
	adc DX,CX
	mov CX, word ptr ds:[g_wMeshScaleShift]
	jcxz @@preScaleDone
@@preScaleLoop:
	sar DX,1h
	rcr AX,1h
	loop @@preScaleLoop
@@preScaleDone:
	mov CX, word ptr ds:[g_wMeshScaleShift]
@@renormTest:
	or DX,DX
	jnz @@renormShift	; hi word nonzero: still too large
	cmp AX, 3fach		; renormalize while magnitude >= 3fach
	jc @@renormDone		; below threshold: fits
@@renormShift:
	shr DX,1h
	rcr AX,1h
	inc CX
	jmp short @@renormTest
@@renormDone:
	mov word ptr ds:[g_bMeshRenormCount], CX
	mov AX, word ptr ds:[g_wMeshScaleShift]
	sub AX,CX
	mov word ptr ds:[g_wMeshScaleResidual], AX
	mov AX, word ptr ds:[g_lActorClampedCamZ]
	mov DX, word ptr ds:[g_lActorClampedCamZ+2]
	mov BX,CX
	jcxz @@normZDone
@@normZLoop:
	sar DX,1h
	rcr AX,1h
	loop @@normZLoop
@@normZDone:
	mov word ptr ds:[g_nMeshNormOriginX], AX
	mov SI,offset _g_dwActorCamX
	mov DI,offset g_nMeshOriginX
	mov AX, word ptr [SI]
	mov DX, word ptr [SI+2]
	mov CX,BX
	jcxz @@originXDone
@@originXLoop:
	sar DX,1h
	rcr AX,1h
	loop @@originXLoop
@@originXDone:
	mov word ptr [DI], AX
	mov AX, word ptr [SI+4]
	mov DX, word ptr [SI+6]
	mov CX,BX
	jcxz @@originYDone
@@originYLoop:
	sar DX,1h
	rcr AX,1h
	loop @@originYLoop
@@originYDone:
	mov word ptr [DI+2], AX
	mov AX, word ptr [SI+8]
	mov DX, word ptr [SI+10]
	mov CX,BX
	jcxz @@originZDone
@@originZLoop:
	sar DX,1h
	rcr AX,1h
	loop @@originZLoop
@@originZDone:
	mov word ptr [DI+4], AX
	mov SI,offset _g_lActorRelX
	mov DI,offset g_matXIn
	mov AX, word ptr [SI]
	mov DX, word ptr [SI+2]
	mov CX,BX
	jcxz @@deltaXDone
@@deltaXLoop:
	sar DX,1h
	rcr AX,1h
	loop @@deltaXLoop
@@deltaXDone:
	mov word ptr [DI], AX
	mov AX, word ptr [SI+4]
	mov DX, word ptr [SI+6]
	mov CX,BX
	jcxz @@deltaYDone
@@deltaYLoop:
	sar DX,1h
	rcr AX,1h
	loop @@deltaYLoop
@@deltaYDone:
	mov word ptr [DI+2], AX
	mov AX, word ptr [SI+8]
	mov DX, word ptr [SI+10]
	mov CX,BX
	jcxz @@deltaZDone
@@deltaZLoop:
	sar DX,1h
	rcr AX,1h
	loop @@deltaZLoop
@@deltaZDone:
	mov word ptr [DI+4], AX
	mov AX,offset g_matXIn
	mov BX,offset g_mat3x3TempOut
	mov CX,offset g_nMeshCamOriginX
	call _r3d_matrix3x3_transform_vec3
	mov AX,offset g_vec3LightDirWorld
	mov BX,offset g_mat3x3TempOut
	mov CX,offset g_vec3LightDirObj
	call _r3d_matrix3x3_transform_vec3
	pop DS
	pop DI
	pop SI
	retf

; ============================================================================
; _r3d_actor_compute_lod_z
;
; Computes the actor mesh's camera-space Z depth metric (g_lActorLodZ) used for LOD selection
; and draw ordering.
;
; C equivalent:
;   void r3d_actor_compute_lod_z(void)
;   {
;       unsigned char far *meshHdr;
;       short far *rot;
;       long axisMin, hi, lo, camZ;
;       long minA, minB;
;       int i;
;
;       meshHdr = (unsigned char far *)g_pCurActorPagedRec;
;       camZ = g_dwActorCamZ;
;
;       if (meshHdr[0] & 0x20) {
;           /* Simple mesh: depth = camera Z minus the mesh bound half-extent. */
;           g_lActorLodZ = camZ - g_dwMeshBoundHalfExtent;
;           return;
;       }
;
;       /* General mesh: project the three object-space bound intervals onto the
;          camera-forward (view-Z) axis using column 1 of the actor rotation, then
;          take, per axis, the nearer (smaller) of the two interval endpoints. */
;       rot = (short far *)&g_mat3x3ActorRot;
;
;       /* Axis X: header shorts at +0x0e (min) and +0x14 (max), rot m[0][1]. */
;       if (rot[1] == 0) {
;           axisMin = 0;
;       } else {
;           minA = ((long)*(short far *)(meshHdr + 0x0e) * rot[1]) >> 14;
;           minB = ((long)*(short far *)(meshHdr + 0x14) * rot[1]) >> 14;
;           axisMin = (minB < minA) ? minB : minA;
;       }
;       g_lActorLodZ = axisMin;
;
;       /* Axis Y: header shorts at +0x10 (min) and +0x16 (max), rot m[1][1]. */
;       if (rot[4] == 0) {
;           axisMin = 0;
;       } else {
;           minA = ((long)*(short far *)(meshHdr + 0x10) * rot[4]) >> 14;
;           minB = ((long)*(short far *)(meshHdr + 0x16) * rot[4]) >> 14;
;           axisMin = (minB < minA) ? minB : minA;
;       }
;       g_lActorLodZ += axisMin;
;
;       /* Axis Z: header shorts at +0x12 (min) and +0x18 (max), rot m[2][1]. */
;       if (rot[7] == 0) {
;           axisMin = 0;
;       } else {
;           minA = ((long)*(short far *)(meshHdr + 0x12) * rot[7]) >> 14;
;           minB = ((long)*(short far *)(meshHdr + 0x18) * rot[7]) >> 14;
;           axisMin = (minB < minA) ? minB : minA;
;       }
;       g_lActorLodZ += axisMin;
;
;       /* Rescale the summed depth and shift it into camera space. */
;       for (i = g_wMeshScaleShift; i != 0; i--)
;           g_lActorLodZ <<= 1;
;       g_lActorLodZ += camZ;
;   }
; ============================================================================
	public _r3d_actor_compute_lod_z
_r3d_actor_compute_lod_z:
	push BP
	push SI
	push DI
	push DS
	mov AX,CS
	mov DS,AX
	les SI, dword ptr ds:[g_pCurActorPagedRec]
	mov AL, ES:byte ptr [SI]
	and AL,MESH_FLAG_SIMPLE
	jz @@generalMesh
	mov BX, word ptr ds:[g_dwMeshBoundHalfExtent]
	mov CX, word ptr ds:[g_dwMeshBoundHalfExtent+2]
	mov SI,offset _g_dwActorCamX
	mov DI,offset g_lActorLodZ
	mov AX, word ptr [SI+4]
	mov DX, word ptr [SI+6]
	sub AX,BX
	sbb DX,CX
	mov word ptr [DI], AX
	mov word ptr [DI+2], DX
	jmp @@done
@@generalMesh:
	mov DI,offset g_mat3x3ActorRot
	mov BX,offset g_lActorLodZ
	mov CX, word ptr [DI+2]
	jcxz @@axisXZero	; rot m[0][1] == 0
	mov AX, ES:word ptr [SI+14]
	imul CX
	Q14NORM
	mov BP,DX
	mov AX, ES:word ptr [SI+20]
	imul CX
	Q14NORM
	cmp BP,DX
	jle @@axisXMin
	mov BP,DX
	jmp short @@axisXMin
@@axisXZero:
	xor BP,BP
@@axisXMin:
	mov AX,BP
	cwd
	mov word ptr [BX], AX
	mov word ptr [BX+2], DX
	mov CX, word ptr [DI+8]
	jcxz @@axisYZero	; rot m[1][1] == 0
	mov AX, ES:word ptr [SI+16]
	imul CX
	Q14NORM
	mov BP,DX
	mov AX, ES:word ptr [SI+22]
	imul CX
	Q14NORM
	cmp BP,DX
	jle @@axisYMin
	mov BP,DX
	jmp short @@axisYMin
@@axisYZero:
	xor BP,BP
@@axisYMin:
	mov AX,BP
	cwd
	add word ptr [BX], AX
	adc word ptr [BX+2], DX
	mov CX, word ptr [DI+14]
	jcxz @@axisZZero	; rot m[2][1] == 0
	mov AX, ES:word ptr [SI+18]
	imul CX
	Q14NORM
	mov BP,DX
	mov AX, ES:word ptr [SI+24]
	imul CX
	Q14NORM
	cmp BP,DX
	jle @@axisZMin
	mov BP,DX
	jmp short @@axisZMin
@@axisZZero:
	xor BP,BP
@@axisZMin:
	mov AX,BP
	cwd
	add word ptr [BX], AX
	adc word ptr [BX+2], DX
	mov SI,offset _g_dwActorCamX
	mov AX, word ptr [BX]
	mov DX, word ptr [BX+2]
	mov CX, word ptr ds:[g_wMeshScaleShift]
	jcxz @@rescaleDone
@@rescaleLoop:
	shl AX,1h
	rcl DX,1h
	loop @@rescaleLoop
@@rescaleDone:
	add AX, word ptr [SI+4]
	adc DX, word ptr [SI+6]
	mov word ptr [BX], AX
	mov word ptr [BX+2], DX
@@done:
	pop DS
	pop DI
	pop SI
	pop BP
	retf

; Gap 0x02ff-0x02ff: 1B zero-init
	db 0
; ============================================================================
; _r3d_backface_dot_indexed
;
; Loads two 3-short vertex rows (indexed by AL and AH) from an ES:BP vertex table, storing the
; AL row raw into the g_matXIn2 scratch vector and the AH row into g_matXOut after an arithmetic
; down-shift by the mesh scale residual plus the camera-space mesh origin, then tail-calls
; r3d_dot3_long on the two vectors.
;
; C equivalent (register-convention MODEL: idxNormal arrives in AL, idxFace in AH, and the table
; base in ES:BP -- there is no packed uchar and no pushed pointer; see Note):
;   long r3d_backface_dot_indexed(unsigned char idxNormal, unsigned char idxFace,
;                                   int far *pVertexTable /* = ES:BP */)
;   {
;       int far *pRowA;
;       int far *pRowB;
;       int shift;
;
;       /* AL (idxNormal) selects the "In2" (normal) vertex, AH (idxFace) selects
;          the "Out" (face) vertex.  Each row is 3 shorts (x, y, z); stride 6 bytes. */
;       pRowA = pVertexTable + idxNormal * 3;
;       pRowB = pVertexTable + idxFace   * 3;
;
;       /* Row A is copied verbatim into the secondary input vector. */
;       g_matXIn2 = pRowA[0];
;       g_matYIn2 = pRowA[1];
;       g_matZIn2 = pRowA[2];
;
;       /* Row B is scaled down (arithmetic right shift by the residual
;          bit count) and biased by the mesh origin in camera space. */
;       shift = (-(int)g_wMeshScaleResidual) & 0x1F;
;       g_matXOut = (pRowB[0] >> shift) + g_nMeshCamOriginX;
;       g_matYOut = (pRowB[1] >> shift) + g_nMeshCamOriginY;
;       g_matZOut = (pRowB[2] >> shift) + g_nMeshCamOriginZ;
;
;       /* Dot the two scratch vectors (In2 . Out) and return the 32-bit result. */
;       return r3d_dot3_long(&g_matXIn2, &g_matXOut);
;   }
; ============================================================================
	public _r3d_backface_dot_indexed
_r3d_backface_dot_indexed:
	mov BL,AL
	xor BH,BH
	shl BX,1h
	mov CL,AH
	xor CH,CH
	shl CX,1h
	VROWADDR
	mov AX, ES:word ptr [BX].vX
	mov word ptr ds:[g_matXIn2], AX
	mov AX, ES:word ptr [BX].vY
	mov word ptr ds:[g_matYIn2], AX
	mov AX, ES:word ptr [BX].vZ
	mov word ptr ds:[g_matZIn2], AX
	mov BX,CX
	VROWADDR
	mov CX, word ptr ds:[g_wMeshScaleResidual]
	neg CX
	mov AX, ES:word ptr [BX].vX
	mov CH,CL
	sar AX,CL
	add AX, word ptr ds:[g_nMeshCamOriginX]
	mov word ptr ds:[g_matXOut], AX
	mov AX, ES:word ptr [BX].vY
	mov CL,CH
	sar AX,CL
	add AX, word ptr ds:[g_nMeshCamOriginY]
	mov word ptr ds:[g_matYOut], AX
	mov AX, ES:word ptr [BX].vZ
	mov CL,CH
	sar AX,CL
	add AX, word ptr ds:[g_nMeshCamOriginZ]
	mov word ptr ds:[g_matZOut], AX
	mov AX,offset g_matXIn2
	mov BX,offset g_matXOut
	jmp _r3d_dot3_long

; In-segment data at 0x0371 [g_nMeshPartPolygonsRemaining]
g_nMeshPartPolygonsRemaining	dw 0

; In-segment data at 0x0373 [g_bNearClipNeeded]
g_bNearClipNeeded	db 0

; ============================================================================
; _r3d_mesh_part_polygons
;
; Transforms, projects, clips and rasterizes every polygon of one mesh part, caching per-vertex
; work in CS-resident scratch arrays keyed by the mesh's vertex pool.
;
; C equivalent:
;   #define POLY_TYPE_MASK      0x03
;   #define POLY_TYPE_SKIP      2
;   #define POLY_FLAG_FLIPTEST  0x20
;   #define POLY_FLAG_TEXTURED  0x10
;
;   #define CLIP_UNTOUCHED  0
;   #define CLIP_PENDING    1
;   #define CLIP_ONSCREEN   2
;   #define CLIP_NEARCLIP   3
;
;   typedef struct {
;       unsigned char flags;    /* +0: bits0-1 type, bit4 textured, bit5 flip-test */
;       unsigned char pad[4];   /* +1 */
;       unsigned char nrmVert;  /* +5: index of the vertex used for the face normal */
;       unsigned char far *vertIdx; /* +6: near ptr to 0xFF-terminated index list */
;   } MeshPolygon;
;
;   void far r3d_mesh_part_polygons(unsigned char far *partHeader)
;   {
;       unsigned int poolOff;
;       MeshPolygon far *poly;
;       unsigned char far *idxList;
;       short far *src;
;       unsigned char vi;
;       unsigned int slot;
;       int camY;
;       long acc;
;       unsigned char shift;
;       int i, n;
;
;       poolOff = g_wMeshVertexPoolOff;
;
;       /* Invalidate the per-vertex clip-state cache when the mesh's vertex
;          pool (segment:offset) differs from the last part processed. */
;       if (FP_SEG(partHeader) != g_wMeshVertexCacheSeg ||
;           poolOff != (unsigned int)g_dwMeshVertexFarPtrCache) {
;           g_wMeshVertexCacheSeg = FP_SEG(partHeader);
;           g_dwMeshVertexFarPtrCache = poolOff;
;           for (i = 0; i < g_nMeshPartVertexCount; i++)
;               g_abPolygonClipState[i] = CLIP_UNTOUCHED;
;       }
;
;       g_nMeshPartPolygonsRemaining = *(short far *)partHeader;
;       poly = *(MeshPolygon far *far *)(partHeader + 2);
;
;       for (; --g_nMeshPartPolygonsRemaining >= 0; poly = (MeshPolygon far *)poly + 1) {
;           int type = poly->flags & POLY_TYPE_MASK;
;           if (type == POLY_TYPE_SKIP)
;               continue;
;
;           idxList = poly->vertIdx;
;           g_bPolyNormalFlipped = 0;
;
;           if (type == 0) {
;               /* Two-sided face: keep it either way, but flip the normal
;                  when the front side faces away from the camera. */
;               if ((poly->flags & POLY_FLAG_FLIPTEST) &&
;                   r3d_backface_dot_indexed() >= 0)
;                   g_bPolyNormalFlipped = 1;
;           } else {
;               /* One-sided face: back-face cull when the normal projects away. */
;               if (r3d_backface_dot_indexed() >= 0)
;                   continue;
;           }
;
;           r3d_polygon_resolve_shade_color();
;           g_bNearClipNeeded = 0;
;           g_nMeshPolyVertexCount = 0;
;
;           /* Transform / project each referenced vertex once, memoizing the
;              result in the clip-state cache so shared vertices are reused. */
;           for (; (vi = *idxList) != 0xFF; idxList++) {
;               slot = (unsigned int)vi * 2;
;
;               if (g_abPolygonClipState[vi] == CLIP_UNTOUCHED) {
;                   g_abPolygonClipState[vi] = CLIP_PENDING;
;
;                   src = (short far *)(poolOff + (unsigned int)vi * 6);
;                   g_matXIn = src[0];
;                   g_matYIn = src[1];
;                   g_matZIn = src[2];
;                   r3d_matrix3x3_transform_vec3();
;
;                   g_aVertexCamX[vi] = g_matXOut + (int)g_dwActorCamX;
;                   g_aVertexCamY[vi] = g_matYOut + (int)g_dwActorCamZ;
;                   g_aVertexCamZ[vi] = g_matZOut + (int)g_dwActorCamY;
;               } else if (g_abPolygonClipState[vi] != CLIP_ONSCREEN) {
;                   goto emit;   /* already near-clipped: skip re-projection */
;               } else {
;                   goto emit;   /* already on-screen: reuse cached screen coords */
;               }
;
;               camY = g_aVertexCamY[vi];
;               if (camY < g_nViewPlaneDist) {
;                   g_abPolygonClipState[vi] = CLIP_NEARCLIP;
;                   g_bNearClipNeeded = 1;
;               } else {
;                   g_abPolygonClipState[vi] = CLIP_ONSCREEN;
;                   shift = g_nScreenShift;
;
;                   /* screenX = (camX << shift) / camY  (perspective divide) */
;                   acc = (long)g_aVertexCamX[vi] << shift;
;                   g_aVertexScrX[vi] = (int)(acc / camY);
;
;                   /* screenY = (camZ << shift) / camY */
;                   acc = (long)g_aVertexCamZ[vi] << shift;
;                   g_aVertexScrY[vi] = (int)(acc / camY);
;               }
;
;           emit:
;               g_polygon_vertices[g_nMeshPolyVertexCount++] = slot;
;           }
;
;           if (!g_bNearClipNeeded) {
;               /* Fully in front of the near plane: copy screen coords out. */
;               if (g_nMeshPolyVertexCount == 0)
;                   continue;
;               n = g_nMeshPolyVertexCount;
;               for (i = 0; i < n; i++) {
;                   unsigned int v = g_polygon_vertices[i];
;                   g_aPolyInX[i] = g_aVertexScrX[v / 2];
;                   g_aPolyInY[i] = g_aVertexScrY[v / 2];
;               }
;           } else {
;               /* Some vertices cross the near plane: clip in Z first.  A flat
;                  textured floor quad whose local normal is +Y is handled by a
;                  specialized world/screen emitter instead. */
;               unsigned char nvi = poly->nrmVert;
;               short far *nrm = (short far *)(poolOff + (unsigned int)nvi * 6);
;               if (g_game_mode == 2 && (poly->flags & POLY_FLAG_TEXTURED) &&
;                   nrm[0] == 0 && nrm[1] == 0 && nrm[2] != 0)
;                   r3d_poly_emit_screen_or_world();
;               else
;                   r3d_polygon_clip_near_z();
;           }
;
;           r3d_apply_viewport_offset();
;
;           if (poly->flags & POLY_FLAG_TEXTURED) {
;               unsigned char nvi = poly->nrmVert;
;               short far *nrm = (short far *)(poolOff + (unsigned int)nvi * 6);
;               if (g_game_mode != 2 || g_bTexturedPolyEnabled ||
;                   nrm[0] != 0 || nrm[1] != 0 || nrm[2] == 0) {
;                   r3d_polygon_submit_textured_quad();
;                   continue;
;               }
;               /* Flat +/-Y floor tile: draw as a flat-shaded fill (8 or 9). */
;               g_graphics_context.bGfx_outline_color = (nrm[2] < 0) ? 9 : 8;
;               g_graphics_context.bGfx_fill_color    = (nrm[2] < 0) ? 9 : 8;
;               g_graphics_context.bGfx_fill_enabled  = 1;
;           }
;
;           if (g_bActorViewportClip)
;               r3d_polygon_scissor_2d();
;           r3d_polygon_submit_to_rasterizer();
;       }
;   }
; ============================================================================
@part_header equ dword ptr [bp+6]
	public _r3d_mesh_part_polygons
_r3d_mesh_part_polygons:
	push BP
	mov BP,SP
	push SI
	push DI
	push DS
	mov AX,CS
	mov DS,AX
	les DI, @part_header
	mov BP, word ptr ds:[g_wMeshVertexPoolOff]
	mov AX,ES
	cmp word ptr ds:[g_wMeshVertexCacheSeg], AX
	jnz @@clearClipCache
	cmp word ptr ds:[g_dwMeshVertexFarPtrCache], BP
	jz @@readPolyList
@@clearClipCache:
	mov word ptr ds:[g_wMeshVertexCacheSeg], AX
	mov word ptr ds:[g_dwMeshVertexFarPtrCache], BP
	push DI
	push ES
	mov AX,CS
	mov ES,AX
	mov DI,offset g_abPolygonClipState
	mov CX, word ptr ds:[g_nMeshPartVertexCount]
	xor AX,AX
	rep stosw
	pop ES
	pop DI
@@readPolyList:
	mov AX, ES:word ptr [DI].hPolyCount
	mov word ptr ds:[g_nMeshPartPolygonsRemaining], AX
	mov DI, ES:word ptr [DI].hFirstPoly
@@nextPoly:
	dec word ptr ds:[g_nMeshPartPolygonsRemaining]
	jge @@polyBody
	jmp @@done
@@polyBody:
	mov AL, ES:byte ptr [DI].fFlags
	mov AH,AL
	and AL,3h
	cmp AL,2h
	jz @@skipPoly		; kind 2: no backface test, skip
	mov SI, ES:word ptr [DI].fVertList
	mov byte ptr ds:[g_bPolyNormalFlipped], 0
	cmp AL,0h
	jnz @@backfaceTest
	test AH,MESH_FLAG_SIMPLE
	jz @@processPoly
	BACKFACEDOT
	jl @@processPoly
	mov byte ptr ds:[g_bPolyNormalFlipped], 1
	jmp short @@processPoly
@@backfaceTest:
	BACKFACEDOT
	jl @@processPoly
@@skipPoly:
	add DI,FACE_SIZE
	jmp short @@nextPoly
@@processPoly:
	call _r3d_polygon_resolve_shade_color
	xor AX,AX
	mov byte ptr ds:[g_bNearClipNeeded], AL
	mov word ptr ds:[g_nMeshPolyVertexCount], AX
@@nextVertex:
	mov AL, ES:byte ptr [SI]
	cmp AL,0ffh
	jnz @@vertexLive
	jmp @@vertexLoopDone
@@vertexLive:
	mov BL,AL
	xor BH,BH
	shl BX,1h
	cmp byte ptr [BX+g_abPolygonClipState], CLIPST_UNTOUCHED
	jz @@projectVertex
	cmp byte ptr [BX+g_abPolygonClipState], CLIPST_PROJECTED
	jnz @@reuseCached	; not on-screen: reuse cached cam coords
	jmp @@emitSlot		; already on-screen: reuse screen coords
@@reuseCached:
	jmp short @@testNearPlane
@@projectVertex:
	mov byte ptr [BX+g_abPolygonClipState], CLIPST_PENDING
	push BX
	VROWADDR
	mov AX, ES:word ptr [BX].vX
	mov word ptr ds:[g_matXIn], AX
	mov AX, ES:word ptr [BX].vY
	mov word ptr ds:[g_matYIn], AX
	mov AX, ES:word ptr [BX].vZ
	mov word ptr ds:[g_matZIn], AX
	mov AX,offset g_matXIn
	mov BX,offset g_mat3x3ActorRot
	mov CX,offset g_matXOut
	call _r3d_matrix3x3_transform_vec3
	pop BX
	mov AX, word ptr ds:[g_matXOut]
	add AX, word ptr ds:[g_dwActorCamX]
	mov word ptr [BX+g_aVertexCamX], AX
	mov AX, word ptr ds:[g_matYOut]
	add AX, word ptr ds:[g_dwActorCamZ]
	mov word ptr [BX+g_aVertexCamY], AX
	mov AX, word ptr ds:[g_matZOut]
	add AX, word ptr ds:[g_dwActorCamY]
	mov word ptr [BX+g_aVertexCamZ], AX
@@testNearPlane:
	mov AX, word ptr [BX+g_aVertexCamY]
	cmp AX, word ptr ds:[g_nViewPlaneDist]
	jge @@projectScreen	; camY >= near plane: project
	mov byte ptr [BX+g_abPolygonClipState], CLIPST_BEHIND
	mov byte ptr ds:[g_bNearClipNeeded], 1
	jmp short @@emitSlot
@@projectScreen:
	push SI
	mov byte ptr [BX+g_abPolygonClipState], CLIPST_PROJECTED
	mov SI,AX
	mov CX, word ptr ds:[g_nScreenShift]
	push CX
	mov AX, word ptr [BX+g_aVertexCamX]
	cwd
	cmp CL,8h
	jl @@scrXShift
	mov DL,AH
	mov AH,AL
	xor AL,AL
	sub CL,8h
	jz @@scrXDivide
@@scrXShift:
	shl AX,1h
	rcl DX,1h
	loop @@scrXShift
@@scrXDivide:
	idiv SI
	mov word ptr [BX+g_aVertexScrX], AX
	mov AX, word ptr [BX+g_aVertexCamZ]
	pop CX
	cwd
	cmp CL,8h
	jl @@scrYShift
	mov DL,AH
	mov AH,AL
	xor AL,AL
	sub CL,8h
	jz @@scrYDivide
@@scrYShift:
	shl AX,1h
	rcl DX,1h
	loop @@scrYShift
@@scrYDivide:
	idiv SI
	mov word ptr [BX+g_aVertexScrY], AX
	pop SI
@@emitSlot:
	mov AX,BX
	mov BX, word ptr ds:[g_nMeshPolyVertexCount]
	shl BX,1h
	mov word ptr [BX+g_polygon_vertices], AX
	inc word ptr ds:[g_nMeshPolyVertexCount]
	inc SI
	jmp @@nextVertex
@@vertexLoopDone:
	cmp byte ptr ds:[g_bNearClipNeeded], 0
	jz @@copyScreen
	cmp SS:word ptr [_g_game_mode], 2
	jnz @@clipNearZ
	mov AL, ES:byte ptr [DI].fFlags
	and AL,10h
	jz @@clipNearZ
	mov AL, ES:byte ptr [DI].fNrmVert
	mov BL,AL
	xor BH,BH
	shl BX,1h
	VROWADDR
	cmp ES:word ptr [BX].vX, 0
	jnz @@clipNearZ
	cmp ES:word ptr [BX].vY, 0
	jnz @@clipNearZ
	cmp ES:word ptr [BX].vZ, 0
	jnz @@emitFloorTile	; flat +/-Y floor tile
@@clipNearZ:
	call _r3d_polygon_clip_near_z
	jmp short @@applyViewport
@@emitFloorTile:
	call _r3d_poly_emit_screen_or_world
	jmp short @@applyViewport
@@copyScreen:
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	or AX,AX
	jnz @@copyLoopInit
	jmp @@advance
@@copyLoopInit:
	mov CX,AX
	xor BX,BX
@@nextCopy:
	mov SI, word ptr [BX+g_polygon_vertices]
	mov AX, word ptr [SI+g_aVertexScrX]
	mov word ptr [BX+g_aPolyInX], AX
	mov AX, word ptr [SI+g_aVertexScrY]
	mov word ptr [BX+g_aPolyInY], AX
	add BX,2h
	loop @@nextCopy
@@applyViewport:
	call _r3d_apply_viewport_offset
	mov AL, ES:byte ptr [DI].fFlags
	test AL,10h
	jz @@submitPoly
	cmp SS:word ptr [_g_game_mode], 2
	jnz @@submitTextured
	cmp SS:word ptr [_g_bTexturedPolyEnabled], 0
	jnz @@submitTextured
	mov AL, ES:byte ptr [DI].fNrmVert
	mov BL,AL
	xor BH,BH
	shl BX,1h
	VROWADDR
	cmp ES:word ptr [BX].vX, 0
	jnz @@submitTextured
	cmp ES:word ptr [BX].vY, 0
	jnz @@submitTextured
	cmp ES:word ptr [BX].vZ, 0
	jnz @@floorFlatShade	; flat +/-Y floor tile
@@submitTextured:
	call _r3d_polygon_submit_textured_quad
	jmp short @@advance
@@floorFlatShade:
	mov AL,9h
	js @@setFillColor	; nrm[2] < 0: color 9
	mov AL,8h
@@setFillColor:
	mov byte ptr SS:[_g_graphics_context.bGfx_outline_color], AL
	mov byte ptr SS:[_g_graphics_context.bGfx_fill_color], AL
	mov SS:byte ptr [_g_graphics_context.bGfx_fill_enabled], 1
@@submitPoly:
	cmp byte ptr ds:[g_bActorViewportClip], 0
	jz @@rasterize
	call _r3d_polygon_scissor_2d
@@rasterize:
	call _r3d_polygon_submit_to_rasterizer
@@advance:
	add DI,FACE_SIZE
	jmp @@nextPoly
@@done:
	pop DS
	pop DI
	pop SI
	pop BP
	retf

; ============================================================================
; _r3d_poly_emit_screen_or_world
;
; Pass 2 of the mesh-poly pipeline: for each polygon vertex, emits either its projected screen
; (x,y) or its raw camera-space (x,z) into the poly draw arrays, and drops the whole polygon if
; no vertex survived.
;
; C equivalent:
;   #define CLIP_STATE_NEAR_CLIPPED 3
;
;   void r3d_poly_emit_screen_or_world(void)
;   {
;       int i;
;       int vtxOff;
;       int keptCount;
;
;       if (g_nMeshPolyVertexCount == 0)
;           return;
;
;       keptCount = 0;
;       for (i = 0; i < g_nMeshPolyVertexCount; i++) {
;           vtxOff = g_polygon_vertices[i];
;
;           if (VTX_BYTE(g_abPolygonClipState, vtxOff) == CLIP_STATE_NEAR_CLIPPED) {
;               /* near-clipped / unprojected: emit raw camera-space (x,z),
;                  and count as kept only if in front of the camera plane. */
;               VTX_WORD(g_aPolyInX, i) = VTX_WORD(g_aVertexCamX, vtxOff);
;               VTX_WORD(g_aPolyInY, i) = VTX_WORD(g_aVertexCamZ, vtxOff);
;               if (VTX_WORD(g_aVertexCamY, vtxOff) >= 0)
;                   keptCount++;
;           } else {
;               /* projected (state 2): emit screen (x,y), always kept. */
;               keptCount++;
;               VTX_WORD(g_aPolyInX, i) = VTX_WORD(g_aVertexScrX, vtxOff);
;               VTX_WORD(g_aPolyInY, i) = VTX_WORD(g_aVertexScrY, vtxOff);
;           }
;       }
;
;       if (keptCount == 0)
;           g_nMeshPolyVertexCount = 0;
;   }
; ============================================================================
	public _r3d_poly_emit_screen_or_world
_r3d_poly_emit_screen_or_world:
	push BP
	mov BP,SP
	pusha
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	or AX,AX
	jz @@done
	mov CX,AX
	xor BX,BX
	xor DX,DX			; DX = keptCount
@@nextVertex:
	mov SI, word ptr [BX+g_polygon_vertices]
	cmp byte ptr [SI+g_abPolygonClipState], CLIPST_BEHIND
	jnz @@emitScreen
	; near-clipped (state 3): emit raw camera-space (x,z)
	mov AX, word ptr [SI+g_aVertexCamX]
	mov word ptr [BX+g_aPolyInX], AX
	mov AX, word ptr [SI+g_aVertexCamZ]
	mov word ptr [BX+g_aPolyInY], AX
	cmp word ptr [SI+g_aVertexCamY], 0
	jl @@advance			; behind camera plane: not kept
	inc DX
	jmp short @@advance
@@emitScreen:
	; projected (state 2): emit screen (x,y), always kept
	inc DX
	mov AX, word ptr [SI+g_aVertexScrX]
	mov word ptr [BX+g_aPolyInX], AX
	mov AX, word ptr [SI+g_aVertexScrY]
	mov word ptr [BX+g_aPolyInY], AX
@@advance:
	add BX,2h
	loop @@nextVertex
	or DX,DX
	jnz @@done			; something kept: leave count as-is
	mov word ptr ds:[g_nMeshPolyVertexCount], 0
@@done:
	popa
	pop BP
	ret

; Gap 0x063d-0x0643: 7B zero-init
	db 0			; 0x63d: pad byte
g_vec3LightDirWorld	dw 3 dup(0)	; 0x63e: world-space directional-light vector (persistent),
				; set once by r3d_light_set_direction and dotted against face
				; normals for mesh shading (g_vec3LightDirWorld @ 233e:063e)
; ============================================================================
; _r3d_camera_setup_view
;
; Loads the per-frame 3D camera state (position, orientation, viewport, clip rect) from a
; window's WorldEntity and builds the transposed world-to-view rotation matrix.
;
; C equivalent:
;   void r3d_camera_setup_view(ViewContext *widget)
;   {
;       WorldEntity *camera;
;       short *src;
;       short *dst;
;       int i;
;
;       camera = widget->camera;
;
;       /* copy the camera world position (2 longs xy + 1 long z = 6 words) */
;       src = (short *)&camera->base.position;
;       dst = (short *)g_camCurWorldPos;
;       for (i = 6; i != 0; i--)
;           *dst++ = *src++;
;
;       /* copy the camera orientation pitch/roll/yaw (3 words) */
;       src = (short *)&camera->base.orientation;
;       dst = (short *)g_camViewYaw;
;       for (i = 3; i != 0; i--)
;           *dst++ = *src++;
;
;       g_nScreenShift = (unsigned char)widget->zoom;
;       g_nActorFarClipThreshold = 1 << g_nScreenShift;
;       g_pFaceMaterialTable = widget->faceMaterials;
;       g_pColorRemapTable = widget->colorRemap;
;
;       /* viewport (x, y, w, h) -> inclusive clip rectangle */
;       g_graphics_context.clip.xmin = widget->viewport.x;
;       g_graphics_context.clip.xmax = widget->viewport.x + widget->viewport.width - 1;
;       g_graphics_context.clip.ymin = widget->viewport.y;
;       g_graphics_context.clip.ymax = widget->viewport.y + widget->viewport.height - 1;
;
;       g_nViewportCenterX = widget->viewport.x + ((unsigned)widget->viewport.width >> 1);
;       g_nViewportCenterY = widget->viewport.y + ((unsigned)widget->viewport.height >> 1);
;
;       g_bSkipFarEdgeCull = 0;
;       g_bActorViewportClip = 0;
;
;       /* copy the view-rotation angles pitch/roll/yaw (3 words) into the matrix builder input */
;       src = (short *)&widget->viewRotation;
;       dst = (short *)g_matXIn;
;       for (i = 3; i != 0; i--)
;           *dst++ = *src++;
;
;       /* Build a scratch rotation matrix from the widget's view-rotation
;          angles; its type byte records whether it came out identity. */
;       r3d_build_rotation_matrix(g_matXIn, g_mat3x3ScratchRot);
;
;       if (g_bScratchMatType == 0) {
;           /* Identity scratch matrix: build the view matrix straight from the
;              camera view angles (fast path). */
;           r3d_build_rotation_matrix(g_camViewYaw, g_mat3x3ViewRot);
;       } else {
;           /* Non-identity scratch matrix: build the actor rotation from the
;              view angles, compose the scratch matrix onto it, and recover the
;              Euler view angles from the composed result. */
;           r3d_build_rotation_matrix(g_camViewYaw, g_mat3x3ActorRot);
;           r3d_matrix3x3_multiply(g_mat3x3ScratchRot, g_mat3x3ActorRot,
;                                  g_mat3x3ViewRot);
;           r3d_matrix_to_euler(g_mat3x3ViewRot, g_camViewYaw);
;       }
;
;       r3d_matrix3x3_transpose(g_mat3x3ViewRot);
;   }
; ============================================================================
@widget equ word ptr [bp+6]
	public _r3d_camera_setup_view
_r3d_camera_setup_view:
	push BP
	mov BP,SP
	push SI
	push DI
	push DS
	mov DX,CS
	mov ES,DX
	mov BX, @widget
	mov SI, word ptr [BX+2]
	add SI,2h
	mov DI,offset g_camCurWorldPos
	mov CX,6h
	rep movsw
	mov SI, word ptr [BX+2]
	add SI,0eh
	mov DI,offset g_camViewYaw
	mov CX,3h
	rep movsw
	mov CX, word ptr [BX]
	mov ES:word ptr [g_nScreenShift], CX
	mov AX,1h
	shl AX,CL
	mov word ptr ES:[g_nViewPlaneDist], AX
	mov AX, word ptr [BX+18]
	mov word ptr ES:[g_pFaceMaterialTable], AX
	mov AX, word ptr [BX+20]
	mov word ptr ES:[g_pColorRemapTable], AX
	mov SI,BX
	add BX,0ah
	; --- viewport -> clip rect ------------------------------------------------
	; Window the world-polygon rasterizer to the viewport by storing it into the
	; DGROUP clip-rect fields g_graphics_context.clip.{xmin,xmax,ymin,ymax}. DS is
	; already = DGROUP here (caller's DS, medium model), so write the struct fields
	; directly under a local assume ds:DGROUP.
	assume ds:DGROUP
	mov AX, word ptr [BX]
	mov word ptr [_g_graphics_context.nClip_xmin], AX
	add AX, word ptr [BX+4]
	dec AX
	mov word ptr [_g_graphics_context.nClip_xmax], AX
	mov AX, word ptr [BX+2]
	mov word ptr [_g_graphics_context.nClip_ymin], AX
	add AX, word ptr [BX+6]
	dec AX
	mov word ptr [_g_graphics_context.nClip_ymax], AX
	assume ds:S233E_TEXT
	mov AX, word ptr [BX+4]
	shr AX,1h
	add AX, word ptr [BX]
	mov word ptr ES:[g_nViewportCenterX], AX
	mov AX, word ptr [BX+6]
	shr AX,1h
	add AX, word ptr [BX+2]
	mov word ptr ES:[g_nViewportCenterY], AX
	mov ES:byte ptr [g_bSkipFarEdgeCull], 0
	mov ES:byte ptr [g_bCamSetupResetFlag], 0
	add SI,4h
	mov DI,offset g_matXIn
	mov CX,3h
	rep movsw
	mov DS,DX
	mov AX,offset g_mat3x3ScratchRot
	push AX
	mov AX,offset g_matXIn
	push AX
	push CS
	call _r3d_build_rotation_matrix
	add SP,4h
	mov AL, byte ptr ds:[g_bScratchMatType]
	or AL,AL
	jnz @@composeViewRot	; scratch matrix type set: compose with actor rot
	mov AX,offset _g_mat3x3ViewRot
	push AX
	mov AX,offset g_camViewYaw
	push AX
	push CS
	call _r3d_build_rotation_matrix
	add SP,4h
	jmp short @@transposeView
@@composeViewRot:
	mov AX,offset g_mat3x3ActorRot
	push AX
	mov AX,offset g_camViewYaw
	push AX
	push CS
	call _r3d_build_rotation_matrix
	add SP,4h
	mov AX,offset _g_mat3x3ViewRot
	push AX
	mov AX,offset g_mat3x3ActorRot
	push AX
	mov AX,offset g_mat3x3ScratchRot
	push AX
	push CS
	call _r3d_matrix3x3_multiply
	add SP,6h
	mov AX,offset g_camViewYaw
	push AX
	mov AX,offset _g_mat3x3ViewRot
	push AX
	push CS
	call _r3d_matrix_to_euler
	add SP,4h
@@transposeView:
	mov AX,offset _g_mat3x3ViewRot
	push AX
	push CS
	call _r3d_matrix3x3_transpose
	add SP,2h
	pop DS
	pop DI
	pop SI
	pop BP
	retf

; ============================================================================
; _r3d_light_set_direction
;
; Sets the world-space directional-light vector from an elevation/azimuth pair by building a
; rotation matrix and rotating the +Y unit vector through it, caching the result in
; g_vec3LightDirWorld for mesh face shading.
;
; C equivalent:
;   void r3d_light_set_direction(short elevation, short azimuth)
;   {
;       /* Angle triple fed to the rotation-matrix builder: elevation about one
;          axis, no roll, azimuth about the third. */
;       g_matXIn = elevation;
;       g_matYIn = 0;
;       g_matZIn = azimuth;
;       r3d_build_rotation_matrix(&g_matXIn, g_mat3x3ScratchRot);
;
;       /* Rotate the +Y unit vector (0, 1.0, 0) in Q9 fixed point through the
;          freshly built matrix to obtain the world light direction. */
;       g_matXIn = 0;
;       g_matZIn = 0;
;       g_matYIn = 0x200;
;       r3d_mat3_xform_vec3_wrap(&g_matXIn, g_mat3x3ScratchRot, g_vec3LightDirWorld);
;   }
; ============================================================================
@elevation equ word ptr [bp+6]
@azimuth equ word ptr [bp+8]
	public _r3d_light_set_direction
_r3d_light_set_direction:
	push BP
	mov BP,SP
	push DS
	mov DX,CS
	mov ES,DX
	mov AX, @elevation
	mov word ptr ES:[g_matXIn], AX
	xor AX,AX
	mov word ptr ES:[g_matYIn], AX
	mov AX, @azimuth
	mov word ptr ES:[g_matZIn], AX
	mov DS,DX
	mov AX,offset g_mat3x3ScratchRot
	push AX
	mov AX,offset g_matXIn
	push AX
	push CS
	call _r3d_build_rotation_matrix
	add SP,4h
	xor AX,AX
	mov word ptr ds:[g_matXIn], AX
	mov word ptr ds:[g_matZIn], AX
	mov AX, 200h		; unit forward vector (+Y, Q9)
	mov word ptr ds:[g_matYIn], AX
	mov AX,offset g_vec3LightDirWorld
	push AX
	mov AX,offset g_mat3x3ScratchRot
	push AX
	mov AX,offset g_matXIn
	push AX
	push CS
	call _r3d_mat3_xform_vec3_wrap
	add SP,6h
	pop DS
	pop BP
	retf

; ============================================================================
; _r3d_build_rotation_matrix
;
; Builds a Q14 fixed-point 3x3 rotation matrix from a 3-component Euler-angle vector using
; sum/difference-of-angles cosine-table lookups, with identity and z-only fast paths.
;
; C equivalent:
;   /*
;    * g_awCosTable is a Q14 cosine table (0x4000 == 1.0), CS-resident, indexed
;    * by a 12-bit angle: idx = (angle >> 4) & 0xFFF over a 65536-unit circle.
;    * COS() folds that 12-bit index into the table's first quadrant. Adding
;    * 0xC000 to an angle before lookup yields sine (cos of angle - 90 degrees).
;    */
;   #define FIX_ONE   0x4000            /* Q14 unit (1.0) */
;
;   static short r3d_cos(unsigned angle)
;   {
;       unsigned idx = (angle >> 4) & 0xFFF;
;       if (idx & 0x800)
;           idx = 0x1000 - idx;
;       return g_awCosTable[idx];
;   }
;
;   /* half-Q14 cosine, used when two products are averaged into one entry */
;   #define HCOS(a)  (r3d_cos((unsigned)(a)) >> 1)
;   /* Q14 * Q14 -> Q14 (the asm keeps DX after two shl/rcl of the 32-bit product) */
;   #define FMUL(a, b)  (short)(((long)(a) * (short)(b)) >> 14)
;
;   int *r3d_build_rotation_matrix(EulerAngles *angles, Mat3x3 *out)
;   {
;       short *m = out->pM;
;       short ax = angles->pitch;      /* slot 0 */
;       short ay = angles->roll;       /* slot 1 */
;       short az = angles->yaw;        /* slot 2 */
;       short cz, sz, a, b, t;
;
;       /* classify: 0 = all zero (identity), 1 = only yaw set, else full 3-axis */
;       if (ax != 0)
;           out->bType = 3;
;       else if (ay != 0)
;           out->bType = 2;
;       else if (az != 0)
;           out->bType = 1;
;       else
;           out->bType = 0;
;
;       if (out->bType >= 2) {
;           cz = r3d_cos((unsigned)(ax + 0xC000));   /* sin(pitch) */
;           m[5] = cz;
;
;           a = HCOS(ay - az) + HCOS(ay + az);       /* cos(roll)cos(yaw) */
;           b = HCOS(ay - az) - HCOS(ay + az);       /* sin(roll)sin(yaw) */
;           m[0] = a - FMUL(cz, b);
;           m[7] = b - FMUL(cz, a);
;
;           a = HCOS(az + ay + 0xC000) + HCOS(az - ay + 0xC000);
;           b = HCOS(ay + az + 0xC000) + HCOS(ay - az + 0xC000);
;           m[1] = FMUL(cz, b) + a;
;           m[6] = FMUL(cz, a) + b;
;
;           m[4] = HCOS(ax - az) + HCOS(ax + az);
;           m[8] = HCOS(ax - ay) + HCOS(ax + ay);
;
;           t = HCOS(ay + ax + 0xC000) + HCOS(ay - ax + 0xC000);
;           m[2] = -t;
;           t = HCOS(az + ax + 0xC000) + HCOS(az - ax + 0xC000);
;           m[3] = -t;
;       } else if (out->bType == 1) {
;           /* pure rotation about yaw */
;           cz = r3d_cos((unsigned)az);              /* cos(yaw) */
;           m[0] = cz;
;           m[4] = cz;
;           sz = r3d_cos((unsigned)(az + 0xC000));   /* sin(yaw) */
;           m[1] = sz;
;           m[3] = -sz;
;           m[2] = 0;
;           m[5] = 0;
;           m[6] = 0;
;           m[7] = 0;
;           m[8] = FIX_ONE;
;       } else {
;           /* identity */
;           m[0] = FIX_ONE;  m[4] = FIX_ONE;  m[8] = FIX_ONE;
;           m[1] = 0;  m[2] = 0;  m[3] = 0;
;           m[5] = 0;  m[6] = 0;  m[7] = 0;
;       }
;       return m;
;   }
; ============================================================================
@angles equ word ptr [bp+6]
@matrix equ word ptr [bp+8]
	public _r3d_build_rotation_matrix
_r3d_build_rotation_matrix:
	push BP
	mov BP,SP
	push DI
	push SI
	mov SI, @angles
	mov DI, @matrix
	mov CL,3h
	mov AX, word ptr [SI]
	or AX,AX
	jnz @@typeResolved	; X angle set: type 3
	dec CL
	mov AX, word ptr [SI+2]
	or AX,AX
	jnz @@typeResolved	; Y angle set: type 2
	dec CL
	mov AX, word ptr [SI+4]
	or AX,AX
	jnz @@typeResolved	; Z angle set: type 1
	dec CL
@@typeResolved:
	mov AL,CL
	mov byte ptr [DI].mType, AL
	cmp AL,MAT3T_ZROT
	jle @@zrotOrIdentity	; type <= 1: Z-only or identity
	jmp bld_rot_full_matrix
@@zrotOrIdentity:
	jz @@zrotOnly		; type == 1: pure Z rotation
	mov AX, Q14_ONE		; 1.0 on the matrix diagonal (identity)
	mov word ptr [DI], AX
	mov word ptr [DI+8], AX
	mov word ptr [DI+16], AX
	xor AX,AX
	mov word ptr [DI+2], AX
	mov word ptr [DI+4], AX
	mov word ptr [DI+6], AX
	mov word ptr [DI+10], AX
	mov word ptr [DI+12], AX
	mov word ptr [DI+14], AX
	jmp bld_rot_done
@@zrotOnly:
	push BX
	mov AX, word ptr [SI+4]
	COS
	pop BX
	mov word ptr [DI], AX
	mov word ptr [DI+8], AX
	push BX
	mov AX, word ptr [SI+4]
	add AX, 0c000h
	COS
	pop BX
	mov word ptr [DI+2], AX
	neg AX
	mov word ptr [DI+6], AX
	xor AX,AX
	mov word ptr [DI+4], AX
	mov word ptr [DI+10], AX
	mov word ptr [DI+12], AX
	mov word ptr [DI+14], AX
	mov AX, Q14_ONE		; 1.0 on the matrix diagonal (identity)
	mov word ptr [DI+16], AX
	jmp bld_rot_done
bld_rot_full_matrix:
	push BX
	mov AX, word ptr [SI]
	add AX, 0c000h
	COS
	pop BX
	mov word ptr [DI+10], AX
	mov BP,AX
	mov AX, word ptr [SI+2]
	sub AX, word ptr [SI+4]
	push BX
	COS
	pop BX
	sar AX,1h
	mov BX,AX
	mov AX, word ptr [SI+2]
	add AX, word ptr [SI+4]
	push BX
	COS
	pop BX
	sar AX,1h
	add BX,AX
	mov AX, word ptr [SI+2]
	sub AX, word ptr [SI+4]
	push BX
	COS
	pop BX
	sar AX,1h
	mov CX,AX
	mov AX, word ptr [SI+2]
	add AX, word ptr [SI+4]
	push BX
	COS
	pop BX
	sar AX,1h
	sub CX,AX
	mov AX,BP
	imul CX
	Q14NORM
	mov AX,BX
	sub AX,DX
	mov word ptr [DI], AX
	mov AX,BP
	imul BX
	Q14NORM
	mov AX,CX
	sub AX,DX
	mov word ptr [DI+14], AX
	mov AX, word ptr [SI+4]
	add AX, word ptr [SI+2]
	push BX
	add AX, 0c000h
	COS
	pop BX
	sar AX,1h
	mov BX,AX
	mov AX, word ptr [SI+4]
	sub AX, word ptr [SI+2]
	push BX
	add AX, 0c000h
	COS
	pop BX
	sar AX,1h
	add BX,AX
	mov AX, word ptr [SI+2]
	add AX, word ptr [SI+4]
	push BX
	add AX, 0c000h
	COS
	pop BX
	sar AX,1h
	mov CX,AX
	mov AX, word ptr [SI+2]
	sub AX, word ptr [SI+4]
	push BX
	add AX, 0c000h
	COS
	pop BX
	sar AX,1h
	add CX,AX
	mov AX,BP
	imul CX
	Q14NORM
	add DX,BX
	mov word ptr [DI+2], DX
	mov AX,BP
	imul BX
	Q14NORM
	add DX,CX
	mov word ptr [DI+12], DX
	mov AX, word ptr [SI]
	add AX, word ptr [SI+4]
	push BX
	COS
	pop BX
	sar AX,1h
	mov CX,AX
	mov AX, word ptr [SI]
	sub AX, word ptr [SI+4]
	push BX
	COS
	pop BX
	sar AX,1h
	add AX,CX
	mov word ptr [DI+8], AX
	mov AX, word ptr [SI]
	add AX, word ptr [SI+2]
	push BX
	COS
	pop BX
	sar AX,1h
	mov CX,AX
	mov AX, word ptr [SI]
	sub AX, word ptr [SI+2]
	push BX
	COS
	pop BX
	sar AX,1h
	add AX,CX
	mov word ptr [DI+16], AX
	mov AX, word ptr [SI+2]
	sub AX, word ptr [SI]
	push BX
	add AX, 0c000h
	COS
	pop BX
	sar AX,1h
	mov CX,AX
	mov AX, word ptr [SI+2]
	add AX, word ptr [SI]
	push BX
	add AX, 0c000h
	COS
	pop BX
	sar AX,1h
	add AX,CX
	neg AX
	mov word ptr [DI+4], AX
	mov AX, word ptr [SI+4]
	sub AX, word ptr [SI]
	push BX
	add AX, 0c000h
	COS
	pop BX
	sar AX,1h
	mov CX,AX
	mov AX, word ptr [SI+4]
	add AX, word ptr [SI]
	push BX
	add AX, 0c000h
	COS
	pop BX
	sar AX,1h
	add AX,CX
	neg AX
	mov word ptr [DI+6], AX
bld_rot_done:
	mov AX,DI
	pop SI
	pop DI
	pop BP
	retf

; ============================================================================
; _r3d_matrix_to_euler
;
; Extracts Euler angles (x,y,z in 16-bit brad units) from a 3x3 rotation matrix via table-driven
; asin/atan2, with a +/-90-degree gimbal-lock fallback.
;
; C equivalent:
;   short far *r3d_matrix_to_euler(Mat3x3 far *matrix, short far *outXyz)
;   {
;       int angleX;
;
;       /* x = asin(m[1][2]); table returns a signed brad angle */
;       angleX = r3d_tbl_asin(matrix->pM[5]);
;       outXyz[0] = angleX;
;
;       if (angleX < 0)
;           angleX = -angleX;
;
;       if (angleX == 0x4000) {
;           /* Gimbal lock at +/-90 degrees: fold y and z into one atan2 */
;           outXyz[1] = 0;
;           outXyz[2] = r3d_tbl_atan2(matrix->pM[0], matrix->pM[1]);
;       } else {
;           outXyz[1] = r3d_tbl_atan2(matrix->pM[8], -matrix->pM[2]);
;           outXyz[2] = r3d_tbl_atan2(matrix->pM[4], -matrix->pM[3]);
;       }
;
;       return outXyz;
;   }
; ============================================================================
@matrix3x3 equ word ptr [bp+6]
@out_xyz equ word ptr [bp+8]
	public _r3d_matrix_to_euler
_r3d_matrix_to_euler:
	push BP
	mov BP,SP
	push SI
	push DI
	mov SI, @matrix3x3
	mov DI, @out_xyz
	mov AX, word ptr [SI+10]
	push AX
	push CS
	call _r3d_tbl_asin
	add SP,2h
	mov word ptr [DI], AX
	cmp AX,0h
	jge @@pitchAbs		; pitch already >= 0
	neg AX
@@pitchAbs:
	cmp AX, ANG_90DEG	; gimbal-lock test: |pitch| at 90 degrees
	jnz @@noGimbal
	xor AX,AX
	mov word ptr [DI+2], AX
	mov AX, word ptr [SI+2]
	push AX
	mov AX, word ptr [SI]
	push AX
	push CS
	call _r3d_tbl_atan2
	add SP,4h
	mov word ptr [DI+4], AX
	jmp short @@done
@@noGimbal:
	mov AX, word ptr [SI+4]
	neg AX
	push AX
	mov AX, word ptr [SI+16]
	push AX
	push CS
	call _r3d_tbl_atan2
	add SP,4h
	mov word ptr [DI+2], AX
	mov AX, word ptr [SI+6]
	neg AX
	push AX
	mov AX, word ptr [SI+8]
	push AX
	push CS
	call _r3d_tbl_atan2
	add SP,4h
	mov word ptr [DI+4], AX
@@done:
	mov AX,DI
	pop DI
	pop SI
	pop BP
	retf

; ============================================================================
; _r3d_matrix3x3_transpose
;
; Transposes a 3x3 short matrix in place by swapping its three off-diagonal pairs, and returns
; the matrix pointer.
;
; C equivalent:
;   Mat3x3 far *r3d_matrix3x3_transpose(Mat3x3 far *m)
;   {
;       short tmp;
;
;       tmp = m->pM[1];
;       m->pM[1] = m->pM[3];
;       m->pM[3] = tmp;
;
;       tmp = m->pM[2];
;       m->pM[2] = m->pM[6];
;       m->pM[6] = tmp;
;
;       tmp = m->pM[5];
;       m->pM[5] = m->pM[7];
;       m->pM[7] = tmp;
;
;       return m;
;   }
; ============================================================================
@m equ word ptr [bp+6]
	public _r3d_matrix3x3_transpose
_r3d_matrix3x3_transpose:
	push BP
	mov BP,SP
	mov BX, @m
	mov AX, word ptr [BX+2]
	xchg word ptr [BX+6], AX
	mov word ptr [BX+2], AX
	mov AX, word ptr [BX+4]
	xchg word ptr [BX+12], AX
	mov word ptr [BX+4], AX
	mov AX, word ptr [BX+10]
	xchg word ptr [BX+14], AX
	mov word ptr [BX+10], AX
	mov AX,BX
	pop BP
	retf

; ============================================================================
; _r3d_matrix3x3_multiply
;
; Multiplies two Q14 fixed-point 3x3 matrices (pMatOut = pMatA * pMatB), dispatching on each
; operand's type byte so identity and 2D z-rotation cases skip work.
;
; C equivalent:
;   #define MAT3_Q 14
;   #define MAT3_ONE 0x4000
;
;   #define MAT3_IDENTITY 0
;   #define MAT3_ZROT     1
;   #define MAT3_FULL     3
;
;   typedef struct {
;       short m[9];
;       unsigned char type;
;   } Mat3x3;
;
;   static short mat3_fix(long acc)
;   {
;       return (short)(acc >> MAT3_Q);
;   }
;
;   Mat3x3 far *r3d_matrix3x3_multiply(Mat3x3 far *pMatA, Mat3x3 far *pMatB,
;                                      Mat3x3 far *pMatOut)
;   {
;       short far *a = pMatA->m;
;       short far *b = pMatB->m;
;       short far *o = pMatOut->m;
;       int i;
;
;       if (pMatA->type == MAT3_IDENTITY || pMatB->type == MAT3_IDENTITY) {
;           Mat3x3 far *src;
;
;           if (pMatA->type == MAT3_IDENTITY)
;               src = pMatB;
;           else
;               src = pMatA;
;
;           pMatOut->type = src->type;
;           for (i = 0; i < 9; i++)
;               pMatOut->m[i] = src->m[i];
;           return pMatOut;
;       }
;
;       if (pMatA->type == MAT3_ZROT) {
;           if (pMatB->type == MAT3_ZROT) {
;               o[0] = mat3_fix((long)a[0] * b[0] + (long)a[1] * b[3]);
;               o[1] = mat3_fix((long)a[0] * b[1] + (long)a[1] * b[4]);
;               o[3] = mat3_fix((long)a[3] * b[0] + (long)a[4] * b[3]);
;               o[4] = mat3_fix((long)a[3] * b[1] + (long)a[4] * b[4]);
;               o[2] = 0;
;               o[5] = 0;
;               o[6] = 0;
;               o[7] = 0;
;               o[8] = MAT3_ONE;
;               pMatOut->type = MAT3_ZROT;
;           } else {
;               o[0] = mat3_fix((long)a[0] * b[0] + (long)a[1] * b[3]);
;               o[1] = mat3_fix((long)a[0] * b[1] + (long)a[1] * b[4]);
;               o[2] = mat3_fix((long)a[0] * b[2] + (long)a[1] * b[5]);
;               o[3] = mat3_fix((long)a[3] * b[0] + (long)a[4] * b[3]);
;               o[4] = mat3_fix((long)a[3] * b[1] + (long)a[4] * b[4]);
;               o[5] = mat3_fix((long)a[3] * b[2] + (long)a[4] * b[5]);
;               o[6] = b[6];
;               o[7] = b[7];
;               o[8] = b[8];
;               pMatOut->type = MAT3_FULL;
;           }
;       } else if (pMatB->type == MAT3_ZROT) {
;           o[0] = mat3_fix((long)a[0] * b[0] + (long)a[1] * b[3]);
;           o[1] = mat3_fix((long)a[0] * b[1] + (long)a[1] * b[4]);
;           o[2] = a[2];
;           o[3] = mat3_fix((long)a[3] * b[0] + (long)a[4] * b[3]);
;           o[4] = mat3_fix((long)a[3] * b[1] + (long)a[4] * b[4]);
;           o[5] = a[5];
;           o[6] = mat3_fix((long)a[6] * b[0] + (long)a[7] * b[3]);
;           o[7] = mat3_fix((long)a[6] * b[1] + (long)a[7] * b[4]);
;           o[8] = a[8];
;           pMatOut->type = MAT3_FULL;
;       } else {
;           o[0] = mat3_fix((long)a[0]*b[0] + (long)a[1]*b[3] + (long)a[2]*b[6]);
;           o[1] = mat3_fix((long)a[0]*b[1] + (long)a[1]*b[4] + (long)a[2]*b[7]);
;           o[2] = mat3_fix((long)a[0]*b[2] + (long)a[1]*b[5] + (long)a[2]*b[8]);
;           o[3] = mat3_fix((long)a[3]*b[0] + (long)a[4]*b[3] + (long)a[5]*b[6]);
;           o[4] = mat3_fix((long)a[3]*b[1] + (long)a[4]*b[4] + (long)a[5]*b[7]);
;           o[5] = mat3_fix((long)a[3]*b[2] + (long)a[4]*b[5] + (long)a[5]*b[8]);
;           o[6] = mat3_fix((long)a[6]*b[0] + (long)a[7]*b[3] + (long)a[8]*b[6]);
;           o[7] = mat3_fix((long)a[6]*b[1] + (long)a[7]*b[4] + (long)a[8]*b[7]);
;           o[8] = mat3_fix((long)a[6]*b[2] + (long)a[7]*b[5] + (long)a[8]*b[8]);
;           pMatOut->type = MAT3_FULL;
;       }
;       return pMatOut;
;   }
; ============================================================================
@pMatA equ word ptr [bp+6]
@pMatB equ word ptr [bp+8]
@pMatOut equ word ptr [bp+10]
	public _r3d_matrix3x3_multiply
_r3d_matrix3x3_multiply:
	push BP
	mov BP,SP
	push DI
	push SI
	mov BX, @pMatA
	mov SI, @pMatB
	mov DI, @pMatOut
	mov AL, byte ptr [BX].mType
	mov DL,AL
	mov AL, byte ptr [SI].mType
	mov AH,DL
	or AH,AH
	jz @@copyIdentity	; A is identity: copy B through
	or AL,AL
	jnz @@dispatchMul
	mov SI,BX		; B is identity: copy A through
	mov AL,AH
@@copyIdentity:
	mov byte ptr [DI].mType, AL
	push DI
	push ES
	mov CX,9h
	mov DX,DS
	mov ES,DX
	rep movsw
	pop ES
	pop DI
	jmp @@done
@@dispatchMul:
	dec AH
	jnz @@aFull		; A != ZROT (must be FULL)
	dec AL
	jz @@zrotZrot		; A ZROT, B ZROT
	jmp @@zrotTimesFull	; A ZROT, B FULL
@@aFull:
	dec AL
	jnz @@bothFull		; B != ZROT: full * full
	jmp @@fullTimesZrot	; A FULL, B ZROT
@@bothFull:
	jmp @@fullMul
@@zrotZrot:
	MULSEED [BX], [SI]
	MULACC [BX+2], [SI+6]
	Q14NORM
	mov AX,DX
	mov word ptr [DI], AX
	MULSEED [BX], [SI+2]
	MULACC [BX+2], [SI+8]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+2], AX
	MULSEED [BX+6], [SI]
	MULACC [BX+8], [SI+6]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+6], AX
	MULSEED [BX+6], [SI+2]
	MULACC [BX+8], [SI+8]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+8], AX
	xor AX,AX
	mov word ptr [DI+4], AX
	mov word ptr [DI+10], AX
	mov word ptr [DI+12], AX
	mov word ptr [DI+14], AX
	mov AX, Q14_ONE		; 1.0 on the matrix diagonal (z-rot)
	mov word ptr [DI+16], AX
	mov AX,MAT3T_ZROT
	mov byte ptr [DI].mType, AL
	jmp @@done
@@fullMul:
	MULSEED [BX], [SI]
	MULACC2 [BX+2], [SI+6]
	MULACC [BX+4], [SI+12]
	Q14NORM
	mov AX,DX
	mov word ptr [DI], AX
	MULSEED [BX], [SI+2]
	MULACC2 [BX+2], [SI+8]
	MULACC [BX+4], [SI+14]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+2], AX
	MULSEED [BX], [SI+4]
	MULACC2 [BX+2], [SI+10]
	MULACC [BX+4], [SI+16]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+4], AX
	MULSEED [BX+6], [SI]
	MULACC2 [BX+8], [SI+6]
	MULACC [BX+10], [SI+12]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+6], AX
	MULSEED [BX+6], [SI+2]
	MULACC2 [BX+8], [SI+8]
	MULACC [BX+10], [SI+14]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+8], AX
	MULSEED [BX+6], [SI+4]
	MULACC2 [BX+8], [SI+10]
	MULACC [BX+10], [SI+16]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+10], AX
	MULSEED [BX+12], [SI]
	MULACC2 [BX+14], [SI+6]
	MULACC [BX+16], [SI+12]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+12], AX
	MULSEED [BX+12], [SI+2]
	MULACC2 [BX+14], [SI+8]
	MULACC [BX+16], [SI+14]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+14], AX
	MULSEED [BX+12], [SI+4]
	MULACC2 [BX+14], [SI+10]
	MULACC [BX+16], [SI+16]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+16], AX
	mov AX,MAT3T_FULL
	mov byte ptr [DI].mType, AL
	jmp @@done
@@zrotTimesFull:
	MULSEED [BX], [SI]
	MULACC [BX+2], [SI+6]
	Q14NORM
	mov AX,DX
	mov word ptr [DI], AX
	MULSEED [BX], [SI+2]
	MULACC [BX+2], [SI+8]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+2], AX
	MULSEED [BX], [SI+4]
	MULACC [BX+2], [SI+10]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+4], AX
	MULSEED [BX+6], [SI]
	MULACC [BX+8], [SI+6]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+6], AX
	MULSEED [BX+6], [SI+2]
	MULACC [BX+8], [SI+8]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+8], AX
	MULSEED [BX+6], [SI+4]
	MULACC [BX+8], [SI+10]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+10], AX
	mov AX, word ptr [SI+12]
	mov word ptr [DI+12], AX
	mov AX, word ptr [SI+14]
	mov word ptr [DI+14], AX
	mov AX, word ptr [SI+16]
	mov word ptr [DI+16], AX
	mov AX,MAT3T_FULL
	mov byte ptr [DI].mType, AL
	jmp @@done
@@fullTimesZrot:
	MULSEED [BX], [SI]
	MULACC [BX+2], [SI+6]
	Q14NORM
	mov AX,DX
	mov word ptr [DI], AX
	MULSEED [BX], [SI+2]
	MULACC [BX+2], [SI+8]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+2], AX
	mov AX, word ptr [BX+4]
	mov word ptr [DI+4], AX
	MULSEED [BX+6], [SI]
	MULACC [BX+8], [SI+6]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+6], AX
	MULSEED [BX+6], [SI+2]
	MULACC [BX+8], [SI+8]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+8], AX
	mov AX, word ptr [BX+10]
	mov word ptr [DI+10], AX
	MULSEED [BX+12], [SI]
	MULACC [BX+14], [SI+6]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+12], AX
	MULSEED [BX+12], [SI+2]
	MULACC [BX+14], [SI+8]
	Q14NORM
	mov AX,DX
	mov word ptr [DI+14], AX
	mov AX, word ptr [BX+16]
	mov word ptr [DI+16], AX
	mov AX,MAT3T_FULL
	mov byte ptr [DI].mType, AL
@@done:
	mov AX,DI
	pop SI
	pop DI
	pop BP
	retf

; ============================================================================
; _r3d_matrix3x3_transform_vec3
;
; Transforms a 3-component fixed-point vector by a 3x3 Q14 matrix, with fast paths selected by
; the matrix's type byte (0=copy, 1=2x2 planar rotation keeping Z, >=2=full 3x3).
;
; C equivalent:
;   void r3d_matrix3x3_transform_vec3(short *v, Mat3x3 *m, short *out)
;   {
;       if (m->bType < 2) {
;           if (m->bType == 1) {
;               out[0] = (short)(((long)m->pM[0] * v[0] +
;                                 (long)m->pM[3] * v[1]) >> 14);
;               out[1] = (short)(((long)m->pM[1] * v[0] +
;                                 (long)m->pM[4] * v[1]) >> 14);
;               out[2] = v[2];
;           } else {
;               out[0] = v[0];
;               out[1] = v[1];
;               out[2] = v[2];
;           }
;       } else {
;           out[0] = (short)(((long)m->pM[0] * v[0] +
;                             (long)m->pM[3] * v[1] +
;                             (long)m->pM[6] * v[2]) >> 14);
;           out[1] = (short)(((long)m->pM[1] * v[0] +
;                             (long)m->pM[4] * v[1] +
;                             (long)m->pM[7] * v[2]) >> 14);
;           out[2] = (short)(((long)m->pM[2] * v[0] +
;                             (long)m->pM[5] * v[1] +
;                             (long)m->pM[8] * v[2]) >> 14);
;       }
;   }
; ============================================================================
	public _r3d_matrix3x3_transform_vec3
_r3d_matrix3x3_transform_vec3:
	push BP
	push SI
	push DI
	mov SI,AX
	mov DI,CX
	mov AL, byte ptr [BX].mType
	cmp AL,MAT3T_ZROT
	jg @@fullXform		; type >= 2: full 3x3
	jz @@planarXform	; type == 1: 2x2 planar rotation
	push ES
	mov AX,DS
	mov ES,AX
	movsw
	movsw
	movsw
	pop ES
	jmp @@done
@@planarXform:
	mov AX, word ptr [SI]
	mov DX,AX
	mov AX, word ptr [BX]
	imul DX
	mov CX,AX
	mov BP,DX
	mov AX, word ptr [SI+2]
	mov DX,AX
	mov AX, word ptr [BX+6]
	imul DX
	add AX,CX
	adc DX,BP
	Q14NORM
	mov AX,DX
	mov word ptr [DI], AX
	mov AX, word ptr [SI]
	mov DX,AX
	mov AX, word ptr [BX+2]
	imul DX
	mov CX,AX
	mov BP,DX
	mov AX, word ptr [SI+2]
	mov DX,AX
	mov AX, word ptr [BX+8]
	imul DX
	add AX,CX
	adc DX,BP
	Q14NORM
	mov AX,DX
	mov word ptr [DI+2], AX
	mov AX, word ptr [SI+4]
	mov word ptr [DI+4], AX
	jmp @@done
@@fullXform:
	mov AX, word ptr [SI]
	mov DX,AX
	mov AX, word ptr [BX]
	imul DX
	mov CX,AX
	mov BP,DX
	mov AX, word ptr [SI+2]
	mov DX,AX
	mov AX, word ptr [BX+6]
	imul DX
	add CX,AX
	adc BP,DX
	mov AX, word ptr [SI+4]
	mov DX,AX
	mov AX, word ptr [BX+12]
	imul DX
	add AX,CX
	adc DX,BP
	Q14NORM
	mov AX,DX
	mov word ptr [DI], AX
	mov AX, word ptr [SI]
	mov DX,AX
	mov AX, word ptr [BX+2]
	imul DX
	mov CX,AX
	mov BP,DX
	mov AX, word ptr [SI+2]
	mov DX,AX
	mov AX, word ptr [BX+8]
	imul DX
	add CX,AX
	adc BP,DX
	mov AX, word ptr [SI+4]
	mov DX,AX
	mov AX, word ptr [BX+14]
	imul DX
	add AX,CX
	adc DX,BP
	Q14NORM
	mov AX,DX
	mov word ptr [DI+2], AX
	mov AX, word ptr [SI]
	mov DX,AX
	mov AX, word ptr [BX+4]
	imul DX
	mov CX,AX
	mov BP,DX
	mov AX, word ptr [SI+2]
	mov DX,AX
	mov AX, word ptr [BX+10]
	imul DX
	add CX,AX
	adc BP,DX
	mov AX, word ptr [SI+4]
	mov DX,AX
	mov AX, word ptr [BX+16]
	imul DX
	add AX,CX
	adc DX,BP
	Q14NORM
	mov AX,DX
	mov word ptr [DI+4], AX
@@done:
	pop DI
	pop SI
	pop BP
	ret

; ============================================================================
; _r3d_mat3_xform_vec3_wrap
;
; Far-call trampoline that forwards (vec, matrix, outVec) to the near, register-convention
; matrix3x3_transform_vec3 and returns outVec for inline chaining.
;
; C equivalent:
;   unsigned char far *r3d_mat3_xform_vec3_wrap(unsigned char far *vec,
;                                               unsigned char far *matrix,
;                                               unsigned char far *outVec)
;   {
;       r3d_matrix3x3_transform_vec3(vec, matrix, outVec);
;       return outVec;
;   }
; ============================================================================
@vec equ word ptr [bp+6]
@matrix equ word ptr [bp+8]
@out_vec equ word ptr [bp+10]
	public _r3d_mat3_xform_vec3_wrap
_r3d_mat3_xform_vec3_wrap:
	push BP
	mov BP,SP
	mov AX, @vec
	mov BX, @matrix
	mov CX, @out_vec
	call _r3d_matrix3x3_transform_vec3
	mov AX, @out_vec
	pop BP
	retf

; ============================================================================
; _r3d_polygon_resolve_shade_color
;
; Resolves and stores a polygon's outline/fill draw-color pair, optionally applying dot3 light-
; ramp shading and a palette remap.
;
; C equivalent (register-convention MODEL, not a real stack-arg prototype: poly arrives in ES:DI
; and normalTable in BP -- see Note; the parameter list below is a readability stand-in):
;   void r3d_polygon_resolve_shade_color(
;       unsigned char far *poly, short far *normalTable)
;   {
;       unsigned char renderState;
;       unsigned char flags;
;       unsigned char outlineColor;
;       unsigned char fillColor;
;       unsigned char material;
;
;       renderState = g_graphics_context.bGfxRenderStateFlag;
;       if (renderState != 0) {
;           outlineColor = poly[1];
;           fillColor    = poly[2];
;       } else {
;           outlineColor = poly[3];
;           fillColor    = poly[4];
;       }
;
;       flags = poly[0];
;       g_graphics_context.bGfx_fill_enabled = (flags & 0x80) ? 1 : 0;
;
;       if (g_graphics_context.bGfx_fill_enabled && (flags & 0x20) &&
;           renderState != 0 && g_pFaceMaterialTable != 0) {
;
;           material = *(unsigned char far *)(g_pFaceMaterialTable + fillColor);
;           if (material != 0 && material <= 8) {
;               short far *normal;
;               long dot;
;               int shade;
;               unsigned char ramped;
;
;               normal = (short far *)(normalTable + (unsigned)poly[5] * 3);
;               g_matXIn2 = normal[0];
;               g_matYIn2 = normal[1];
;               g_matZIn2 = normal[2];
;               if (g_bPolyNormalFlipped) {
;                   g_matXIn2 = -g_matXIn2;
;                   g_matYIn2 = -g_matYIn2;
;                   g_matZIn2 = -g_matZIn2;
;               }
;
;               dot = r3d_dot3_long(&g_matXIn2, g_vec3LightDirObj);
;               shade = (int)(dot >> 16);
;               if (shade == 16)
;                   shade = 15;
;               shade += 16;
;
;               ramped = g_abLightingLut[((material - 1) << 5) + shade];
;               ramped += fillColor;
;               if (outlineColor == fillColor)
;                   outlineColor = ramped;
;               fillColor = ramped;
;           }
;       }
;
;       if (g_pColorRemapTable != 0) {
;           outlineColor = g_pColorRemapTable[outlineColor];
;           fillColor    = g_pColorRemapTable[fillColor];
;       }
;
;       g_graphics_context.bGfx_outline_color = outlineColor;
;       g_graphics_context.bGfx_fill_color    = fillColor;
;   }
; ============================================================================
	public _r3d_polygon_resolve_shade_color
_r3d_polygon_resolve_shade_color:
	mov DL, SS:byte ptr [_g_graphics_context.bGfxRenderStateFlag]
	or DL,DL
	jz @@nightColors
	mov CL, ES:byte ptr [DI].fDayOutline
	mov CH, ES:byte ptr [DI].fDayFill
	jmp short @@haveColors
@@nightColors:
	mov CL, ES:byte ptr [DI].fNightOutline
	mov CH, ES:byte ptr [DI].fNightFill
@@haveColors:
	xor AH,AH
	mov AL, ES:byte ptr [DI].fFlags
	test AL,80h
	jz @@fillFlagSet
	inc AH
@@fillFlagSet:
	mov SS:byte ptr [_g_graphics_context.bGfx_fill_enabled], AH
	or AH,AH
	jnz @@fillEnabled
	jmp shade_store_colors
@@fillEnabled:
	test AL,MESH_FLAG_SIMPLE
	jnz @@notSimple
	jmp shade_store_colors
@@notSimple:
	or DL,DL
	jnz @@lit
	jmp shade_store_colors
@@lit:
	mov AX, word ptr ds:[g_pFaceMaterialTable]
	or AX,AX
	jz shade_store_colors
	mov BX,AX
	mov AL,CH
	xor AH,AH
	add BX,AX
	mov AL, SS:byte ptr [BX]
	cmp AX,0h

; ============================================================================
; _r3d_polygon_resolve_shade_color_lit
;
; Per-face Gouraud-style shader: dots the face normal against the object-space light vector
; (g_vec3LightDirObj), clamps to
; a 0..16 shade, looks up a base palette color in the 32-entry-per-material lighting LUT, biases
; and optionally palette-remaps it, then writes the outline/fill color pair into the graphics
; context. This label is a FALL-THROUGH continuation of r3d_polygon_resolve_shade_color (never
; called directly; execution reaches it only by falling off the end of that routine, and it
; shares that routine's single ret). The gate register AX arriving here is the per-face MATERIAL
; id (the sibling's C block at 0x1220 correctly calls it `material`), loaded from the material
; table at g_pFaceMaterialTable indexed by fill color.
;
; C equivalent:
;   void near r3d_polygon_resolve_shade_color_lit(int material, unsigned char far *pFace,
;                                       int far *pNormalTable, unsigned char outlineColor,
;                                       unsigned char fillColor)
;   {
;       int shade;
;       unsigned char litColor;
;       int far *pNormal;
;
;       if (material > 0 && material <= 8) {
;           pNormal = (int far *)((char far *)pNormalTable + pFace[5] * 6);
;           g_matXIn2 = pNormal[0];
;           g_matYIn2 = pNormal[1];
;           g_matZIn2 = pNormal[2];
;
;           if (g_bPolyNormalFlipped) {
;               g_matXIn2 = -g_matXIn2;
;               g_matYIn2 = -g_matYIn2;
;               g_matZIn2 = -g_matZIn2;
;           }
;
;           shade = (int)(r3d_dot3_long(&g_matXIn2, g_vec3LightDirObj) >> 16);
;           if (shade == 16)
;               shade = 15;
;           shade += 16;
;
;           litColor = g_abLightingLut[(material - 1) * 32 + shade] + fillColor;
;
;           if (outlineColor == fillColor)
;               outlineColor = litColor;
;           fillColor = litColor;
;       }
;
;       if (g_pColorRemapTable != 0) {
;           outlineColor = g_pColorRemapTable[outlineColor];
;           fillColor = g_pColorRemapTable[fillColor];
;       }
;
;       g_graphics_context.bGfx_outline_color = outlineColor;
;       g_graphics_context.bGfx_fill_color = fillColor;
;   }
; ============================================================================
	public _r3d_polygon_resolve_shade_color_lit
_r3d_polygon_resolve_shade_color_lit:
	jle shade_store_colors
	cmp AX,8h
	jg shade_store_colors
	push CX
	push AX
	mov BL, ES:byte ptr [DI].fNrmVert
	xor BH,BH
	shl BX,1h
	VROWADDR
	mov AX, ES:word ptr [BX].vX
	mov word ptr ds:[g_matXIn2], AX
	mov AX, ES:word ptr [BX].vY
	mov word ptr ds:[g_matYIn2], AX
	mov AX, ES:word ptr [BX].vZ
	mov word ptr ds:[g_matZIn2], AX
	cmp byte ptr ds:[g_bPolyNormalFlipped], 0
	jz @@notFlipped
	mov BX,offset g_matXIn2
	neg word ptr [BX]
	neg word ptr [BX+2]
	neg word ptr [BX+4]
@@notFlipped:
	mov AX,offset g_matXIn2
	mov BX,offset g_vec3LightDirObj
	call _r3d_dot3_long
	mov AX,DX
	cmp AX,10h
	jnz @@shadeOk
	dec AX
@@shadeOk:
	add AX,10h
	pop BX
	dec BX
	mov CL,5h
	shl BX,CL
	add BX,AX
	mov AL, byte ptr [BX+g_abLightingLut]
	pop CX
	add AL,CH
	cmp CL,CH
	jnz @@fillOnly
	mov CL,AL
@@fillOnly:
	mov CH,AL
shade_store_colors:				; shared tail: reached from both halves (crosses public boundary, stays global)
	mov AX, word ptr ds:[g_pColorRemapTable]
	or AX,AX
	jz @@storeColors
	mov BL,CL
	xor BH,BH
	add BX,AX
	mov CL, SS:byte ptr [BX]
	mov BL,CH
	xor BH,BH
	add BX,AX
	mov CH, SS:byte ptr [BX]
@@storeColors:
	mov SS:byte ptr [_g_graphics_context.bGfx_outline_color], CL
	mov SS:byte ptr [_g_graphics_context.bGfx_fill_color], CH
	ret

; ============================================================================
; _r3d_polygon_submit_to_rasterizer
;
; Copies the current mesh polygon's projected screen X/Y vertices into the graphics-context
; polygon buffers and hands the polygon to the far sky/floor draw dispatcher.
;
; C equivalent:
;   void r3d_polygon_submit_to_rasterizer(void)
;   {
;       int n;
;       int i;
;
;       n = g_nMeshPolyVertexCount;
;       if (n == 0)
;           return;
;
;       g_graphics_context.nPolygonClipVertexCount = n;
;
;       for (i = 0; i < n; i++)
;           g_graphics_context.pPolygonX[i] = g_aPolyInX[i];
;       for (i = 0; i < n; i++)
;           g_graphics_context.pPolygonY[i] = g_aPolyInY[i];
;
;       sky_polygon_draw_dispatch(g_graphics_context.nPolygonClipVertexCount,
;                                 g_graphics_context.pPolygonX,
;                                 g_graphics_context.pPolygonY);
;   }
; ============================================================================
	public _r3d_polygon_submit_to_rasterizer
_r3d_polygon_submit_to_rasterizer:
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	mov CX,AX
	jcxz @@done
	mov word ptr SS:[_g_graphics_context.nPolygonClipVertexCount], AX
	push SI
	push DI
	push DS
	push ES
	mov DX,SS
	mov ES,DX
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	mov CX,AX
	mov SI, offset g_aPolyInX
	mov DI, offset DGROUP:_g_graphics_context.pPolygonX
	rep movsw
	mov CX,AX
	mov SI, offset g_aPolyInY
	mov DI, offset DGROUP:_g_graphics_context.pPolygonY
	rep movsw
	mov DS,DX		; DS := SS := DGROUP for the load below + dispatch
	mov AX, offset DGROUP:_g_graphics_context.pPolygonY
	push AX
	mov AX, offset DGROUP:_g_graphics_context.pPolygonX
	push AX
	; --- vertex-count load ---------------------------------------------------
	; Read the polygon vertex count from the DGROUP field
	; g_graphics_context.nPolygonClipVertexCount. DS is already = DGROUP here, so
	; read the struct field directly under a local assume ds:DGROUP.
	assume ds:DGROUP
	mov AX, word ptr [_g_graphics_context.nPolygonClipVertexCount]
	assume ds:S233E_TEXT
	push AX
	call far ptr _sky_polygon_draw_dispatch
	add SP,6h
	pop ES
	pop DS
	pop DI
	pop SI
@@done:
	ret

; ============================================================================
; _r3d_polygon_submit_textured_quad
;
; If the current mesh polygon has exactly 4 vertices, copies its projected screen X/Y into the
; graphics-context polygon buffers, reads the day/night texture index from the polygon record at
; ES:DI, and calls worldrender_textured_quad_lod.
;
; C equivalent:
;   void r3d_polygon_submit_textured_quad(void)
;   {
;       int i;
;       int count;
;       int textureIndex;
;       unsigned char far *pPolyRecord;
;
;       count = g_nMeshPolyVertexCount;
;       if (count != 4)
;           return;
;
;       g_graphics_context.nPolygonClipVertexCount = count;
;
;       if (g_graphics_context.bGfxRenderStateFlag != 0)
;           textureIndex = pPolyRecord[1] | (pPolyRecord[2] << 8);
;       else
;           textureIndex = pPolyRecord[3] | (pPolyRecord[4] << 8);
;
;       for (i = 0; i < count; i++) {
;           g_graphics_context.pPolygonX[i] = g_aPolyInX[i];
;           g_graphics_context.pPolygonY[i] = g_aPolyInY[i];
;       }
;
;       worldrender_textured_quad_lod(textureIndex,
;                                     g_graphics_context.pPolygonX,
;                                     g_graphics_context.pPolygonY);
;   }
; ============================================================================
	public _r3d_polygon_submit_textured_quad
_r3d_polygon_submit_textured_quad:
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	cmp AX,4h
	jnz @@done
	mov CX,AX
	mov word ptr SS:[_g_graphics_context.nPolygonClipVertexCount], AX
	push SI
	push DI
	push DS
	push ES
	cmp SS:byte ptr [_g_graphics_context.bGfxRenderStateFlag], 0
	jz @@nightTexture
	mov DL, ES:byte ptr [DI].fDayOutline
	mov DH, ES:byte ptr [DI].fDayFill
	jmp short @@haveTexture
@@nightTexture:
	mov DL, ES:byte ptr [DI].fNightOutline
	mov DH, ES:byte ptr [DI].fNightFill
@@haveTexture:
	mov AX,SS
	mov ES,AX
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	mov CX,AX
	mov SI, offset g_aPolyInX
	mov DI, offset DGROUP:_g_graphics_context.pPolygonX
	rep movsw
	mov CX,AX
	mov SI, offset g_aPolyInY
	mov DI, offset DGROUP:_g_graphics_context.pPolygonY
	rep movsw
	mov AX,SS
	mov DS,AX
	mov AX, offset DGROUP:_g_graphics_context.pPolygonY
	push AX
	mov AX, offset DGROUP:_g_graphics_context.pPolygonX
	push AX
	push DX
	call far ptr _worldrender_textured_quad_lod
	add SP,6h
	pop ES
	pop DS
	pop DI
	pop SI
@@done:
	ret

; Gap 0x13ab-0x13ab: 1B zero-init
	db 0
; ============================================================================
; _r3d_ldiv_helper
;
; Scales two longs in place by the ratio num/den, i.e. out1 = in1*num/den and out2 =
; in2*num/den, using a sign-normalized fixed-point long divide/multiply. NB the
; stack positions: the DIVISOR den is the third slot ([BP+12:14]) and the
; NUMERATOR num the fourth ([BP+16:18]).
;
; C equivalent:
;   void near r3d_ldiv_helper(long *pScaledA, long *pScaledB, long den, long num)
;   {
;       long qFrac;
;       int sign;
;
;       /* Work with magnitudes; remember the sign of the num/den ratio. */
;       sign = 0;
;       if (num < 0) { num = -num; sign ^= 1; }
;       if (den < 0) { den = -den; sign ^= 1; }
;
;       /* Ratio is exactly +/-1: the scaled outputs are just the inputs,
;          negated together when num and den had opposite signs. */
;       if (num == den) {
;           if (sign) {
;               *pScaledA = -*pScaledA;
;               *pScaledB = -*pScaledB;
;           }
;           return;
;       }
;
;       /* Bail out (leave the outputs untouched) when the ratio would be
;          at or above 1, i.e. |num| >= |den| (the asm compares the high
;          words of the jointly left-normalized magnitudes, so a high-word
;          tie also bails). */
;       if (num >= den)
;           return;
;
;       /* qFrac = num / den built as a shifted fixed-point quotient:
;          the operands are left-normalized so the two DIVs recover a
;          high word (integer part) and a low word (fraction).  Only the
;          sign-free magnitude is formed here; each product is signed
;          independently below. */
;       qFrac = fixed_ldiv(num, den);
;
;       /* out = in * qFrac, keeping the middle 32 bits of the 64-bit
;          product (a fixed-point multiply that undoes qFrac's shift),
;          then apply the combined sign of that input and the ratio. */
;       {
;           long a = *pScaledA;
;           int negA = (a < 0);
;           if (negA) a = -a;
;           a = fixed_lmul(a, qFrac);
;           if ((a != 0) && ((*(int *)((char *)&(*pScaledA) + 2)) ^ sign) < 0)
;               a = -a;
;           *pScaledA = a;
;       }
;       {
;           long b = *pScaledB;
;           int negB = (b < 0);
;           if (negB) b = -b;
;           b = fixed_lmul(b, qFrac);
;           if ((b != 0) && ((*(int *)((char *)&(*pScaledB) + 2)) ^ sign) < 0)
;               b = -b;
;           *pScaledB = b;
;       }
;   }
; ============================================================================
@pScaledA equ word ptr [bp+4]
@pScaledAHi equ word ptr [bp+6]
@pScaledB equ word ptr [bp+8]
@pScaledBHi equ word ptr [bp+10]
@den equ word ptr [bp+12]
@denHi equ word ptr [bp+14]
@num equ word ptr [bp+16]
@numHi equ word ptr [bp+18]
	public _r3d_ldiv_helper
_r3d_ldiv_helper:
	push BP
	mov BP,SP
	sub SP,10h
	push SI
	push DI
	mov AX, @den
	mov DX, @denHi
	or DX,DX
	jns @@denAbs
	NEG32ADC AX, DX
	mov @den, AX
	mov @denHi, DX
@@denAbs:
	mov BX, @num
	mov CX, @numHi
	or CX,CX
	jns @@numAbs
	NEG32ADC BX, CX
	mov @num, BX
	mov @numHi, CX
@@numAbs:
	mov SI,DX
	xor SI,CX
	mov word ptr [BP-10], SI		; sign = sign(num) ^ sign(den)
	cmp AX,BX
	jnz @@notEqual
	cmp CX,DX
	jnz @@notEqual
	or SI,SI
	jz @@done
	mov AX, @pScaledA
	mov DX, @pScaledAHi
	NEG32ADC AX, DX
	mov @pScaledA, AX
	mov @pScaledAHi, DX
	mov AX, @pScaledB
	mov DX, @pScaledBHi
	NEG32ADC AX, DX
	mov @pScaledB, AX
	mov @pScaledBHi, DX
@@done:
	pop DI
	pop SI
	add SP,10h
	pop BP
	ret
@@notEqual:
	or DX,DX
	jnz @@normByte
	xchg AX, DX
	xchg BX, CX
	jmp short @@divide
@@normByte:
	or DH,DH
	jnz @@normCheck
	mov CH,CL
	mov CL,BH
	mov BH,BL
	mov DH,DL
	mov DL,AH
	mov AH,AL
	or DX,DX
	jmp short @@normCheck
@@normalize:
	shl BX,1h
	rcl CX,1h
	shl AX,1h
	rcl DX,1h
	or DX,DX
@@normCheck:
	jns @@normalize
@@divide:
	mov AX,BX
	xchg DX, CX
	cmp CX,DX
	jbe @@done				; |num| >= |den|: leave outputs untouched
	div CX
	mov word ptr [BP-2], AX
	mov word ptr [BP-6], AX
	xor AX,AX
	div CX
	mov word ptr [BP-4], AX
	mov word ptr [BP-8], AX
	mov AX, @pScaledA
	mov DX, @pScaledAHi
	or DX,DX
	jnz @@aSigned
	or AX,AX
	jz @@aStore
@@aSigned:
	or DX,DX
	jns @@aMul
	NEG32ADC AX, DX
@@aMul:
	mov BX, word ptr [BP-2]
	or BX,BX
	jz @@aMulLo
	or DX,DX
	jnz @@aMulFull
@@aMulLo:
	or DX,DX
	jnz @@aMulHi
	xchg word ptr [BP-4], AX
	xchg word ptr [BP-2], DX
@@aMulHi:
	xchg AX, DX
	mul word ptr [BP-4]
	xor AX,AX
	xchg AX, DX
	jmp short @@aStore
@@aMulFull:
	mov CX,DX
	mul word ptr [BP-2]
	mov SI,AX
	mov DI,DX
	mov AX,CX
	mul word ptr [BP-4]
	add SI,AX
	mov SI,0h
	adc DI,DX
	adc SI,0h
	mov AX,CX
	mul word ptr [BP-2]
	add AX,DI
	adc DX,SI
@@aStore:
	mov BX, @pScaledAHi
	xor BX, word ptr [BP-10]
	jns @@aWrite
	NEG32ADC AX, DX
@@aWrite:
	mov @pScaledA, AX
	mov @pScaledAHi, DX
	mov AX, @pScaledB
	mov DX, @pScaledBHi
	or DX,DX
	jnz @@bSigned
	or AX,AX
	jz @@bStore
@@bSigned:
	or DX,DX
	jns @@bMul
	NEG32ADC AX, DX
@@bMul:
	mov BX, word ptr [BP-6]
	or BX,BX
	jz @@bMulLo
	or DX,DX
	jnz @@bMulFull
@@bMulLo:
	or DX,DX
	jnz @@bMulHi
	xchg word ptr [BP-8], AX
	xchg word ptr [BP-6], DX
@@bMulHi:
	xchg AX, DX
	mul word ptr [BP-8]
	xor AX,AX
	xchg AX, DX
	jmp short @@bStore
@@bMulFull:
	mov CX,DX
	mul word ptr [BP-6]
	mov SI,AX
	mov DI,DX
	mov AX,CX
	mul word ptr [BP-8]
	add SI,AX
	mov SI,0h
	adc DI,DX
	adc SI,0h
	mov AX,CX
	mul word ptr [BP-6]
	add AX,DI
	adc DX,SI
@@bStore:
	mov BX, @pScaledBHi
	xor BX, word ptr [BP-10]
	jns @@bWrite
	NEG32ADC AX, DX
@@bWrite:
	mov @pScaledB, AX
	mov @pScaledBHi, DX
	pop DI
	pop SI
	add SP,10h
	pop BP
	ret

; ============================================================================
; _r3d_mat3_xform_vec3_long
;
; Transforms a short vec3 by a 3x3 matrix into three 48-bit fixed-point results (int part in
; out[], fractional low word in g_matXOut/YOut/ZOut), with identity/z-rotation fast paths keyed
; on matrix->bType.
;
; C equivalent:
;   void near r3d_mat3_xform_vec3_long(int *vec, Mat3x3 *matrix, long *out)
;   {
;       long acc;
;       int frac, lo, hi;
;       int i;
;
;       if (matrix->bType == 0) {
;           /* Identity: just sign-extend and scale each component. */
;           out[0] = (long)vec[0] << g_wMeshScaleShift;
;           g_matXOut = 0;
;           out[1] = (long)vec[1] << g_wMeshScaleShift;
;           g_matYOut = 0;
;           out[2] = (long)vec[2] << g_wMeshScaleShift;
;           g_matZOut = 0;
;           return;
;       }
;
;       if (matrix->bType == 1) {
;           /* 2D z-rotation: X,Y use the upper-left 2x2, Z passes through. */
;           acc = (long)matrix->pM[0] * vec[0] + (long)matrix->pM[3] * vec[1];
;           r3d_store_scaled48(acc, &out[0], &g_matXOut);
;
;           acc = (long)matrix->pM[1] * vec[0] + (long)matrix->pM[4] * vec[1];
;           r3d_store_scaled48(acc, &out[1], &g_matYOut);
;
;           out[2] = (long)vec[2] << g_wMeshScaleShift;
;           g_matZOut = 0;
;           return;
;       }
;
;       /* Full 3x3 transform. */
;       acc = (long)matrix->pM[0] * vec[0] + (long)matrix->pM[3] * vec[1]
;           + (long)matrix->pM[6] * vec[2];
;       r3d_store_scaled48(acc, &out[0], &g_matXOut);
;
;       acc = (long)matrix->pM[1] * vec[0] + (long)matrix->pM[4] * vec[1]
;           + (long)matrix->pM[7] * vec[2];
;       r3d_store_scaled48(acc, &out[1], &g_matYOut);
;
;       acc = (long)matrix->pM[2] * vec[0] + (long)matrix->pM[5] * vec[1]
;           + (long)matrix->pM[8] * vec[2];
;       r3d_store_scaled48(acc, &out[2], &g_matZOut);
;   }
;
;   /* Inlined helper: treat the 32-bit product as a 48-bit sign-extended
;      value {intHi:intLo:frac16}, shift it left by (2 + g_wMeshScaleShift),
;      store the two high words as the long integer part and the low word as
;      the fractional residue.  In the asm this is straight-line, not a call. */
;   static void r3d_store_scaled48(long prod, long *outInt, int *outFrac)
;   {
;       int frac, lo, hi;
;       int i;
;
;       frac = 0;                      /* BP: 16 fractional bits below prod */
;       lo   = (int)prod;              /* AX after mov BP,AX; mov AX,DX not */
;       hi   = (int)((unsigned long)prod >> 16);
;       /* rebuild as {hi:lo:frac} = prod << 16, then arithmetic-shift */
;       frac = lo;
;       lo   = hi;
;       hi   = hi >> 15;               /* cwd sign extension into new high */
;
;       /* 2 fixed pre-shifts, then g_wMeshScaleShift more, all across 48 bits */
;       for (i = 0; i < 2 + g_wMeshScaleShift; i++) {
;           hi   = (hi << 1) | ((lo >> 15) & 1);
;           lo   = (lo << 1) | ((frac >> 15) & 1);
;           frac = frac << 1;
;       }
;
;       *outInt  = ((long)(unsigned short)hi << 16) | (unsigned short)lo;
;       *outFrac = frac;
;   }
; ============================================================================
	public _r3d_mat3_xform_vec3_long
_r3d_mat3_xform_vec3_long:
	push BP
	push SI
	push DI
	mov SI,BX
	mov DI,CX
	mov BX,AX
	mov AL, byte ptr [SI].mType
	or AL,AL
	jnz @@notIdentity
	mov AX, word ptr [BX]
	cwd
	mov CX, word ptr ds:[g_wMeshScaleShift]
	jcxz @@idXDone
@@idXShift:
	shl AX,1h
	rcl DX,1h
	loop @@idXShift
@@idXDone:
	mov word ptr [DI], AX
	mov word ptr [DI+2], DX
	xor AX,AX
	mov word ptr ds:[g_matXOut], AX
	mov AX, word ptr [BX+2]
	cwd
	mov CX, word ptr ds:[g_wMeshScaleShift]
	jcxz @@idYDone
@@idYShift:
	shl AX,1h
	rcl DX,1h
	loop @@idYShift
@@idYDone:
	mov word ptr [DI+4], AX
	mov word ptr [DI+6], DX
	xor AX,AX
	mov word ptr ds:[g_matYOut], AX
	mov AX, word ptr [BX+4]
	cwd
	mov CX, word ptr ds:[g_wMeshScaleShift]
	jcxz @@idZDone
@@idZShift:
	shl AX,1h
	rcl DX,1h
	loop @@idZShift
@@idZDone:
	mov word ptr [DI+8], AX
	mov word ptr [DI+10], DX
	xor AX,AX
	mov word ptr ds:[g_matZOut], AX
	jmp @@done
@@notIdentity:
	dec AL
	jz @@rotZ
	jmp @@full3x3
@@rotZ:
	MULSEED [BX], [SI]
	MULACC [BX+2], [SI+6]
	mov BP,AX
	mov AX,DX
	cwd
	Q14NORM48
	mov CX, word ptr ds:[g_wMeshScaleShift]
	jcxz @@rotXDone
@@rotXShift:
	shl BP,1h
	rcl AX,1h
	rcl DX,1h
	loop @@rotXShift
@@rotXDone:
	mov word ptr [DI], AX
	mov word ptr [DI+2], DX
	mov word ptr ds:[g_matXOut], BP
	MULSEED [BX], [SI+2]
	MULACC [BX+2], [SI+8]
	mov BP,AX
	mov AX,DX
	cwd
	Q14NORM48
	mov CX, word ptr ds:[g_wMeshScaleShift]
	jcxz @@rotYDone
@@rotYShift:
	shl BP,1h
	rcl AX,1h
	rcl DX,1h
	loop @@rotYShift
@@rotYDone:
	mov word ptr [DI+4], AX
	mov word ptr [DI+6], DX
	mov word ptr ds:[g_matYOut], BP
	mov AX, word ptr [BX+4]
	cwd
	mov CX, word ptr ds:[g_wMeshScaleShift]
	jcxz @@rotZDone
@@rotZShift:
	shl AX,1h
	rcl DX,1h
	loop @@rotZShift
@@rotZDone:
	mov word ptr [DI+8], AX
	mov word ptr [DI+10], DX
	xor AX,AX
	mov word ptr ds:[g_matZOut], AX
	jmp @@done
@@full3x3:
	MULSEED [BX], [SI]
	MULACC2 [BX+2], [SI+6]
	MULACC [BX+4], [SI+12]
	mov BP,AX
	mov AX,DX
	cwd
	Q14NORM48
	mov CX, word ptr ds:[g_wMeshScaleShift]
	jcxz @@fullXDone
@@fullXShift:
	shl BP,1h
	rcl AX,1h
	rcl DX,1h
	loop @@fullXShift
@@fullXDone:
	mov word ptr [DI], AX
	mov word ptr [DI+2], DX
	mov word ptr ds:[g_matXOut], BP
	MULSEED [BX], [SI+2]
	MULACC2 [BX+2], [SI+8]
	MULACC [BX+4], [SI+14]
	mov BP,AX
	mov AX,DX
	cwd
	Q14NORM48
	mov CX, word ptr ds:[g_wMeshScaleShift]
	jcxz @@fullYDone
@@fullYShift:
	shl BP,1h
	rcl AX,1h
	rcl DX,1h
	loop @@fullYShift
@@fullYDone:
	mov word ptr [DI+4], AX
	mov word ptr [DI+6], DX
	mov word ptr ds:[g_matYOut], BP
	MULSEED [BX], [SI+4]
	MULACC2 [BX+2], [SI+10]
	MULACC [BX+4], [SI+16]
	mov BP,AX
	mov AX,DX
	cwd
	Q14NORM48
	mov CX, word ptr ds:[g_wMeshScaleShift]
	jcxz @@fullZDone
@@fullZShift:
	shl BP,1h
	rcl AX,1h
	rcl DX,1h
	loop @@fullZShift
@@fullZDone:
	mov word ptr [DI+8], AX
	mov word ptr [DI+10], DX
	mov word ptr ds:[g_matZOut], BP
@@done:
	pop DI
	pop SI
	pop BP
	ret

; In-segment data at 0x174b [g_nMeshPolyRemaining]
g_nMeshPolyRemaining	dw 0

; In-segment data at 0x174d [g_bMeshPolyHasZClipVertex]
g_bMeshPolyHasZClipVertex	db 0

; ============================================================================
; _r3d_mesh_polygons
;
; Transforms, projects, back-face culls, near-clips and rasterizes every solid-shaded polygon of
; one mesh part (the LOD-1 and LOD-2 path of the actor renderer; ACTRENDR.C dispatches this for
; bCurMeshLod 1 and 2, while the default LOD 0 goes to r3d_mesh_part_polygons and LOD 3 to
; r3d_mesh_part_polygons_lod3).
;
; C equivalent:
;   #define MESH_MAX_VERTS 256
;   #define POLY_MAX_VERTS 20
;
;   typedef struct {
;       unsigned char flags;     /* +0: bit0..1 = kind, bit5 = double-sided */
;       unsigned char pad1;      /* +1 */
;       unsigned char pad234[3]; /* +2..+4 */
;       unsigned char faceVtx;   /* +5: representative vertex for back-face test */
;       unsigned short vtxList;  /* +6: near offset of 0xFF-terminated index list */
;   } MeshPoly;                  /* 8-byte record */
;
;   /* Clip-state per mesh vertex, index = vertex id:
;    *   0 = untouched, 1 = transformed this frame, 2 = visible (projected),
;    *   3 = behind the near-clip plane. */
;   extern unsigned char g_abPolygonClipState[510];
;
;   /* Parallel per-vertex arrays, index = vertex id. The cam-space coords are
;    * 32-bit; the assembler keeps them as split lo/hi word arrays. */
;   extern long g_aVertexCam[3][MESH_MAX_VERTS];  /* [0]=X [1]=Z [2]=Y (cam) */
;   extern long g_aVertexScr[2][MESH_MAX_VERTS];  /* [0]=X [1]=Y (screen)   */
;
;   extern unsigned short g_polygon_vertices[POLY_MAX_VERTS]; /* visible vtx ids */
;   extern short g_aPolyScrX[POLY_MAX_VERTS];  /* built screen X for clipper */
;   extern short g_aPolyScrY[POLY_MAX_VERTS];  /* built screen Y for clipper */
;
;   void far r3d_mesh_polygons(unsigned char far *part_header)
;   {
;       unsigned short vtxPoolOff;
;       unsigned char far *polyBase;
;       MeshPoly far *poly;
;       unsigned char far *idxList;
;       short vId, kind;
;       long lo, hi;
;       short i;
;
;       /* Once per distinct vertex pool, clear the per-vertex clip-state cache. */
;       vtxPoolOff = g_wMeshVertexPoolOff;
;       if (FP_SEG(part_header) != g_dwMeshVertexFarPtrCache >> 16 ||
;           (unsigned short)g_dwMeshVertexFarPtrCache != vtxPoolOff) {
;           g_dwMeshVertexFarPtrCache =
;               ((unsigned long)FP_SEG(part_header) << 16) | vtxPoolOff;
;           for (i = 0; i < (short)g_nMeshPartVertexCount; i++)
;               ((unsigned short *)g_abPolygonClipState)[i] = 0;
;       }
;
;       /* part_header: word[0] = polygon count, word[1] = near ptr to polygons. */
;       g_nMeshPolyRemaining = *(unsigned short far *)part_header;
;       polyBase = *(unsigned char far * far *)(part_header + 2);
;
;       while (--g_nMeshPolyRemaining >= 0) {
;           poly = (MeshPoly far *)polyBase;
;           kind = poly->flags & 3;
;           if (kind == 2) {          /* not a solid polygon here */
;               polyBase += 8;
;               continue;
;           }
;           idxList = polyBase + poly->vtxList; /* vertex-index list, in same seg */
;           g_bPolyNormalFlipped = 0;
;
;           /* Back-face test. r3d_backface_dot_indexed(AL=faceVtx, AH=normal) */
;           if (kind == 0) {
;               if ((poly->flags & 0x20) &&      /* double-sided */
;                   r3d_backface_dot_indexed(poly->faceVtx, *idxList) >= 0)
;                   g_bPolyNormalFlipped = 1;     /* front faces away: flip normal */
;           } else {
;               if (r3d_backface_dot_indexed(poly->faceVtx, *idxList) >= 0) {
;                   polyBase += 8;               /* back-facing: cull */
;                   continue;
;               }
;           }
;
;           r3d_polygon_resolve_shade_color();
;           g_bMeshPolyHasZClipVertex = 0;
;           g_nMeshPolyVertexCount = 0;
;
;           /* Walk the polygon's vertex indices to the 0xFF terminator. */
;           for (; (vId = *idxList) != 0xFF; idxList++) {
;               if (g_abPolygonClipState[vId] == 0) {
;                   /* First sighting this frame: rotate into actor space, then
;                    * translate by the actor's camera-space origin (32-bit). */
;                   short far *src = (short far *)(vtxPoolOff + vId * 6);
;                   g_matXIn = src[0];
;                   g_matYIn = src[1];
;                   g_matZIn = src[2];
;                   r3d_mat3_xform_vec3_long(&g_matXIn, &g_mat3x3ActorRot,
;                                            &g_matXOut32);
;                   g_aVertexCam[0][vId] = g_matXOut32L + g_dwActorCamX;
;                   g_aVertexCam[1][vId] = g_matZOut32L + g_dwActorCamZ;
;                   g_aVertexCam[2][vId] = g_matYOut32L + g_dwActorCamY;
;
;                   /* Classify against the near-clip plane (cam Z = index 1). */
;                   if (g_aVertexCam[1][vId] <= 0 &&
;                       (g_aVertexCam[1][vId] < 0 ||
;                        (unsigned long)g_aVertexCam[0][vId] <
;                            (unsigned short)g_nActorFarClipThreshold)) {
;                       g_abPolygonClipState[vId] = 3;      /* behind near plane */
;                       g_bMeshPolyHasZClipVertex = 1;
;                       goto emit_vertex;
;                   }
;                   g_abPolygonClipState[vId] = 2;          /* visible */
;                   /* Perspective divide -> screen X/Y (32-bit fixed point). */
;                   r3d_ldiv_helper(g_aVertexCam[0][vId], g_aVertexCam[2][vId],
;                                   g_aVertexCam[1][vId], g_nActorFarClipThreshold,
;                                   0L, &g_aVertexScr[0][vId],
;                                   &g_aVertexScr[1][vId]);
;               } else if (g_abPolygonClipState[vId] != 2) {
;                   /* Cached as near-clipped: reclassify but skip retransform. */
;                   if (g_aVertexCam[1][vId] <= 0 &&
;                       (g_aVertexCam[1][vId] < 0 ||
;                        (unsigned long)g_aVertexCam[0][vId] <
;                            (unsigned short)g_nActorFarClipThreshold)) {
;                       g_abPolygonClipState[vId] = 3;
;                       g_bMeshPolyHasZClipVertex = 1;
;                   } else {
;                       g_abPolygonClipState[vId] = 2;
;                       r3d_ldiv_helper(g_aVertexCam[0][vId],
;                                       g_aVertexCam[2][vId], g_aVertexCam[1][vId],
;                                       g_nActorFarClipThreshold, 0L,
;                                       &g_aVertexScr[0][vId],
;                                       &g_aVertexScr[1][vId]);
;                   }
;               }
;           emit_vertex:
;               g_polygon_vertices[g_nMeshPolyVertexCount++] = vId;
;           }
;
;           if (g_bMeshPolyHasZClipVertex) {
;               /* Some vertex crossed near-Z: run the geometric clipper. */
;               if (g_bCurMeshLod == 1)
;                   r3d_polygon_clip_against_zplane();
;               else
;                   r3d_polygon_clip_near_z_lod2();
;           } else {
;               if (g_nMeshPolyVertexCount == 0) {
;                   polyBase += 8;
;                   continue;
;               }
;               /* Fully in front: copy screen coords straight into the poly. */
;               for (i = 0; i < g_nMeshPolyVertexCount; i++) {
;                   vId = g_polygon_vertices[i];
;                   g_aPolyScrX[i] = (short)g_aVertexScr[0][vId];
;                   g_aPolyScrY[i] = (short)g_aVertexScr[1][vId];
;               }
;           }
;
;           r3d_apply_viewport_offset_long();
;           if (g_bActorViewportClip) {
;               if (g_bCurMeshLod == 1)
;                   r3d_clip_polygon_to_viewport();
;               else
;                   r3d_polygon_clip_rect_2d();
;           }
;           r3d_polygon_submit_to_rasterizer();
;           polyBase += 8;
;       }
;   }
; ============================================================================
@part_header equ dword ptr [bp+6]
	public _r3d_mesh_polygons
_r3d_mesh_polygons:
	push BP
	mov BP,SP
	push SI
	push DI
	push DS
	mov AX,CS
	mov DS,AX
	les DI, @part_header
	mov BP, word ptr ds:[g_wMeshVertexPoolOff]
	mov AX,ES
	cmp word ptr ds:[g_wMeshVertexCacheSeg], AX
	jnz @@rebuildCache
	cmp word ptr ds:[g_dwMeshVertexFarPtrCache], BP
	jz @@haveCache
@@rebuildCache:
	mov word ptr ds:[g_wMeshVertexCacheSeg], AX
	mov word ptr ds:[g_dwMeshVertexFarPtrCache], BP
	push DI
	push ES
	mov AX,CS
	mov ES,AX
	mov DI,offset g_abPolygonClipState
	mov CX, word ptr ds:[g_nMeshPartVertexCount]
	xor AX,AX
	rep stosw
	pop ES
	pop DI
@@haveCache:
	mov AX, ES:word ptr [DI].hPolyCount
	mov word ptr ds:[g_nMeshPolyRemaining], AX
	mov DI, ES:word ptr [DI].hFirstPoly
@@nextPoly:
	dec word ptr ds:[g_nMeshPolyRemaining]
	jge @@procPoly
	jmp @@done
@@procPoly:
	mov AL, ES:byte ptr [DI].fFlags
	mov AH,AL
	and AL,3h
	cmp AL,2h
	jz @@skipPoly
	mov SI, ES:word ptr [DI].fVertList
	mov byte ptr ds:[g_bPolyNormalFlipped], 0
	cmp AL,0h
	jnz @@backfaceTest
	test AH,MESH_FLAG_SIMPLE
	jz @@shadePoly
	BACKFACEDOT
	jl @@shadePoly
	mov byte ptr ds:[g_bPolyNormalFlipped], 1
	jmp short @@shadePoly
@@backfaceTest:
	BACKFACEDOT
	jl @@shadePoly
@@skipPoly:
	add DI,FACE_SIZE
	jmp short @@nextPoly
@@shadePoly:
	call _r3d_polygon_resolve_shade_color
	xor AX,AX
	mov byte ptr ds:[g_bMeshPolyHasZClipVertex], AL
	mov word ptr ds:[g_nMeshPolyVertexCount], AX
@@nextVertex:
	mov AL, ES:byte ptr [SI]
	cmp AL,0ffh
	jnz @@vertexValid
	jmp @@polyDone
@@vertexValid:
	mov BL,AL
	xor BH,BH
	shl BX,1h
	cmp byte ptr [BX+g_abPolygonClipState], CLIPST_UNTOUCHED
	jz @@transformVertex
	cmp byte ptr [BX+g_abPolygonClipState], CLIPST_PROJECTED
	jnz @@vertexCached
	jmp @@appendVertex
@@vertexCached:
	jmp @@classifyVertex
@@transformVertex:
	mov byte ptr [BX+g_abPolygonClipState], CLIPST_PENDING
	push BX
	VROWADDR
	mov AX, ES:word ptr [BX].vX
	mov word ptr ds:[g_matXIn], AX
	mov AX, ES:word ptr [BX].vY
	mov word ptr ds:[g_matYIn], AX
	mov AX, ES:word ptr [BX].vZ
	mov word ptr ds:[g_matZIn], AX
	mov AX,offset g_matXIn
	mov BX,offset g_mat3x3ActorRot
	mov CX,offset g_matXOut32
	call _r3d_mat3_xform_vec3_long
	pop BX
	mov CX, word ptr ds:[g_matXOut]
	mov AX, word ptr ds:[g_matXOut32]
	mov DX, word ptr ds:[g_matXOut32Hi]
	add CX,0h
	adc AX, word ptr ds:[g_dwActorCamX]
	adc DX, word ptr ds:[g_dwActorCamX+2]
	ST32 BX, g_aVertexCamX
	mov CX, word ptr ds:[g_matYOut]
	mov AX, word ptr ds:[g_matZOut32]
	mov DX, word ptr ds:[g_matZOut32Hi]
	add CX,0h
	adc AX, word ptr ds:[g_dwActorCamZ]
	adc DX, word ptr ds:[g_dwActorCamZ+2]
	ST32 BX, g_aVertexCamY
	mov CX, word ptr ds:[g_matZOut]
	mov AX, word ptr ds:[g_matYOut32]
	mov DX, word ptr ds:[g_matYOut32Hi]
	add CX,0h
	adc AX, word ptr ds:[g_dwActorCamY]
	adc DX, word ptr ds:[g_dwActorCamY+2]
	ST32 BX, g_aVertexCamZ
@@classifyVertex:
	mov AX, word ptr [BX+g_aVertexCamYHi]
	cmp AX,0h
	jg @@projectVertex
	jl @@vertexBehind
	mov AX, word ptr [BX+g_aVertexCamY]
	cmp AX, word ptr ds:[g_nViewPlaneDist]
	jnc @@projectVertex
@@vertexBehind:
	mov byte ptr [BX+g_abPolygonClipState], CLIPST_BEHIND
	mov byte ptr ds:[g_bMeshPolyHasZClipVertex], 1
	jmp short @@appendVertex
@@projectVertex:
	mov byte ptr [BX+g_abPolygonClipState], CLIPST_PROJECTED
	push SI
	mov SI,BX
	xor AX,AX
	push AX
	push word ptr ds:[g_nViewPlaneDist]
	push word ptr [SI+g_aVertexCamYHi]
	push word ptr [SI+g_aVertexCamY]
	push word ptr [SI+g_aVertexCamZHi]
	push word ptr [SI+g_aVertexCamZ]
	push word ptr [SI+g_aVertexCamXHi]
	push word ptr [SI+g_aVertexCamX]
	call _r3d_ldiv_helper
	pop word ptr [SI+g_aVertexScrX]
	pop word ptr [SI+g_aVertexScrXHi]
	pop word ptr [SI+g_aVertexScrY]
	pop word ptr [SI+g_aVertexScrYHi]
	add SP,8h
	mov BX,SI
	pop SI
@@appendVertex:
	mov AX,BX
	mov BX, word ptr ds:[g_nMeshPolyVertexCount]
	shl BX,1h
	mov word ptr [BX+g_polygon_vertices], AX
	inc word ptr ds:[g_nMeshPolyVertexCount]
	inc SI
	jmp @@nextVertex
@@polyDone:
	cmp byte ptr ds:[g_bMeshPolyHasZClipVertex], 0
	jz @@copyVerts
	cmp byte ptr ds:[g_bCurMeshLod], 1
	jnz @@clipLod2
	call _r3d_polygon_clip_against_zplane
	jmp short @@viewport
@@clipLod2:
	call _r3d_polygon_clip_near_z_lod2
	jmp short @@viewport
@@copyVerts:
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	or AX,AX
	jz @@advancePoly
	mov CX,AX
	xor BX,BX
@@copyVertLoop:
	mov SI, word ptr [BX+g_polygon_vertices]
	mov AX, word ptr [SI+g_aVertexScrX]
	mov word ptr [BX+g_aPolyInX], AX
	mov AX, word ptr [SI+g_aVertexScrXHi]
	mov word ptr [BX+g_aPolyInXHi], AX
	mov AX, word ptr [SI+g_aVertexScrY]
	mov word ptr [BX+g_aPolyInY], AX
	mov AX, word ptr [SI+g_aVertexScrYHi]
	mov word ptr [BX+g_aPolyInYHi], AX
	add BX,2h
	loop @@copyVertLoop
@@viewport:
	call _r3d_apply_viewport_offset_long
	cmp byte ptr ds:[g_bActorViewportClip], 0
	jz @@submit
	cmp byte ptr ds:[g_bCurMeshLod], 1
	jnz @@clipRect
	call _r3d_clip_polygon_to_viewport
	jmp short @@submit
@@clipRect:
	call _r3d_polygon_clip_rect_2d
@@submit:
	call _r3d_polygon_submit_to_rasterizer
@@advancePoly:
	add DI,FACE_SIZE
	jmp @@nextPoly
@@done:
	pop DS
	pop DI
	pop SI
	pop BP
	retf

; Gap 0x1983-0x1983: 1B zero-init
	db 0
; In-segment data at 0x1984 [g_nPolyListRemaining]
g_nPolyListRemaining	dw 0

; ============================================================================
; _r3d_mesh_part_polygons_lod3
;
; Renders a mesh part's polygon list: backface-culls each face, transforms/projects its
; referenced vertices into screen space (with per-vertex caching), then submits each visible
; face to the rasterizer or textured-quad path.
;
; C equivalent:
;   /*
;    * part_header points to a small header in the mesh-part segment (ES):
;    *   [0] short  faceCount
;    *   [2] word   near offset (within ES) of the first 8-byte face record
;    *
;    * Each 8-byte face record:
;    *   [0] byte  flags  (bits 0-1 = face kind, 0x10 = textured quad, 0x20 = two-sided)
;    *   [5] byte  reference vertex index used for the back-face test
;    *   [6] word  near offset (within ES) of this face's vertex-index list,
;    *             a run of byte indices terminated by 0xFF
;    *
;    * Vertices are pulled from the shared mesh vertex pool at
;    * ES:g_wMeshVertexPoolOff, 6 bytes (short x,y,z) per vertex.  Because the
;    * pool is reused across faces, per-vertex results are cached: g_abPolygonClipState[]
;    * records 0 = untouched, 1 = transformed to camera space, 2 = also projected to
;    * screen.  The cache is flushed whenever the vertex pool far pointer changes.
;    */
;   void far r3d_mesh_part_polygons_lod3(unsigned short far *part_header)
;   {
;       unsigned char far *facePtr;
;       unsigned char far *indexList;
;       unsigned short vertexPoolOff;
;       unsigned short poolSeg;
;       unsigned char flags;
;       unsigned char kind;
;       int i;
;
;       vertexPoolOff = g_wMeshVertexPoolOff;
;       poolSeg = FP_SEG(part_header);
;
;       /* Flush the per-vertex cache if the vertex pool far pointer changed. */
;       if (g_wMeshVertexCacheSeg != poolSeg ||
;           (unsigned short)g_dwMeshVertexFarPtrCache != vertexPoolOff)
;       {
;           g_wMeshVertexCacheSeg = poolSeg;
;           g_dwMeshVertexFarPtrCache = vertexPoolOff;
;           for (i = 0; i < g_nMeshPartVertexCount; i++)
;               g_abPolygonClipState[i] = 0;
;       }
;
;       g_nPolyListRemaining = part_header[0];
;       facePtr = (unsigned char far *)MK_FP(poolSeg, part_header[1]);
;
;       while (--g_nPolyListRemaining >= 0)
;       {
;           flags = facePtr[0];
;           kind = flags & 3;
;           if (kind == 2)
;           {
;               facePtr += 8;               /* kind 2: skip, no culling */
;               continue;
;           }
;
;           indexList = (unsigned char far *)MK_FP(poolSeg, *(unsigned short far *)(facePtr + 6));
;           g_bPolyNormalFlipped = 0;
;
;           if (kind == 0)
;           {
;               /* One-sided face: back-face cull unless flagged two-sided (0x20). */
;               if ((flags & 0x20) != 0 &&
;                   r3d_backface_dot_indexed(indexList[0], facePtr[5]) >= 0)
;               {
;                   /* Two-sided face seen from behind: draw with flipped normal. */
;                   g_bPolyNormalFlipped = 1;
;               }
;               else
;               {
;                   facePtr += 8;
;                   continue;
;               }
;           }
;           else
;           {
;               /* kind 1/3: cull if the face's signed area points away. */
;               if (r3d_backface_dot_indexed(indexList[0], facePtr[5]) >= 0)
;               {
;                   facePtr += 8;
;                   continue;
;               }
;           }
;
;           r3d_polygon_resolve_shade_color();
;           g_nMeshPolyVertexCount = 0;
;
;           for (; indexList[0] != 0xFF; indexList++)
;           {
;               unsigned char v = indexList[0];
;               short far *pool;
;
;               if (g_abPolygonClipState[v] == 0)
;               {
;                   /* Transform this vertex into camera space (cache miss). */
;                   g_abPolygonClipState[v] = 1;
;                   pool = (short far *)MK_FP(poolSeg, vertexPoolOff + v * 6);
;                   g_matXIn = pool[0];
;                   g_matYIn = pool[1];
;                   g_matZIn = pool[2];
;                   r3d_matrix3x3_transform_vec3(&g_matXIn, &g_mat3x3ActorRot,
;                                                &g_matXOut);
;                   g_aVertexCamX[v] = scale_shift(g_matXOut, g_wMeshScaleShift) +
;                                      (short)g_dwActorCamX;
;                   g_aVertexCamY[v] = scale_shift(g_matYOut, g_wMeshScaleShift) +
;                                      (short)g_dwActorCamZ;
;                   g_aVertexCamZ[v] = scale_shift(g_matZOut, g_wMeshScaleShift) +
;                                      (short)g_dwActorCamY;
;               }
;               else if (g_abPolygonClipState[v] == 2)
;               {
;                   /* Already fully projected: reuse cached screen coords. */
;                   g_polygon_vertices[g_nMeshPolyVertexCount++] = v * 2;
;                   continue;
;               }
;
;               /* Perspective-divide into screen space (state 1 -> 2). */
;               g_abPolygonClipState[v] = 2;
;               {
;                   short depth = g_aVertexCamY[v];       /* camera-space depth */
;                   unsigned char sh = g_nScreenShift;
;                   /* screenX = (camX << sh) / depth, done in 32 bits */
;                   g_aVertexScrX[v] = (short)(((long)g_aVertexCamX[v] << sh) / depth);
;                   g_aVertexScrY[v] = (short)(((long)g_aVertexCamZ[v] << sh) / depth);
;               }
;               g_polygon_vertices[g_nMeshPolyVertexCount++] = v * 2;
;           }
;
;           if (g_nMeshPolyVertexCount != 0)
;           {
;               /* Gather the face's screen coords into the flat poly X/Y buffers. */
;               for (i = 0; i < g_nMeshPolyVertexCount; i++)
;               {
;                   short far *vtx = (short far *)MK_FP(_CS, g_polygon_vertices[i]);
;                   g_aPolyInX[i] = *(short *)((char *)vtx +
;                                           ((char *)g_aVertexScrX - (char *)0));
;                   g_aPolyInY[i] = *(short *)((char *)vtx +
;                                           ((char *)g_aVertexScrY - (char *)0));
;               }
;               r3d_apply_viewport_offset();
;
;               if ((facePtr[0] & 0x10) != 0)
;               {
;                   r3d_polygon_submit_textured_quad();
;               }
;               else
;               {
;                   if (g_bActorViewportClip != 0)
;                       r3d_polygon_scissor_2d();
;                   r3d_polygon_submit_to_rasterizer();
;               }
;           }
;
;           facePtr += 8;
;       }
;   }
;
;   /* Helper (inline in the asm): signed fixed-point shift by a signed count. */
;   static short scale_shift(short v, short count)
;   {
;       if (count > 0)
;           return v << count;
;       return v >> (-count);
;   }
; ============================================================================
@part_header equ dword ptr [bp+6]
	public _r3d_mesh_part_polygons_lod3
_r3d_mesh_part_polygons_lod3:
	push BP
	mov BP,SP
	push SI
	push DI
	push DS
	mov AX,CS
	mov DS,AX
	les DI, @part_header
	mov BP, word ptr ds:[g_wMeshVertexPoolOff]
	mov AX,ES
	cmp word ptr ds:[g_wMeshVertexCacheSeg], AX
	jnz @@rebuildCache
	cmp word ptr ds:[g_dwMeshVertexFarPtrCache], BP
	jz @@haveCache
@@rebuildCache:
	mov word ptr ds:[g_wMeshVertexCacheSeg], AX
	mov word ptr ds:[g_dwMeshVertexFarPtrCache], BP
	push DI
	push ES
	mov AX,CS
	mov ES,AX
	mov DI,offset g_abPolygonClipState
	mov CX, word ptr ds:[g_nMeshPartVertexCount]
	xor AX,AX
	rep stosw
	pop ES
	pop DI
@@haveCache:
	mov AX, ES:word ptr [DI].hPolyCount
	mov word ptr ds:[g_nPolyListRemaining], AX
	mov DI, ES:word ptr [DI].hFirstPoly
@@nextPoly:
	dec word ptr ds:[g_nPolyListRemaining]
	jge @@procPoly
	jmp @@done
@@procPoly:
	mov AL, ES:byte ptr [DI].fFlags
	mov AH,AL
	and AL,3h
	cmp AL,2h
	jz @@skipPoly
	mov SI, ES:word ptr [DI].fVertList
	mov byte ptr ds:[g_bPolyNormalFlipped], 0
	cmp AL,0h
	jnz @@backfaceTest
	test AH,MESH_FLAG_SIMPLE
	jz @@shadePoly
	BACKFACEDOT
	jl @@shadePoly
	mov byte ptr ds:[g_bPolyNormalFlipped], 1
	jmp short @@shadePoly
@@backfaceTest:
	BACKFACEDOT
	jl @@shadePoly
@@skipPoly:
	add DI,FACE_SIZE
	jmp short @@nextPoly
@@shadePoly:
	call _r3d_polygon_resolve_shade_color
	xor AX,AX
	mov word ptr ds:[g_nMeshPolyVertexCount], AX
@@nextVertex:
	mov AL, ES:byte ptr [SI]
	cmp AL,0ffh
	jnz @@vertexValid
	jmp @@copyVerts
@@vertexValid:
	mov BL,AL
	xor BH,BH
	shl BX,1h
	cmp byte ptr [BX+g_abPolygonClipState], CLIPST_UNTOUCHED
	jz @@transformVertex
	cmp byte ptr [BX+g_abPolygonClipState], CLIPST_PROJECTED
	jnz @@vertexCached
	jmp @@appendVertex
@@vertexCached:
	jmp @@projectVertex
@@transformVertex:
	mov byte ptr [BX+g_abPolygonClipState], CLIPST_PENDING
	push BX
	VROWADDR
	mov AX, ES:word ptr [BX].vX
	mov word ptr ds:[g_matXIn], AX
	mov AX, ES:word ptr [BX].vY
	mov word ptr ds:[g_matYIn], AX
	mov AX, ES:word ptr [BX].vZ
	mov word ptr ds:[g_matZIn], AX
	mov AX,offset g_matXIn
	mov BX,offset g_mat3x3ActorRot
	mov CX,offset g_matXOut
	call _r3d_matrix3x3_transform_vec3
	pop BX
	mov AX, word ptr ds:[g_matXOut]
	mov CX, word ptr ds:[g_wMeshScaleShift]
	or CL,CL
	jg @@xShiftLeft
	neg CL
	sar AX,CL
	jmp short @@xScaled
@@xShiftLeft:
	shl AX,CL
@@xScaled:
	add AX, word ptr ds:[g_dwActorCamX]
	mov word ptr [BX+g_aVertexCamX], AX
	mov AX, word ptr ds:[g_matYOut]
	mov CX, word ptr ds:[g_wMeshScaleShift]
	or CL,CL
	jg @@yShiftLeft
	neg CL
	sar AX,CL
	jmp short @@yScaled
@@yShiftLeft:
	shl AX,CL
@@yScaled:
	add AX, word ptr ds:[g_dwActorCamZ]
	mov word ptr [BX+g_aVertexCamY], AX
	mov AX, word ptr ds:[g_matZOut]
	mov CX, word ptr ds:[g_wMeshScaleShift]
	or CL,CL
	jg @@zShiftLeft
	neg CL
	sar AX,CL
	jmp short @@zScaled
@@zShiftLeft:
	shl AX,CL
@@zScaled:
	add AX, word ptr ds:[g_dwActorCamY]
	mov word ptr [BX+g_aVertexCamZ], AX
@@projectVertex:
	mov byte ptr [BX+g_abPolygonClipState], CLIPST_PROJECTED
	push SI
	mov SI, word ptr [BX+g_aVertexCamY]
	mov CX, word ptr ds:[g_nScreenShift]
	push CX
	mov AX, word ptr [BX+g_aVertexCamX]
	cwd
	cmp CL,8h
	jl @@scrXShift
	mov DL,AH
	mov AH,AL
	xor AL,AL
	sub CL,8h
	jz @@scrXDivide
@@scrXShift:
	shl AX,1h
	rcl DX,1h
	loop @@scrXShift
@@scrXDivide:
	idiv SI
	mov word ptr [BX+g_aVertexScrX], AX
	mov AX, word ptr [BX+g_aVertexCamZ]
	pop CX
	cwd
	cmp CL,8h
	jl @@scrYShift
	mov DL,AH
	mov AH,AL
	xor AL,AL
	sub CL,8h
	jz @@scrYDivide
@@scrYShift:
	shl AX,1h
	rcl DX,1h
	loop @@scrYShift
@@scrYDivide:
	idiv SI
	mov word ptr [BX+g_aVertexScrY], AX
	pop SI
@@appendVertex:
	mov AX,BX
	mov BX, word ptr ds:[g_nMeshPolyVertexCount]
	shl BX,1h
	mov word ptr [BX+g_polygon_vertices], AX
	inc word ptr ds:[g_nMeshPolyVertexCount]
	inc SI
	jmp @@nextVertex
@@copyVerts:
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	or AX,AX
	jz @@advancePoly
	mov CX,AX
	xor BX,BX
@@copyVertLoop:
	mov SI, word ptr [BX+g_polygon_vertices]
	mov AX, word ptr [SI+g_aVertexScrX]
	mov word ptr [BX+g_aPolyInX], AX
	mov AX, word ptr [SI+g_aVertexScrY]
	mov word ptr [BX+g_aPolyInY], AX
	add BX,2h
	loop @@copyVertLoop
	call _r3d_apply_viewport_offset
	mov AL, ES:byte ptr [DI].fFlags
	test AL,10h
	jz @@clipAndSubmit
	call _r3d_polygon_submit_textured_quad
	jmp short @@advancePoly
@@clipAndSubmit:
	cmp byte ptr ds:[g_bActorViewportClip], 0
	jz @@submit
	call _r3d_polygon_scissor_2d
@@submit:
	call _r3d_polygon_submit_to_rasterizer
@@advancePoly:
	add DI,FACE_SIZE
	jmp @@nextPoly
@@done:
	pop DS
	pop DI
	pop SI
	pop BP
	retf

; Gap 0x1b79-0x1b79: 1B zero-init
	db 0
; ============================================================================
; _r3d_vec2_long_translate_yflip
;
; Translates a 32-bit (x,y) point into screen space: x += viewport center X, y = center Y - y (Y
; flip), returning the point.
;
; C equivalent:
;   long *r3d_vec2_long_translate_yflip(long *pt)
;   {
;       pt[0] += (long)g_nViewportCenterX;
;       pt[1] = (long)g_nViewportCenterY - pt[1];
;       return pt;
;   }
; ============================================================================
@pt equ word ptr ss:[bx+4]
	public _r3d_vec2_long_translate_yflip
_r3d_vec2_long_translate_yflip:
	mov BX,SP
	mov BX, @pt
	mov AX, word ptr CS:[g_nViewportCenterX]
	cwd
	add word ptr [BX], AX
	adc word ptr [BX+2], DX
	mov AX, word ptr CS:[g_nViewportCenterY]
	cwd
	sub AX, word ptr [BX+4]
	sbb DX, word ptr [BX+6]
	mov word ptr [BX+4], AX
	mov word ptr [BX+6], DX
	mov AX,BX
	retf

; ============================================================================
; _r3d_vec2_perspective_divide
;
; Perspective-divides a 2D point: scales each numerator (X,Y) by the view distance and divides
; by the shared depth (nDenom) via r3d_ldiv_helper, storing the two projected coords in *out.
; This is a standard perspective divide by depth: nProj = nNum * viewDist / nDepth.
;
; C equivalent:
;   PerspDiv2Result *r3d_vec2_perspective_divide(PerspDiv2Args *args,
;                                                PerspDiv2Result *out)
;   {
;       long projX;
;       long projY;
;
;       projX = args->nNumX;
;       projY = args->nNumY;
;
;       /* out = in * g_nActorFarClipThreshold / args->nDenom  (num/den per the
;          corrected ldiv ABI: den=[BP+12]=nDenom, num=[BP+16]=viewDist). */
;       r3d_ldiv_helper(&projX, &projY, args->nDenom, (long)g_nActorFarClipThreshold);
;
;       out->nProjX = projX;
;       out->nProjY = projY;
;       return out;
;   }
; ============================================================================
@args equ word ptr [bp+6]
@out equ word ptr [bp+8]
	public _r3d_vec2_perspective_divide
_r3d_vec2_perspective_divide:
	push BP
	mov BP,SP
	push SI
	mov SI, @args
	mov BP, @out
	xor AX,AX
	push AX
	push word ptr CS:[g_nViewPlaneDist]
	push word ptr [SI+6]
	push word ptr [SI+4]
	push word ptr [SI+10]
	push word ptr [SI+8]
	push word ptr [SI+2]
	push word ptr [SI]
	call _r3d_ldiv_helper
	pop word ptr [BP+0]
	pop word ptr [BP+2]
	pop word ptr [BP+4]
	pop word ptr [BP+6]
	add SP,8h
	mov AX,BP
	pop SI
	pop BP
	retf

; ============================================================================
; _r3d_actor_proj_scale_compute
;
; Computes an actor's screen-space projection scale as the fixed-point ratio
; (args->nNumX * g_nActorFarClipThreshold) / args->nDenom via the ldiv mul-div helper -- a
; half-extent scaled by the view distance over the clamped depth (shrinks with distance).
;
; C equivalent:
;   extern short far g_nActorFarClipThreshold;
;
;   long r3d_ldiv_helper(long *pScaledA, long *pScaledB, long den, long num);
;
;   long r3d_actor_proj_scale_compute(PerspDiv2Args *args)   /* structs.h:1249 */
;   {
;       long scale = args->nNumX;
;       long dummy = 0L;
;
;       /* Only nNumX and nDenom are read; nNumY is ignored here. Per the corrected
;          ldiv ABI: den=[BP+12]=args->nDenom (clamped depth),
;          num=[BP+16]=(long)g_nActorFarClipThreshold (view distance). */
;       r3d_ldiv_helper(&scale, &dummy, args->nDenom, (long)g_nActorFarClipThreshold);
;       return scale;   /* args->nNumX * viewDist / args->nDenom */
;   }
; ============================================================================
@args equ word ptr [bp+6]
	public _r3d_actor_proj_scale_compute
_r3d_actor_proj_scale_compute:
	push BP
	mov BP,SP
	push SI
	mov SI, @args
	xor AX,AX
	push AX
	push word ptr CS:[g_nViewPlaneDist]
	push word ptr [SI+6]
	push word ptr [SI+4]
	push AX
	push AX
	push word ptr [SI+2]
	push word ptr [SI]
	call _r3d_ldiv_helper
	pop AX
	pop DX
	add SP,0ch
	pop SI
	pop BP
	retf

; ============================================================================
; _r3d_imul_full32
;
; Signed 16x16->32-bit multiply; returns the full 32-bit product a*b in DX:AX.
;
; C equivalent:
;   long r3d_imul_full32(int a, int b)
;   {
;       return (long)a * b;
;   }
; ============================================================================
@a equ word ptr [bx+4]
@b equ word ptr [bx+6]
	public _r3d_imul_full32
_r3d_imul_full32:
	mov BX,SP
	mov AX, @a
	imul @b
	retf

; ============================================================================
; _r3d_dot3_coeff16_vec32
;
; Signed 3D dot product of a short vector (x,y,z) with three 32-bit coefficients, accumulated at
; full 48-bit precision; returns the top 32 bits.
;
; C equivalent:
;   long near r3d_dot3_coeff16_vec32(short x, short y, short z, long *coeffs)
;   {
;       long acc;
;       long term;
;       unsigned short accLo;
;
;       g_matXIn2 = x;
;       g_matYIn2 = y;
;       g_matZIn2 = z;
;
;       /* Each term is a 16-bit signed value times a 32-bit signed coefficient,
;          kept to full 48-bit precision.  The 48-bit running total is stored across
;          three scratch words: g_matXOut (high), g_matYOut (mid), g_matZOut (low). */
;
;       accLo = mul48_signed(x, coeffs[0], &acc);
;       g_matXOut = (unsigned short)(acc >> 16);
;       g_matYOut = (unsigned short)acc;
;       g_matZOut = accLo;
;
;       accLo = mul48_signed(y, coeffs[1], &term);
;       acc = add48(&accLo, term);
;       g_matXOut = (unsigned short)(acc >> 16);
;       g_matYOut = (unsigned short)acc;
;       g_matZOut = accLo;
;
;       if (z != 0) {
;           (void)mul48_signed(z, coeffs[2], &term);
;           acc = add48(&accLo, term);
;       }
;
;       g_matYOut = (unsigned short)(acc >> 16);
;       g_matZOut = (unsigned short)acc;
;       return acc;
;   }
;
;   /* Sign-magnitude multiply of a 16-bit signed value by a 32-bit signed
;      coefficient.  Returns the low 16 bits of the 48-bit product; the upper
;      32 bits are written through hi.  (Inlined in the asm, shown here for clarity.) */
;   static unsigned short mul48_signed(short v, long coeff, long *hi)
;   {
;       int negate;
;       unsigned short vMag;
;       unsigned long coeffMag;
;       unsigned short lo;
;       unsigned long mid;
;
;       negate = 0;
;       coeffMag = (unsigned long)coeff;
;       if (coeff < 0) {
;           negate = 1;
;           coeffMag = -coeffMag;
;       }
;       vMag = (unsigned short)v;
;       if (v < 0) {
;           negate ^= 1;
;           vMag = -vMag;
;       }
;
;       /* 48-bit product: (vMag * coeffLo) + (vMag * coeffHi << 16) */
;       lo = (unsigned short)((unsigned long)vMag * (unsigned short)coeffMag);
;       mid = (unsigned long)vMag * (unsigned short)(coeffMag >> 16)
;           + ((unsigned long)vMag * (unsigned short)coeffMag >> 16);
;
;       if (negate) {
;           /* two's-complement negate of the whole 48-bit magnitude */
;           lo = -lo;
;           mid = ~mid + (lo == 0);
;       }
;
;       *hi = (long)mid;
;       return lo;
;   }
; ============================================================================
	public _r3d_dot3_coeff16_vec32
_r3d_dot3_coeff16_vec32:
	push BX
	push SI
	mov word ptr ds:[g_matXIn2], AX
	mov word ptr ds:[g_matYIn2], CX
	mov word ptr ds:[g_matZIn2], DX
	mov SI,BX
	mov DX, word ptr [SI]
	mov BX, word ptr [SI+2]
	mov AX, word ptr ds:[g_matXIn2]
	push DI
	xor DI,DI
	or BX,BX
	jge @@xVecAbs
	or DI,1h
	NEG32 BX, DX
@@xVecAbs:
	or AX,AX
	jge @@xMul
	xor DI,1h
	neg AX
@@xMul:
	mov CX,AX
	mul DX
	xchg BX, DX
	xchg AX, CX
	mul DX
	add AX,BX
	adc DX,0h
	test DI,1h
	jz @@xStore
	not CX
	not AX
	not DX
	add CX,1h
	adc AX,0h
	adc DX,0h
@@xStore:
	pop DI
	mov word ptr ds:[g_matXOut], DX
	mov word ptr ds:[g_matYOut], AX
	mov word ptr ds:[g_matZOut], CX
	mov DX, word ptr [SI+4]
	mov BX, word ptr [SI+6]
	mov AX, word ptr ds:[g_matYIn2]
	push DI
	xor DI,DI
	or BX,BX
	jge @@yVecAbs
	or DI,1h
	NEG32 BX, DX
@@yVecAbs:
	or AX,AX
	jge @@yMul
	xor DI,1h
	neg AX
@@yMul:
	mov CX,AX
	mul DX
	xchg BX, DX
	xchg AX, CX
	mul DX
	add AX,BX
	adc DX,0h
	test DI,1h
	jz @@yStore
	not CX
	not AX
	not DX
	add CX,1h
	adc AX,0h
	adc DX,0h
@@yStore:
	pop DI
	add CX, word ptr ds:[g_matZOut]
	adc AX, word ptr ds:[g_matYOut]
	adc DX, word ptr ds:[g_matXOut]
	mov BX, word ptr ds:[g_matZIn2]
	or BX,BX
	jz @@done
	mov word ptr ds:[g_matXOut], DX
	mov word ptr ds:[g_matYOut], AX
	mov word ptr ds:[g_matZOut], CX
	mov AX,BX
	mov DX, word ptr [SI+8]
	mov BX, word ptr [SI+10]
	push DI
	xor DI,DI
	or BX,BX
	jge @@zVecAbs
	or DI,1h
	NEG32 BX, DX
@@zVecAbs:
	or AX,AX
	jge @@zMul
	xor DI,1h
	neg AX
@@zMul:
	mov CX,AX
	mul DX
	xchg BX, DX
	xchg AX, CX
	mul DX
	add AX,BX
	adc DX,0h
	test DI,1h
	jz @@zStore
	not CX
	not AX
	not DX
	add CX,1h
	adc AX,0h
	adc DX,0h
@@zStore:
	pop DI
	add CX, word ptr ds:[g_matZOut]
	adc AX, word ptr ds:[g_matYOut]
	adc DX, word ptr ds:[g_matXOut]
@@done:
	pop SI
	pop BX
	ret

; ============================================================================
; _r3d_mat3_xform_vec3_ll
;
; Transforms a 3-long input vector by a 3x3 matrix (with a kind byte selecting
; identity/2-row/3-row paths), scaling each dot product by 4, into a 3-long output vector.
;
; C equivalent:
;   void near r3d_mat3_xform_vec3_ll(long *inVec, short *mtx, long *outVec)
;   {
;       long dot;
;
;       switch (mtx[9]) {          /* kind byte at mtx + 18 */
;       case 0:
;           /* identity: pass the three input longs straight through */
;           outVec[0] = inVec[0];
;           outVec[1] = inVec[1];
;           outVec[2] = inVec[2];
;           break;
;
;       case 1:
;           /* two rows transformed, Z copied through untransformed */
;           dot = r3d_dot3_coeff16_vec32(inVec, mtx[0], mtx[3], mtx[6]);
;           outVec[0] = dot << 2;
;           dot = r3d_dot3_coeff16_vec32(inVec, mtx[1], mtx[4], mtx[7]);
;           outVec[1] = dot << 2;
;           outVec[2] = inVec[2];
;           break;
;
;       default:
;           /* full 3x3 transform */
;           dot = r3d_dot3_coeff16_vec32(inVec, mtx[0], mtx[3], mtx[6]);
;           outVec[0] = dot << 2;
;           dot = r3d_dot3_coeff16_vec32(inVec, mtx[1], mtx[4], mtx[7]);
;           outVec[1] = dot << 2;
;           dot = r3d_dot3_coeff16_vec32(inVec, mtx[2], mtx[5], mtx[8]);
;           outVec[2] = dot << 2;
;           break;
;       }
;   }
; ============================================================================
	public _r3d_mat3_xform_vec3_ll
_r3d_mat3_xform_vec3_ll:
	push SI
	push DI
	mov SI,BX
	mov DI,CX
	mov BX,AX
	mov AL, byte ptr [SI].mType
	or AL,AL
	jnz @@notIdentity
	push ES
	mov AX,DS
	mov ES,AX
	mov SI,BX
	mov CX,6h
	rep movsw
	pop ES
	jmp @@done
@@notIdentity:
	dec AL
	jz @@twoRows
	jmp short @@full3x3
@@twoRows:
	mov AX, word ptr [SI]
	mov CX, word ptr [SI+6]
	mov DX, word ptr [SI+12]
	call _r3d_dot3_coeff16_vec32
	Q14NORM48C
	mov word ptr [DI], AX
	mov word ptr [DI+2], DX
	mov AX, word ptr [SI+2]
	mov CX, word ptr [SI+8]
	mov DX, word ptr [SI+14]
	call _r3d_dot3_coeff16_vec32
	Q14NORM48C
	mov word ptr [DI+4], AX
	mov word ptr [DI+6], DX
	mov AX, word ptr [BX+8]
	mov DX, word ptr [BX+10]
	mov word ptr [DI+8], AX
	mov word ptr [DI+10], DX
	jmp short @@done
@@full3x3:
	mov AX, word ptr [SI]
	mov CX, word ptr [SI+6]
	mov DX, word ptr [SI+12]
	call _r3d_dot3_coeff16_vec32
	Q14NORM48C
	mov word ptr [DI], AX
	mov word ptr [DI+2], DX
	mov AX, word ptr [SI+2]
	mov CX, word ptr [SI+8]
	mov DX, word ptr [SI+14]
	call _r3d_dot3_coeff16_vec32
	Q14NORM48C
	mov word ptr [DI+4], AX
	mov word ptr [DI+6], DX
	mov AX, word ptr [SI+4]
	mov CX, word ptr [SI+10]
	mov DX, word ptr [SI+16]
	call _r3d_dot3_coeff16_vec32
	Q14NORM48C
	mov word ptr [DI+8], AX
	mov word ptr [DI+10], DX
@@done:
	pop DI
	pop SI
	ret

; Gap 0x1deb-0x1deb: 1B zero-init
	db 0
; ============================================================================
; _r3d_polygon_scissor_2d
;
; Sutherland-Hodgman clips the current mesh polygon against the viewport rectangle in two passes
; (X planes then Y planes), rewriting the CS-resident vertex arrays and updating the vertex
; count.
;
; C equivalent:
;   void r3d_polygon_scissor_2d(void)
;   {
;       int prevCode, curCode;
;       int prev, cur, out;
;       int clip;
;       int i;
;
;       if (g_nMeshPolyVertexCount < 2)
;           return;
;
;       /* -- Pass 1: clip against the left (xmin) and right (xmax) planes.
;             Reads g_aPolyInX/g_aPolyInY, writes g_aPolyClipX/g_aPolyClipY.
;             Outcode bit 1 = left of xmin, bit 2 = right of xmax. */
;       out = 0;
;       prev = g_nMeshPolyVertexCount - 1;
;       prevCode = 0;
;       if (g_aPolyInX[prev] < g_graphics_context.clip.xmin)
;           prevCode |= 1;
;       if (g_aPolyInX[prev] > g_graphics_context.clip.xmax)
;           prevCode |= 2;
;
;       for (cur = 0; cur < g_nMeshPolyVertexCount; cur++) {
;           curCode = 0;
;           if (g_aPolyInX[cur] < g_graphics_context.clip.xmin)
;               curCode |= 1;
;           if (g_aPolyInX[cur] > g_graphics_context.clip.xmax)
;               curCode |= 2;
;
;           if ((prevCode | curCode) == 0) {
;               /* Both endpoints inside: keep the current vertex. */
;               g_aPolyClipX[out] = g_aPolyInX[cur];
;               g_aPolyClipY[out] = g_aPolyInY[cur];
;               out++;
;           } else if ((prevCode & curCode) == 0) {
;               /* Edge crosses a plane (not trivially rejected). */
;               if (prevCode == 0) {
;                   /* prev inside, cur outside: emit the crossing only. */
;                   if (curCode & 1)
;                       clip = g_graphics_context.clip.xmin;
;                   else
;                       clip = g_graphics_context.clip.xmax;
;                   if ((curCode & 1) || (curCode & 2)) {
;                       g_aPolyClipX[out] = clip;
;                       g_aPolyClipY[out] = (int)((long)(g_aPolyInY[prev] -
;                           g_aPolyInY[cur]) * (clip - g_aPolyInX[cur]) /
;                           (g_aPolyInX[prev] - g_aPolyInX[cur])) +
;                           g_aPolyInY[cur];
;                       out++;
;                   }
;               } else if (curCode == 0) {
;                   /* prev outside, cur inside: emit crossing then cur. */
;                   if (prevCode & 1)
;                       clip = g_graphics_context.clip.xmin;
;                   else
;                       clip = g_graphics_context.clip.xmax;
;                   if ((prevCode & 1) || (prevCode & 2)) {
;                       g_aPolyClipX[out] = clip;
;                       g_aPolyClipY[out] = (int)((long)(g_aPolyInY[cur] -
;                           g_aPolyInY[prev]) * (clip - g_aPolyInX[prev]) /
;                           (g_aPolyInX[cur] - g_aPolyInX[prev])) +
;                           g_aPolyInY[prev];
;                       out++;
;                   }
;                   g_aPolyClipX[out] = g_aPolyInX[cur];
;                   g_aPolyClipY[out] = g_aPolyInY[cur];
;                   out++;
;               } else {
;                   /* Both outside but on opposite planes: emit two crossings. */
;                   clip = (prevCode & 1) ? g_graphics_context.clip.xmin
;                                         : g_graphics_context.clip.xmax;
;                   g_aPolyClipX[out] = clip;
;                   g_aPolyClipY[out] = (int)((long)(g_aPolyInY[cur] -
;                       g_aPolyInY[prev]) * (clip - g_aPolyInX[prev]) /
;                       (g_aPolyInX[cur] - g_aPolyInX[prev])) +
;                       g_aPolyInY[prev];
;                   out++;
;
;                   clip = (curCode & 1) ? g_graphics_context.clip.xmin
;                                        : g_graphics_context.clip.xmax;
;                   g_aPolyClipX[out] = clip;
;                   g_aPolyClipY[out] = (int)((long)(g_aPolyInY[prev] -
;                       g_aPolyInY[cur]) * (clip - g_aPolyInX[cur]) /
;                       (g_aPolyInX[prev] - g_aPolyInX[cur])) +
;                       g_aPolyInY[cur];
;                   out++;
;               }
;           }
;           prev = cur;
;           prevCode = curCode;
;       }
;
;       g_nMeshPolyVertexCount = out;
;       if (g_nMeshPolyVertexCount < 2) {
;           /* Degenerate result: copy the clipped buffer back verbatim. */
;           for (i = 0; i < g_nMeshPolyVertexCount; i++)
;               g_aPolyInX[i] = g_aPolyClipX[i];
;           for (i = 0; i < g_nMeshPolyVertexCount; i++)
;               g_aPolyInY[i] = g_aPolyClipY[i];
;           return;
;       }
;
;       /* -- Pass 2: clip against the top (ymax) and bottom (ymin) planes.
;             Reads g_aPolyClipX/g_aPolyClipY, writes back g_aPolyInX/g_aPolyInY.
;             Outcode bit 4 = below ymax, bit 8 = above ymin. */
;       out = 0;
;       prev = g_nMeshPolyVertexCount - 1;
;       prevCode = 0;
;       if (g_aPolyClipY[prev] > g_graphics_context.clip.ymax)
;           prevCode |= 4;
;       if (g_aPolyClipY[prev] < g_graphics_context.clip.ymin)
;           prevCode |= 8;
;
;       for (cur = 0; cur < g_nMeshPolyVertexCount; cur++) {
;           curCode = 0;
;           if (g_aPolyClipY[cur] > g_graphics_context.clip.ymax)
;               curCode |= 4;
;           if (g_aPolyClipY[cur] < g_graphics_context.clip.ymin)
;               curCode |= 8;
;
;           if ((prevCode | curCode) == 0) {
;               g_aPolyInX[out] = g_aPolyClipX[cur];
;               g_aPolyInY[out] = g_aPolyClipY[cur];
;               out++;
;           } else if ((prevCode & curCode) == 0) {
;               if (prevCode == 0) {
;                   if (curCode & 8)
;                       clip = g_graphics_context.clip.ymin;
;                   else
;                       clip = g_graphics_context.clip.ymax;
;                   if ((curCode & 8) || (curCode & 4)) {
;                       g_aPolyInY[out] = clip;
;                       g_aPolyInX[out] = (int)((long)(g_aPolyClipX[prev] -
;                           g_aPolyClipX[cur]) * (clip - g_aPolyClipY[cur]) /
;                           (g_aPolyClipY[prev] - g_aPolyClipY[cur])) +
;                           g_aPolyClipX[cur];
;                       out++;
;                   }
;               } else if (curCode == 0) {
;                   if (prevCode & 8)
;                       clip = g_graphics_context.clip.ymin;
;                   else
;                       clip = g_graphics_context.clip.ymax;
;                   if ((prevCode & 8) || (prevCode & 4)) {
;                       g_aPolyInY[out] = clip;
;                       g_aPolyInX[out] = (int)((long)(g_aPolyClipX[cur] -
;                           g_aPolyClipX[prev]) * (clip - g_aPolyClipY[prev]) /
;                           (g_aPolyClipY[cur] - g_aPolyClipY[prev])) +
;                           g_aPolyClipX[prev];
;                       out++;
;                   }
;                   g_aPolyInX[out] = g_aPolyClipX[cur];
;                   g_aPolyInY[out] = g_aPolyClipY[cur];
;                   out++;
;               } else {
;                   clip = (prevCode & 8) ? g_graphics_context.clip.ymin
;                                         : g_graphics_context.clip.ymax;
;                   g_aPolyInY[out] = clip;
;                   g_aPolyInX[out] = (int)((long)(g_aPolyClipX[cur] -
;                       g_aPolyClipX[prev]) * (clip - g_aPolyClipY[prev]) /
;                       (g_aPolyClipY[cur] - g_aPolyClipY[prev])) +
;                       g_aPolyClipX[prev];
;                   out++;
;
;                   clip = (curCode & 8) ? g_graphics_context.clip.ymin
;                                        : g_graphics_context.clip.ymax;
;                   g_aPolyInY[out] = clip;
;                   g_aPolyInX[out] = (int)((long)(g_aPolyClipX[prev] -
;                       g_aPolyClipX[cur]) * (clip - g_aPolyClipY[cur]) /
;                       (g_aPolyClipY[prev] - g_aPolyClipY[cur])) +
;                       g_aPolyClipX[cur];
;                   out++;
;               }
;           }
;           prev = cur;
;           prevCode = curCode;
;       }
;
;       g_nMeshPolyVertexCount = out;
;   }
; ============================================================================
	public _r3d_polygon_scissor_2d
_r3d_polygon_scissor_2d:
	push BP
	push SI
	push DI
	push ES
	mov AX,CS
	mov ES,AX
	xor DI,DI
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	cmp AX,2h
	jge @@xPassInit
	jmp @@done
@@xPassInit:
	dec AX
	mov BX,AX
	shl BX,1h
	xor CL,CL
	mov AX, word ptr [BX+g_aPolyInX]
	cmp AX, SS:word ptr [_g_graphics_context.nClip_xmin]
	jge @@xPrevChkXmax
	or CL,1h
@@xPrevChkXmax:
	cmp AX, SS:word ptr [_g_graphics_context.nClip_xmax]
	jle @@xPrevDone
	or CL,2h
@@xPrevDone:
	xor SI,SI
@@xPassNext:
	shl SI,1h
	xor CH,CH
	mov AX, word ptr [SI+g_aPolyInX]
	cmp AX, SS:word ptr [_g_graphics_context.nClip_xmin]
	jge @@xCurChkXmax
	or CH,1h
@@xCurChkXmax:
	cmp AX, SS:word ptr [_g_graphics_context.nClip_xmax]
	jle @@xCurDone
	or CH,2h
@@xCurDone:
	mov AL,CL
	or AL,CH
	jnz @@xNotBothIn
	mov AX, word ptr [SI+g_aPolyInX]
	mov word ptr [DI+g_aPolyClipX], AX
	mov AX, word ptr [SI+g_aPolyInY]
	mov word ptr [DI+g_aPolyClipY], AX
	add DI,2h
	jmp @@xAdvance
@@xNotBothIn:
	mov AL,CL
	and AL,CH
	jz @@xClip
	jmp @@xAdvance
@@xClip:
	or CL,CL
	jnz @@xCurInside
	test CH,1h
	jz @@xCurXmax
	mov AX, word ptr SS:[_g_graphics_context.nClip_xmin]
	mov word ptr [DI+g_aPolyClipX], AX
	sub AX, word ptr [SI+g_aPolyInX]
	mov BP,AX
	mov AX, word ptr [BX+g_aPolyInY]
	sub AX, word ptr [SI+g_aPolyInY]
	imul BP
	mov BP, word ptr [BX+g_aPolyInX]
	sub BP, word ptr [SI+g_aPolyInX]
	idiv BP
	add AX, word ptr [SI+g_aPolyInY]
	mov word ptr [DI+g_aPolyClipY], AX
	add DI,2h
	jmp short @@xEmitEnd
@@xCurXmax:
	test CH,2h
	jz @@xEmitEnd
	mov AX, word ptr SS:[_g_graphics_context.nClip_xmax]
	mov word ptr [DI+g_aPolyClipX], AX
	sub AX, word ptr [SI+g_aPolyInX]
	mov BP,AX
	mov AX, word ptr [BX+g_aPolyInY]
	sub AX, word ptr [SI+g_aPolyInY]
	imul BP
	mov BP, word ptr [BX+g_aPolyInX]
	sub BP, word ptr [SI+g_aPolyInX]
	idiv BP
	add AX, word ptr [SI+g_aPolyInY]
	mov word ptr [DI+g_aPolyClipY], AX
	add DI,2h
@@xEmitEnd:
	jmp @@xAdvance
@@xCurInside:
	or CH,CH
	jnz @@xBothOut
	test CL,1h
	jz @@xPrevXmax
	mov AX, word ptr SS:[_g_graphics_context.nClip_xmin]
	mov word ptr [DI+g_aPolyClipX], AX
	sub AX, word ptr [BX+g_aPolyInX]
	mov BP,AX
	mov AX, word ptr [SI+g_aPolyInY]
	sub AX, word ptr [BX+g_aPolyInY]
	imul BP
	mov BP, word ptr [SI+g_aPolyInX]
	sub BP, word ptr [BX+g_aPolyInX]
	idiv BP
	add AX, word ptr [BX+g_aPolyInY]
	mov word ptr [DI+g_aPolyClipY], AX
	add DI,2h
	jmp short @@xEmitCur
@@xPrevXmax:
	test CL,2h
	jz @@xEmitCur
	mov AX, word ptr SS:[_g_graphics_context.nClip_xmax]
	mov word ptr [DI+g_aPolyClipX], AX
	sub AX, word ptr [BX+g_aPolyInX]
	mov BP,AX
	mov AX, word ptr [SI+g_aPolyInY]
	sub AX, word ptr [BX+g_aPolyInY]
	imul BP
	mov BP, word ptr [SI+g_aPolyInX]
	sub BP, word ptr [BX+g_aPolyInX]
	idiv BP
	add AX, word ptr [BX+g_aPolyInY]
	mov word ptr [DI+g_aPolyClipY], AX
	add DI,2h
@@xEmitCur:
	mov AX, word ptr [SI+g_aPolyInX]
	mov word ptr [DI+g_aPolyClipX], AX
	mov AX, word ptr [SI+g_aPolyInY]
	mov word ptr [DI+g_aPolyClipY], AX
	add DI,2h
	jmp @@xAdvance
@@xBothOut:
	test CL,1h
	jz @@xBothPrevXmax
	mov AX, word ptr SS:[_g_graphics_context.nClip_xmin]
	mov word ptr [DI+g_aPolyClipX], AX
	sub AX, word ptr [BX+g_aPolyInX]
	mov BP,AX
	mov AX, word ptr [SI+g_aPolyInY]
	sub AX, word ptr [BX+g_aPolyInY]
	imul BP
	mov BP, word ptr [SI+g_aPolyInX]
	sub BP, word ptr [BX+g_aPolyInX]
	idiv BP
	add AX, word ptr [BX+g_aPolyInY]
	mov word ptr [DI+g_aPolyClipY], AX
	add DI,2h
	jmp short @@xBothCurXmin
@@xBothPrevXmax:
	test CL,2h
	jz @@xBothCurXmin
	mov AX, word ptr SS:[_g_graphics_context.nClip_xmax]
	mov word ptr [DI+g_aPolyClipX], AX
	sub AX, word ptr [BX+g_aPolyInX]
	mov BP,AX
	mov AX, word ptr [SI+g_aPolyInY]
	sub AX, word ptr [BX+g_aPolyInY]
	imul BP
	mov BP, word ptr [SI+g_aPolyInX]
	sub BP, word ptr [BX+g_aPolyInX]
	idiv BP
	add AX, word ptr [BX+g_aPolyInY]
	mov word ptr [DI+g_aPolyClipY], AX
	add DI,2h
@@xBothCurXmin:
	test CH,1h
	jz @@xBothCurXmax
	mov AX, word ptr SS:[_g_graphics_context.nClip_xmin]
	mov word ptr [DI+g_aPolyClipX], AX
	sub AX, word ptr [SI+g_aPolyInX]
	mov BP,AX
	mov AX, word ptr [BX+g_aPolyInY]
	sub AX, word ptr [SI+g_aPolyInY]
	imul BP
	mov BP, word ptr [BX+g_aPolyInX]
	sub BP, word ptr [SI+g_aPolyInX]
	idiv BP
	add AX, word ptr [SI+g_aPolyInY]
	mov word ptr [DI+g_aPolyClipY], AX
	add DI,2h
	jmp short @@xAdvance
@@xBothCurXmax:
	test CH,2h
	jz @@xAdvance
	mov AX, word ptr SS:[_g_graphics_context.nClip_xmax]
	mov word ptr [DI+g_aPolyClipX], AX
	sub AX, word ptr [SI+g_aPolyInX]
	mov BP,AX
	mov AX, word ptr [BX+g_aPolyInY]
	sub AX, word ptr [SI+g_aPolyInY]
	imul BP
	mov BP, word ptr [BX+g_aPolyInX]
	sub BP, word ptr [SI+g_aPolyInX]
	idiv BP
	add AX, word ptr [SI+g_aPolyInY]
	mov word ptr [DI+g_aPolyClipY], AX
	add DI,2h
@@xAdvance:
	mov BX,SI
	mov CL,CH
	shr SI,1h
	inc SI
	cmp SI, word ptr ds:[g_nMeshPolyVertexCount]
	jz @@xPassDone
	jmp @@xPassNext
@@xPassDone:
	shr DI,1h
	mov AX,DI
	mov word ptr ds:[g_nMeshPolyVertexCount], AX
	cmp AX,2h
	jge @@yPassInit
	jmp @@copyBack
@@yPassInit:
	dec AX
	mov BX,AX
	shl BX,1h
	xor CL,CL
	mov AX, word ptr [BX+g_aPolyClipY]
	cmp AX, SS:word ptr [_g_graphics_context.nClip_ymax]
	jle @@yPrevChkYmin
	or CL,4h
@@yPrevChkYmin:
	cmp AX, SS:word ptr [_g_graphics_context.nClip_ymin]
	jge @@yPrevDone
	or CL,8h
@@yPrevDone:
	xor DI,DI
	mov SI,DI
@@yPassNext:
	shl SI,1h
	xor CH,CH
	mov AX, word ptr [SI+g_aPolyClipY]
	cmp AX, SS:word ptr [_g_graphics_context.nClip_ymax]
	jle @@yCurChkYmin
	or CH,4h
@@yCurChkYmin:
	cmp AX, SS:word ptr [_g_graphics_context.nClip_ymin]
	jge @@yCurDone
	or CH,8h
@@yCurDone:
	mov AL,CL
	or AL,CH
	jnz @@yNotBothIn
	mov AX, word ptr [SI+g_aPolyClipX]
	mov word ptr [DI+g_aPolyInX], AX
	mov AX, word ptr [SI+g_aPolyClipY]
	mov word ptr [DI+g_aPolyInY], AX
	add DI,2h
	jmp @@yAdvance
@@yNotBothIn:
	mov AL,CL
	and AL,CH
	jz @@yClip
	jmp @@yAdvance
@@yClip:
	or CL,CL
	jnz @@yCurInside
	test CH,8h
	jz @@yCurYmax
	mov AX, word ptr SS:[_g_graphics_context.nClip_ymin]
	mov word ptr [DI+g_aPolyInY], AX
	sub AX, word ptr [SI+g_aPolyClipY]
	mov BP,AX
	mov AX, word ptr [BX+g_aPolyClipX]
	sub AX, word ptr [SI+g_aPolyClipX]
	imul BP
	mov BP, word ptr [BX+g_aPolyClipY]
	sub BP, word ptr [SI+g_aPolyClipY]
	idiv BP
	add AX, word ptr [SI+g_aPolyClipX]
	mov word ptr [DI+g_aPolyInX], AX
	add DI,2h
	jmp short @@yEmitEnd
@@yCurYmax:
	test CH,4h
	jz @@yEmitEnd
	mov AX, word ptr SS:[_g_graphics_context.nClip_ymax]
	mov word ptr [DI+g_aPolyInY], AX
	sub AX, word ptr [SI+g_aPolyClipY]
	mov BP,AX
	mov AX, word ptr [BX+g_aPolyClipX]
	sub AX, word ptr [SI+g_aPolyClipX]
	imul BP
	mov BP, word ptr [BX+g_aPolyClipY]
	sub BP, word ptr [SI+g_aPolyClipY]
	idiv BP
	add AX, word ptr [SI+g_aPolyClipX]
	mov word ptr [DI+g_aPolyInX], AX
	add DI,2h
@@yEmitEnd:
	jmp @@yAdvance
@@yCurInside:
	or CH,CH
	jnz @@yBothOut
	test CL,8h
	jz @@yPrevYmax
	mov AX, word ptr SS:[_g_graphics_context.nClip_ymin]
	mov word ptr [DI+g_aPolyInY], AX
	sub AX, word ptr [BX+g_aPolyClipY]
	mov BP,AX
	mov AX, word ptr [SI+g_aPolyClipX]
	sub AX, word ptr [BX+g_aPolyClipX]
	imul BP
	mov BP, word ptr [SI+g_aPolyClipY]
	sub BP, word ptr [BX+g_aPolyClipY]
	idiv BP
	add AX, word ptr [BX+g_aPolyClipX]
	mov word ptr [DI+g_aPolyInX], AX
	add DI,2h
	jmp short @@yEmitCur
@@yPrevYmax:
	test CL,4h
	jz @@yEmitCur
	mov AX, word ptr SS:[_g_graphics_context.nClip_ymax]
	mov word ptr [DI+g_aPolyInY], AX
	sub AX, word ptr [BX+g_aPolyClipY]
	mov BP,AX
	mov AX, word ptr [SI+g_aPolyClipX]
	sub AX, word ptr [BX+g_aPolyClipX]
	imul BP
	mov BP, word ptr [SI+g_aPolyClipY]
	sub BP, word ptr [BX+g_aPolyClipY]
	idiv BP
	add AX, word ptr [BX+g_aPolyClipX]
	mov word ptr [DI+g_aPolyInX], AX
	add DI,2h
@@yEmitCur:
	mov AX, word ptr [SI+g_aPolyClipX]
	mov word ptr [DI+g_aPolyInX], AX
	mov AX, word ptr [SI+g_aPolyClipY]
	mov word ptr [DI+g_aPolyInY], AX
	add DI,2h
	jmp @@yAdvance
@@yBothOut:
	test CL,8h
	jz @@yBothPrevYmax
	mov AX, word ptr SS:[_g_graphics_context.nClip_ymin]
	mov word ptr [DI+g_aPolyInY], AX
	sub AX, word ptr [BX+g_aPolyClipY]
	mov BP,AX
	mov AX, word ptr [SI+g_aPolyClipX]
	sub AX, word ptr [BX+g_aPolyClipX]
	imul BP
	mov BP, word ptr [SI+g_aPolyClipY]
	sub BP, word ptr [BX+g_aPolyClipY]
	idiv BP
	add AX, word ptr [BX+g_aPolyClipX]
	mov word ptr [DI+g_aPolyInX], AX
	add DI,2h
	jmp short @@yBothCurYmin
@@yBothPrevYmax:
	test CL,4h
	jz @@yBothCurYmin
	mov AX, word ptr SS:[_g_graphics_context.nClip_ymax]
	mov word ptr [DI+g_aPolyInY], AX
	sub AX, word ptr [BX+g_aPolyClipY]
	mov BP,AX
	mov AX, word ptr [SI+g_aPolyClipX]
	sub AX, word ptr [BX+g_aPolyClipX]
	imul BP
	mov BP, word ptr [SI+g_aPolyClipY]
	sub BP, word ptr [BX+g_aPolyClipY]
	idiv BP
	add AX, word ptr [BX+g_aPolyClipX]
	mov word ptr [DI+g_aPolyInX], AX
	add DI,2h
@@yBothCurYmin:
	test CH,8h
	jz @@yBothCurYmax
	mov AX, word ptr SS:[_g_graphics_context.nClip_ymin]
	mov word ptr [DI+g_aPolyInY], AX
	sub AX, word ptr [SI+g_aPolyClipY]
	mov BP,AX
	mov AX, word ptr [BX+g_aPolyClipX]
	sub AX, word ptr [SI+g_aPolyClipX]
	imul BP
	mov BP, word ptr [BX+g_aPolyClipY]
	sub BP, word ptr [SI+g_aPolyClipY]
	idiv BP
	add AX, word ptr [SI+g_aPolyClipX]
	mov word ptr [DI+g_aPolyInX], AX
	add DI,2h
	jmp short @@yAdvance
@@yBothCurYmax:
	test CH,4h
	jz @@yAdvance
	mov AX, word ptr SS:[_g_graphics_context.nClip_ymax]
	mov word ptr [DI+g_aPolyInY], AX
	sub AX, word ptr [SI+g_aPolyClipY]
	mov BP,AX
	mov AX, word ptr [BX+g_aPolyClipX]
	sub AX, word ptr [SI+g_aPolyClipX]
	imul BP
	mov BP, word ptr [BX+g_aPolyClipY]
	sub BP, word ptr [SI+g_aPolyClipY]
	idiv BP
	add AX, word ptr [SI+g_aPolyClipX]
	mov word ptr [DI+g_aPolyInX], AX
	add DI,2h
@@yAdvance:
	mov BX,SI
	mov CL,CH
	shr SI,1h
	inc SI
	cmp SI, word ptr ds:[g_nMeshPolyVertexCount]
	jz @@yPassDone
	jmp @@yPassNext
@@yPassDone:
	shr DI,1h
	mov AX,DI
	mov word ptr ds:[g_nMeshPolyVertexCount], AX
	jmp short @@done
@@copyBack:
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	mov CX,AX
	mov SI, offset g_aPolyClipX
	mov DI, offset g_aPolyInX
	rep movsw
	mov CX,AX
	mov SI, offset g_aPolyClipY
	mov DI, offset g_aPolyInY
	rep movsw
@@done:
	pop ES
	pop DI
	pop SI
	pop BP
	ret

; ============================================================================
; _r3d_interp_vertex_at_zclip
;
; Interpolates one polygon-edge vertex onto the near/far clip plane and writes its projected
; screen coordinates.
;
; C equivalent:
;   extern short g_aVertexCamX[256];
;   extern short g_aVertexCamY[256];
;   extern short g_aVertexCamZ[256];
;   extern short g_aVertexScrX[256];
;   extern short g_aVertexScrY[256];
;   extern short g_nActorFarClipThreshold;
;
;   /* a, b are register-passed (a=SI, b=BX), not stack args -- see Note. */
;   void r3d_interp_vertex_at_zclip(int a, int b)
;   {
;       int denom, num;
;
;       denom = g_aVertexCamY[a] - g_aVertexCamY[b];
;       num   = g_nActorFarClipThreshold - g_aVertexCamY[b];
;
;       g_aVertexScrX[b] = g_aVertexCamX[b] +
;           (int)((long)(g_aVertexCamX[a] - g_aVertexCamX[b]) * num / denom);
;
;       g_aVertexScrY[b] = g_aVertexCamZ[b] +
;           (int)((long)(g_aVertexCamZ[a] - g_aVertexCamZ[b]) * num / denom);
;   }
; ============================================================================
	public _r3d_interp_vertex_at_zclip
_r3d_interp_vertex_at_zclip:
	push CX
	mov AX, word ptr [SI+g_aVertexCamY]
	mov BP,AX
	mov AX, word ptr [BX+g_aVertexCamY]
	sub BP,AX
	mov DX,AX
	mov AX, word ptr ds:[g_nViewPlaneDist]
	sub AX,DX
	mov CX,AX
	mov AX, word ptr [SI+g_aVertexCamX]
	sub AX, word ptr [BX+g_aVertexCamX]
	imul CX
	idiv BP
	mov DX,AX
	mov AX, word ptr [BX+g_aVertexCamX]
	add AX,DX
	mov word ptr [BX+g_aVertexScrX], AX
	mov AX, word ptr [SI+g_aVertexCamZ]
	sub AX, word ptr [BX+g_aVertexCamZ]
	imul CX
	idiv BP
	mov DX,AX
	mov AX, word ptr [BX+g_aVertexCamZ]
	add AX,DX
	mov word ptr [BX+g_aVertexScrY], AX
	pop CX
	ret

; ============================================================================
; _r3d_polygon_clip_near_z
;
; Sutherland-Hodgman clip of the current polygon against the near-Z plane, emitting the clipped
; 2-D screen outline and updating the vertex count.
;
; C equivalent:
;   #define CLIP_BEHIND_NEAR 3
;
;   void near r3d_polygon_clip_near_z(void)
;   {
;       int prev;
;       int cur;
;       int i;
;       int outCursor;
;       unsigned char prevState;
;       unsigned char curState;
;
;       prev = g_polygon_vertices[g_nMeshPolyVertexCount - 1];
;       outCursor = 0;
;
;       for (i = 0; i < g_nMeshPolyVertexCount; i++) {
;           cur = g_polygon_vertices[i];
;           prevState = g_abPolygonClipState[prev];
;           curState = g_abPolygonClipState[cur];
;
;           if (curState == CLIP_BEHIND_NEAR) {
;               if (prevState != CLIP_BEHIND_NEAR) {
;                   r3d_interp_vertex_at_zclip();
;                   g_aPolyOutScrX[outCursor] = g_aVertexScrX[cur];
;                   g_aPolyOutScrY[outCursor] = g_aVertexScrY[cur];
;                   outCursor++;
;               }
;           } else if (prevState == CLIP_BEHIND_NEAR) {
;               r3d_interp_vertex_at_zclip();
;               g_aPolyOutScrX[outCursor] = g_aVertexScrX[prev];
;               g_aPolyOutScrY[outCursor] = g_aVertexScrY[prev];
;               outCursor++;
;               g_aPolyOutScrX[outCursor] = g_aVertexScrX[cur];
;               g_aPolyOutScrY[outCursor] = g_aVertexScrY[cur];
;               outCursor++;
;           } else {
;               g_aPolyOutScrX[outCursor] = g_aVertexScrX[cur];
;               g_aPolyOutScrY[outCursor] = g_aVertexScrY[cur];
;               outCursor++;
;           }
;
;           prev = cur;
;       }
;
;       g_nMeshPolyVertexCount = outCursor;
;   }
; ============================================================================
	public _r3d_polygon_clip_near_z
_r3d_polygon_clip_near_z:
	push BP
	push SI
	push DI
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	dec AX
	mov BX,AX
	shl BX,1h
	mov BX, word ptr [BX+g_polygon_vertices]
	xor CX,CX
	xor DI,DI
@@nextEdge:
	mov SI,CX
	mov SI, word ptr [SI+g_polygon_vertices]
	mov AL, byte ptr [BX+g_abPolygonClipState]	; AL = prevState
	mov AH, byte ptr [SI+g_abPolygonClipState]	; AH = curState
	cmp AH,3h
	jz @@curBehind			; cur behind near plane
	cmp AL,3h
	jz @@edgeEnters			; prev behind, cur in front: edge enters
	; both in front: emit cur unchanged
	mov AX, word ptr [SI+g_aVertexScrX]
	mov word ptr [DI+g_aPolyInX], AX
	mov AX, word ptr [SI+g_aVertexScrY]
	mov word ptr [DI+g_aPolyInY], AX
	add DI,2h
	jmp short @@advance
@@edgeEnters:
	call _r3d_interp_vertex_at_zclip	; clip prev at near plane
	mov AX, word ptr [BX+g_aVertexScrX]	; emit clipped prev
	mov word ptr [DI+g_aPolyInX], AX
	mov AX, word ptr [BX+g_aVertexScrY]
	mov word ptr [DI+g_aPolyInY], AX
	add DI,2h
	mov AX, word ptr [SI+g_aVertexScrX]	; emit cur
	mov word ptr [DI+g_aPolyInX], AX
	mov AX, word ptr [SI+g_aVertexScrY]
	mov word ptr [DI+g_aPolyInY], AX
	add DI,2h
	jmp short @@advance
@@curBehind:
	cmp AL,3h
	jz @@advance			; both behind: emit nothing
	; edge leaves: prev in front, cur behind
	xchg BX, SI
	call _r3d_interp_vertex_at_zclip	; clip cur at near plane
	xchg SI, BX
	mov AX, word ptr [SI+g_aVertexScrX]	; emit clipped cur
	mov word ptr [DI+g_aPolyInX], AX
	mov AX, word ptr [SI+g_aVertexScrY]
	mov word ptr [DI+g_aPolyInY], AX
	add DI,2h
@@advance:
	mov BX,SI			; prev = cur
	add CX,2h
	mov AX,CX
	shr AX,1h
	cmp AX, word ptr ds:[g_nMeshPolyVertexCount]
	jz @@done
	jmp @@nextEdge
@@done:
	mov AX,DI
	shr AX,1h
	mov word ptr ds:[g_nMeshPolyVertexCount], AX
	pop DI
	pop SI
	pop BP
	ret

; ============================================================================
; _r3d_apply_viewport_offset
;
; Bias all clipped polygon vertices into screen space: x += viewport center X, y = viewport
; center Y - y (math-Y to screen-Y flip).
;
; C equivalent:
;   void r3d_apply_viewport_offset(void)
;   {
;       short cx;
;       short cy;
;       short *px;
;       short *py;
;       unsigned n;
;
;       n = g_nMeshPolyVertexCount;
;       if (n == 0)
;           return;
;
;       cx = g_nViewportCenterX;
;       cy = g_nViewportCenterY;
;       px = g_anMeshPolyVertexX;
;       py = g_anMeshPolyVertexY;
;
;       do {
;           *px = cx + *px;
;           *py = cy - *py;
;           px++;
;           py++;
;       } while (--n != 0);
;   }
; ============================================================================
	public _r3d_apply_viewport_offset
_r3d_apply_viewport_offset:
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	mov CX,AX
	jcxz @@done
	push SI
	push DI
	mov BX, word ptr ds:[g_nViewportCenterX]
	mov DX, word ptr ds:[g_nViewportCenterY]
	mov SI, offset g_aPolyInX
	mov DI, offset g_aPolyInY
@@applyLoop:
	mov AX,BX
	add AX, word ptr [SI]
	mov word ptr [SI], AX
	mov AX,DX
	sub AX, word ptr [DI]
	mov word ptr [DI], AX
	add SI,2h
	add DI,2h
	loop @@applyLoop
	pop DI
	pop SI
@@done:
	ret

; ============================================================================
; _r3d_clip_interp_x_edge
;
; Sutherland-Hodgman clip of a polygon edge against the left (xmin) or right (xmax) viewport
; boundary: writes the boundary x and the linearly interpolated y into the output vertex slot.
;
; C equivalent:
;   /* Register convention (near, frameless): CX = clip-side flags (bit0 = clip
;      to xmin, bit1 = clip to xmax); BP -> "inside" vertex v1, SI -> "outside"
;      vertex v2, DI -> output vertex slot.  The inputs (v1, v2) index the INPUT
;      pool g_aPolyInX/Y (+ high-word halves); the output slot indexes the SEPARATE
;      clip scratch g_aPolyClipX/Y (+ high-word halves).  All are byte offsets and
;      the 32-bit x/y are split across low- and high-word arrays.  Only one
;      boundary is handled per call. */
;   void near r3d_clip_interp_x_edge(unsigned cxFlags, int v1, int v2, int outVert)
;   {
;       short xClip;
;       int dxNum;      /* xClip - v1.x, truncated to 16 bits */
;       int dxDen;      /* v2.x  - v1.x, truncated to 16 bits */
;       int dyEdge;     /* v2.y  - v1.y, truncated to 16 bits */
;       long yInterp;
;
;       if (cxFlags & 1)
;           xClip = g_graphics_context.clip.xmin;
;       else if (cxFlags & 2)
;           xClip = g_graphics_context.clip.xmax;
;       else
;           return;
;
;       /* out.x = the boundary coordinate, sign-extended to 32 bits (to clip scratch) */
;       *(short *)((char *)g_aPolyClipX    + outVert) = xClip;
;       *(short *)((char *)g_aPolyClipXHi  + outVert) = (short)(xClip >> 15);
;
;       /* 16-bit signed edge deltas (only the low words; from input pool) */
;       dxNum = xClip - *(short *)((char *)g_aPolyInX + v1);
;       dxDen = *(short *)((char *)g_aPolyInX + v2) - *(short *)((char *)g_aPolyInX + v1);
;       dyEdge = *(short *)((char *)g_aPolyInY + v2) - *(short *)((char *)g_aPolyInY + v1);
;
;       /* y = v1.y + (v2.y - v1.y) * (xClip - v1.x) / (v2.x - v1.x) */
;       yInterp = (long)((long)dyEdge * dxNum / dxDen);
;       yInterp += *(short *)((char *)g_aPolyInY + v1)
;                | ((long)*(short *)((char *)g_aPolyInYHi + v1) << 16);
;
;       *(short *)((char *)g_aPolyClipY   + outVert) = (short)yInterp;
;       *(short *)((char *)g_aPolyClipYHi + outVert) = (short)(yInterp >> 16);
;   }
; ============================================================================
	public _r3d_clip_interp_x_edge
_r3d_clip_interp_x_edge:
	test CL,1h
	jz @@tryXmax
	push CX
	mov AX, word ptr SS:[_g_graphics_context.nClip_xmin]
	cwd
	ST32 DI, g_aPolyClipX
	SUB32 g_aPolyInX
	mov BX,AX
	LD32 g_aPolyInX
	SUB32 g_aPolyInX
	mov CX,AX
	LD32 g_aPolyInY
	SUB32 g_aPolyInY
	imul BX
	idiv CX
	cwd
	ADD32 g_aPolyInY
	ST32 DI, g_aPolyClipY
	add DI,2h
	pop CX
	jmp short @@done
@@tryXmax:
	test CL,2h
	jz @@done
	push CX
	mov AX, word ptr SS:[_g_graphics_context.nClip_xmax]
	cwd
	ST32 DI, g_aPolyClipX
	SUB32 g_aPolyInX
	mov BX,AX
	LD32 g_aPolyInX
	SUB32 g_aPolyInX
	mov CX,AX
	LD32 g_aPolyInY
	SUB32 g_aPolyInY
	imul BX
	idiv CX
	cwd
	ADD32 g_aPolyInY
	ST32 DI, g_aPolyClipY
	add DI,2h
	pop CX
@@done:
	ret

; ============================================================================
; _r3d_clip_interp_y_edge
;
; Sutherland-Hodgman clip of one polygon edge against the top or bottom viewport Y edge,
; emitting the intersection vertex.
;
; C equivalent:
;   void r3d_clip_interp_y_edge(void)
;   {
;       long clipY;
;       int num, den, t;
;
;       if (edgeFlags & 8) {
;           clipY = g_graphics_context.clip.ymin;
;       } else if (edgeFlags & 4) {
;           clipY = g_graphics_context.clip.ymax;
;       } else {
;           return;
;       }
;
;       pOut->y = clipY;
;       pOut->yHi = clipY >> 15;
;
;       num = (int)pV2->x - (int)pV1->x;
;       den = (int)pV2->y - (int)pV1->y;
;       t   = (int)((long)num * (int)(clipY - pV1->y) / den);
;
;       pOut->x = (long)t + pV1->x;
;       pOut->xHi = ((long)t >> 15) + pV1->xHi + carry;
;
;       pOut++;
;   }
; ============================================================================
	public _r3d_clip_interp_y_edge
_r3d_clip_interp_y_edge:
	test CL,8h
	jz @@tryYmax
	push CX
	mov AX, word ptr SS:[_g_graphics_context.nClip_ymin]
	cwd
	ST32 DI, g_aPolyInY
	SUB32 g_aPolyClipY
	mov BX,AX
	LD32 g_aPolyClipY
	SUB32 g_aPolyClipY
	mov CX,AX
	LD32 g_aPolyClipX
	SUB32 g_aPolyClipX
	imul BX
	idiv CX
	cwd
	ADD32 g_aPolyClipX
	ST32 DI, g_aPolyInX
	add DI,2h
	pop CX
	jmp short @@done
@@tryYmax:
	test CL,4h
	jz @@done
	push CX
	mov AX, word ptr SS:[_g_graphics_context.nClip_ymax]
	cwd
	ST32 DI, g_aPolyInY
	SUB32 g_aPolyClipY
	mov BX,AX
	LD32 g_aPolyClipY
	SUB32 g_aPolyClipY
	mov CX,AX
	LD32 g_aPolyClipX
	SUB32 g_aPolyClipX
	imul BX
	idiv CX
	cwd
	ADD32 g_aPolyClipX
	ST32 DI, g_aPolyInX
	add DI,2h
	pop CX
@@done:
	ret

; ============================================================================
; _r3d_clip_polygon_to_viewport
;
; Sutherland-Hodgman clips the current mesh polygon to the viewport rectangle (x-min/x-max, then
; y-min/y-max) in place, using 32-bit fixed-point vertex coordinates.
;
; C equivalent:
;   #define MESH_POLY_MAX 20
;
;   extern long g_aPolyInX[MESH_POLY_MAX];
;   extern long g_aPolyInY[MESH_POLY_MAX];
;   extern long g_aPolyClipX[MESH_POLY_MAX];
;   extern long g_aPolyClipY[MESH_POLY_MAX];
;   extern int g_nMeshPolyVertexCount;
;
;   #define OC_XMIN 0x01
;   #define OC_XMAX 0x02
;   #define OC_YMAX 0x04
;   #define OC_YMIN 0x08
;
;   static int outcode_x(long x)
;   {
;       int high = (int)(x >> 16);
;       int code = 0;
;       if (high < 0 || (high == 0 && (unsigned)x < (unsigned)g_graphics_context.clip.xmin))
;           code |= OC_XMIN;
;       if (high > 0 || (high == 0 && (unsigned)g_graphics_context.clip.xmax < (unsigned)x))
;           code |= OC_XMAX;
;       return code;
;   }
;
;   static int outcode_y(long y)
;   {
;       int high = (int)(y >> 16);
;       int code = 0;
;       if (high < 0 || (high == 0 && (unsigned)y < (unsigned)g_graphics_context.clip.ymin))
;           code |= OC_YMIN;
;       if (high > 0 || (high == 0 && (unsigned)g_graphics_context.clip.ymax < (unsigned)y))
;           code |= OC_YMAX;
;       return code;
;   }
;
;   void r3d_clip_polygon_to_viewport(void)
;   {
;       int n, prev, cur, out;
;       int prevCode, curCode;
;
;       n = g_nMeshPolyVertexCount;
;       if (n < 2)
;           return;
;
;       /* ---- X pass: clip against x-min / x-max into the *Out scratch arrays ---- */
;       out = 0;
;       prev = n - 1;
;       prevCode = outcode_x(g_aPolyInX[prev]);
;       for (cur = 0; cur < n; cur++) {
;           curCode = outcode_x(g_aPolyInX[cur]);
;           if ((prevCode | curCode) == 0) {
;               g_aPolyClipX[out] = g_aPolyInX[cur];
;               g_aPolyClipY[out] = g_aPolyInY[cur];
;               out++;
;           } else if ((prevCode & curCode) == 0) {
;               if (prevCode == 0) {
;                   /* leaving: emit exit intersection only (prev inside, cur out) */
;                   r3d_clip_interp_x_edge(prev, cur, curCode, &out);
;               } else if (curCode == 0) {
;                   /* entering: emit entry intersection, then cur */
;                   r3d_clip_interp_x_edge(prev, cur, prevCode, &out);
;                   g_aPolyClipX[out] = g_aPolyInX[cur];
;                   g_aPolyClipY[out] = g_aPolyInY[cur];
;                   out++;
;               } else {
;                   /* crosses two edges: emit both intersections */
;                   r3d_clip_interp_x_edge(prev, cur, prevCode, &out);
;                   r3d_clip_interp_x_edge(prev, cur, curCode, &out);
;               }
;           }
;           prev = cur;
;           prevCode = curCode;
;       }
;       n = out;
;       g_nMeshPolyVertexCount = n;
;
;       if (n < 2) {
;           /* degenerate: copy scratch back to the main arrays verbatim */
;           int i;
;           for (i = 0; i < n; i++)
;               g_aPolyInX[i] = g_aPolyClipX[i];
;           for (i = 0; i < n; i++)
;               g_aPolyInY[i] = g_aPolyClipY[i];
;           return;
;       }
;
;       /* ---- Y pass: clip the *Out arrays against y-min / y-max back into main ---- */
;       out = 0;
;       prev = n - 1;
;       prevCode = outcode_y(g_aPolyClipY[prev]);
;       for (cur = 0; cur < n; cur++) {
;           curCode = outcode_y(g_aPolyClipY[cur]);
;           if ((prevCode | curCode) == 0) {
;               g_aPolyInX[out] = g_aPolyClipX[cur];
;               g_aPolyInY[out] = g_aPolyClipY[cur];
;               out++;
;           } else if ((prevCode & curCode) == 0) {
;               if (prevCode == 0) {
;                   r3d_clip_interp_y_edge(prev, cur, curCode, &out);
;               } else if (curCode == 0) {
;                   r3d_clip_interp_y_edge(prev, cur, prevCode, &out);
;                   g_aPolyInX[out] = g_aPolyClipX[cur];
;                   g_aPolyInY[out] = g_aPolyClipY[cur];
;                   out++;
;               } else {
;                   r3d_clip_interp_y_edge(prev, cur, prevCode, &out);
;                   r3d_clip_interp_y_edge(prev, cur, curCode, &out);
;               }
;           }
;           prev = cur;
;           prevCode = curCode;
;       }
;       g_nMeshPolyVertexCount = out;
;   }
; ============================================================================
	public _r3d_clip_polygon_to_viewport
_r3d_clip_polygon_to_viewport:
	push BP
	push SI
	push DI
	xor DI,DI
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	cmp AX,2h
	jge @@xPassInit
	jmp @@done
@@xPassInit:
	dec AX
	shl AX,1h
	mov BP,AX
	xor CL,CL
	mov AX, DS:word ptr [BP+g_aPolyInX]
	mov DX, DS:word ptr [BP+g_aPolyInXHi]
	cmp DX,0h
	jg @@xPrevChkXmax
	jl @@xPrevSetXmin
	cmp AX, SS:word ptr [_g_graphics_context.nClip_xmin]
	jnc @@xPrevChkXmax
@@xPrevSetXmin:
	or CL,1h
@@xPrevChkXmax:
	cmp DX,0h
	jl @@xPrevDone
	jg @@xPrevSetXmax
	cmp AX, SS:word ptr [_g_graphics_context.nClip_xmax]
	jbe @@xPrevDone
@@xPrevSetXmax:
	or CL,2h
@@xPrevDone:
	xor SI,SI
@@xPassNext:
	xor CH,CH
	LD32 g_aPolyInX
	cmp DX,0h
	jg @@xCurChkXmax
	jl @@xCurSetXmin
	cmp AX, SS:word ptr [_g_graphics_context.nClip_xmin]
	jnc @@xCurChkXmax
@@xCurSetXmin:
	or CH,1h
@@xCurChkXmax:
	cmp DX,0h
	jl @@xCurDone
	jg @@xCurSetXmax
	cmp AX, SS:word ptr [_g_graphics_context.nClip_xmax]
	jbe @@xCurDone
@@xCurSetXmax:
	or CH,2h
@@xCurDone:
	mov AL,CL
	or AL,CH
	jnz @@xNotBothIn
	LD32 g_aPolyInX
	ST32 DI, g_aPolyClipX
	LD32 g_aPolyInY
	ST32 DI, g_aPolyClipY
	add DI,2h
	jmp short @@xAdvance
@@xNotBothIn:
	mov AL,CL
	and AL,CH
	jnz @@xAdvance
	or CL,CL
	jnz @@xPrevOut
	xchg BP, SI
	xchg CL, CH
	call _r3d_clip_interp_x_edge
	xchg BP, SI
	xchg CL, CH
	jmp short @@xAdvance
@@xPrevOut:
	or CH,CH
	jnz @@xBothOut
	call _r3d_clip_interp_x_edge
	LD32 g_aPolyInX
	ST32 DI, g_aPolyClipX
	LD32 g_aPolyInY
	ST32 DI, g_aPolyClipY
	add DI,2h
	jmp short @@xAdvance
@@xBothOut:
	call _r3d_clip_interp_x_edge
	xchg BP, SI
	xchg CL, CH
	call _r3d_clip_interp_x_edge
	xchg BP, SI
	xchg CL, CH
@@xAdvance:
	mov BP,SI
	mov CL,CH
	add SI,2h
	mov AX,SI
	shr AX,1h
	cmp AX, word ptr ds:[g_nMeshPolyVertexCount]
	jz @@xPassDone
	jmp @@xPassNext
@@xPassDone:
	mov AX,DI
	shr AX,1h
	mov word ptr ds:[g_nMeshPolyVertexCount], AX
	cmp AX,2h
	jge @@yPassInit
	jmp @@copyBack
@@yPassInit:
	dec AX
	shl AX,1h
	mov BP,AX
	xor CL,CL
	mov AX, DS:word ptr [BP+g_aPolyClipY]
	mov DX, DS:word ptr [BP+g_aPolyClipYHi]
	cmp DX,0h
	jg @@yPrevChkYmax
	jl @@yPrevSetYmin
	cmp AX, SS:word ptr [_g_graphics_context.nClip_ymin]
	jnc @@yPrevChkYmax
@@yPrevSetYmin:
	or CL,8h
@@yPrevChkYmax:
	cmp DX,0h
	jl @@yPrevDone
	jg @@yPrevSetYmax
	cmp AX, SS:word ptr [_g_graphics_context.nClip_ymax]
	jbe @@yPrevDone
@@yPrevSetYmax:
	or CL,4h
@@yPrevDone:
	xor DI,DI
	mov SI,DI
@@yPassNext:
	xor CH,CH
	LD32 g_aPolyClipY
	cmp DX,0h
	jg @@yCurChkYmax
	jl @@yCurSetYmin
	cmp AX, SS:word ptr [_g_graphics_context.nClip_ymin]
	jnc @@yCurChkYmax
@@yCurSetYmin:
	or CH,8h
@@yCurChkYmax:
	cmp DX,0h
	jl @@yCurDone
	jg @@yCurSetYmax
	cmp AX, SS:word ptr [_g_graphics_context.nClip_ymax]
	jbe @@yCurDone
@@yCurSetYmax:
	or CH,4h
@@yCurDone:
	mov AL,CL
	or AL,CH
	jnz @@yNotBothIn
	LD32 g_aPolyClipX
	ST32 DI, g_aPolyInX
	LD32 g_aPolyClipY
	ST32 DI, g_aPolyInY
	add DI,2h
	jmp short @@yAdvance
@@yNotBothIn:
	mov AL,CL
	and AL,CH
	jnz @@yAdvance
	or CL,CL
	jnz @@yPrevOut
	xchg BP, SI
	xchg CL, CH
	call _r3d_clip_interp_y_edge
	xchg BP, SI
	xchg CL, CH
	jmp short @@yAdvance
@@yPrevOut:
	or CH,CH
	jnz @@yBothOut
	call _r3d_clip_interp_y_edge
	LD32 g_aPolyClipX
	ST32 DI, g_aPolyInX
	LD32 g_aPolyClipY
	ST32 DI, g_aPolyInY
	add DI,2h
	jmp short @@yAdvance
@@yBothOut:
	call _r3d_clip_interp_y_edge
	xchg BP, SI
	xchg CL, CH
	call _r3d_clip_interp_y_edge
	xchg BP, SI
	xchg CL, CH
@@yAdvance:
	mov BP,SI
	mov CL,CH
	add SI,2h
	mov AX,SI
	shr AX,1h
	cmp AX, word ptr ds:[g_nMeshPolyVertexCount]
	jz @@yPassDone
	jmp @@yPassNext
@@yPassDone:
	mov AX,DI
	shr AX,1h
	mov word ptr ds:[g_nMeshPolyVertexCount], AX
	jmp short @@done
@@copyBack:
	push ES
	mov AX,CS
	mov ES,AX
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	mov CX,AX
	mov SI, offset g_aPolyClipX
	mov DI, offset g_aPolyInX
	rep movsw
	mov CX,AX
	mov SI, offset g_aPolyClipY
	mov DI, offset g_aPolyInY
	rep movsw
	pop ES
@@done:
	pop DI
	pop SI
	pop BP
	ret

; ============================================================================
; _r3d_interp_vertex_at_zclip_long
;
; Interpolates a clipped mesh vertex onto the far-clip Z plane using the full 32-bit vertex
; coordinate arrays, writing the projected screen X/Y as longs.
;
; C equivalent:
;   void near r3d_interp_vertex_at_zclip_long(int aIdx, int bIdx)
;   {
;       int num;
;       int den;
;       int dx;
;
;       num = (int)((long)g_nActorFarClipThreshold - g_alVertexCamY[aIdx]);
;       den = (int)(g_alVertexCamY[bIdx] - g_alVertexCamY[aIdx]);
;
;       dx = (int)(g_alVertexCamX[bIdx] - g_alVertexCamX[aIdx]);
;       dx = (int)((long)dx * num / den);
;       g_alVertexScrX[aIdx] = g_alVertexCamX[aIdx] + (long)dx;
;
;       dx = (int)(g_alVertexCamZ[bIdx] - g_alVertexCamZ[aIdx]);
;       dx = (int)((long)dx * num / den);
;       g_alVertexScrY[aIdx] = g_alVertexCamZ[aIdx] + (long)dx;
;   }
; ============================================================================
	public _r3d_interp_vertex_at_zclip_long
_r3d_interp_vertex_at_zclip_long:
	push BX
	push CX
	mov AX, word ptr ds:[g_nViewPlaneDist]
	cwd
	SUB32 g_aVertexCamY
	mov BX,AX
	LD32 g_aVertexCamY
	SUB32 g_aVertexCamY
	mov CX,AX
	LD32 g_aVertexCamX
	SUB32 g_aVertexCamX
	imul BX
	idiv CX
	cwd
	ADD32 g_aVertexCamX
	mov DS:word ptr [BP+g_aVertexScrX], AX
	mov DS:word ptr [BP+g_aVertexScrXHi], DX
	LD32 g_aVertexCamZ
	SUB32 g_aVertexCamZ
	imul BX
	idiv CX
	cwd
	ADD32 g_aVertexCamZ
	mov DS:word ptr [BP+g_aVertexScrY], AX
	mov DS:word ptr [BP+g_aVertexScrYHi], DX
	pop CX
	pop BX
	ret

; ============================================================================
; _r3d_polygon_clip_against_zplane
;
; Sutherland-Hodgman clip of the current polygon against the near-Z plane, emitting the clipped
; screen/clip vertex list and updating the vertex count.
;
; The emit copies each vertex's 32-bit screen X and Y (low + high word halves)
; from the per-vertex table g_aVertexScr{X,Y}/{X,Y}Hi (indexed by the vertex's
; byte offset) into the polygon-input arrays g_aPolyIn{X,Y}/{X,Y}Hi (indexed by
; the output byte offset), exactly the COPYVTX2IN move set. As in
; r3d_poly_emit_screen_or_world, VTX_WORD(arr, off)/VTX_BYTE(arr, off) denote
; arr indexed by the pre-doubled byte offset 'off' (g_polygon_vertices[] stores
; vertexIndex*2, and dstIdx/srcIdx step by 2).
;
; C equivalent:
;   void near r3d_polygon_clip_against_zplane(void)
;   {
;       int prevVtx;        /* byte offset of previous vertex into the per-vertex arrays */
;       int curVtx;         /* byte offset of current vertex into the per-vertex arrays  */
;       unsigned srcIdx;    /* byte index into g_polygon_vertices[] */
;       unsigned dstIdx;    /* byte index into the emitted g_aPolyIn* arrays */
;
;       srcIdx = 0;
;       dstIdx = 0;
;
;       /* Start with the last vertex as "previous" so the polygon wraps closed. */
;       prevVtx = g_polygon_vertices[g_nMeshPolyVertexCount - 1];
;
;       do {
;           curVtx = VTX_WORD(g_polygon_vertices, srcIdx);
;
;           if (VTX_BYTE(g_abPolygonClipState, curVtx) == CLIPST_BEHIND) {
;               /* Current vertex is behind the near plane. */
;               if (VTX_BYTE(g_abPolygonClipState, prevVtx) != CLIPST_BEHIND) {
;                   /* Edge exits the visible half-space: emit the intersection. */
;                   r3d_interp_vertex_at_zclip_long();
;                   VTX_WORD(g_aPolyInX,   dstIdx) = VTX_WORD(g_aVertexScrX,   curVtx);
;                   VTX_WORD(g_aPolyInXHi, dstIdx) = VTX_WORD(g_aVertexScrXHi, curVtx);
;                   VTX_WORD(g_aPolyInY,   dstIdx) = VTX_WORD(g_aVertexScrY,   curVtx);
;                   VTX_WORD(g_aPolyInYHi, dstIdx) = VTX_WORD(g_aVertexScrYHi, curVtx);
;                   dstIdx += 2;
;               }
;               /* else: both endpoints behind -> emit nothing. */
;           }
;           else if (VTX_BYTE(g_abPolygonClipState, prevVtx) == CLIPST_BEHIND) {
;               /* Edge enters the visible half-space: emit intersection, then current. */
;               r3d_interp_vertex_at_zclip_long();
;               VTX_WORD(g_aPolyInX,   dstIdx)     = VTX_WORD(g_aVertexScrX,   prevVtx);
;               VTX_WORD(g_aPolyInXHi, dstIdx)     = VTX_WORD(g_aVertexScrXHi, prevVtx);
;               VTX_WORD(g_aPolyInY,   dstIdx)     = VTX_WORD(g_aVertexScrY,   prevVtx);
;               VTX_WORD(g_aPolyInYHi, dstIdx)     = VTX_WORD(g_aVertexScrYHi, prevVtx);
;
;               VTX_WORD(g_aPolyInX,   dstIdx + 2) = VTX_WORD(g_aVertexScrX,   curVtx);
;               VTX_WORD(g_aPolyInXHi, dstIdx + 2) = VTX_WORD(g_aVertexScrXHi, curVtx);
;               VTX_WORD(g_aPolyInY,   dstIdx + 2) = VTX_WORD(g_aVertexScrY,   curVtx);
;               VTX_WORD(g_aPolyInYHi, dstIdx + 2) = VTX_WORD(g_aVertexScrYHi, curVtx);
;               dstIdx += 4;
;           }
;           else {
;               /* Both endpoints in front: emit current vertex unchanged. */
;               VTX_WORD(g_aPolyInX,   dstIdx) = VTX_WORD(g_aVertexScrX,   curVtx);
;               VTX_WORD(g_aPolyInXHi, dstIdx) = VTX_WORD(g_aVertexScrXHi, curVtx);
;               VTX_WORD(g_aPolyInY,   dstIdx) = VTX_WORD(g_aVertexScrY,   curVtx);
;               VTX_WORD(g_aPolyInYHi, dstIdx) = VTX_WORD(g_aVertexScrYHi, curVtx);
;               dstIdx += 2;
;           }
;
;           prevVtx = curVtx;
;           srcIdx += 2;
;       } while (srcIdx >> 1 != g_nMeshPolyVertexCount);
;
;       g_nMeshPolyVertexCount = dstIdx >> 1;
;   }
; ============================================================================
	public _r3d_polygon_clip_against_zplane
_r3d_polygon_clip_against_zplane:
	push BP
	push SI
	push DI
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	dec AX
	mov BP,AX
	shl BP,1h
	mov BP, DS:word ptr [BP+g_polygon_vertices]
	xor CX,CX
	xor DI,DI
@@nextEdge:
	mov SI,CX
	mov SI, word ptr [SI+g_polygon_vertices]
	mov AL, DS:byte ptr [BP+g_abPolygonClipState]
	mov AH, byte ptr [SI+g_abPolygonClipState]
	cmp AH,3h
	jz @@curBehind
	cmp AL,3h
	jz @@prevBehind
	COPYVTX2IN
	add DI,2h
	jmp short @@advance
@@prevBehind:
	call _r3d_interp_vertex_at_zclip_long
	mov AX, DS:word ptr [BP+g_aVertexScrX]
	mov word ptr [DI+g_aPolyInX], AX
	mov AX, DS:word ptr [BP+g_aVertexScrXHi]
	mov word ptr [DI+g_aPolyInXHi], AX
	mov AX, DS:word ptr [BP+g_aVertexScrY]
	mov word ptr [DI+g_aPolyInY], AX
	mov AX, DS:word ptr [BP+g_aVertexScrYHi]
	mov word ptr [DI+g_aPolyInYHi], AX
	add DI,2h
	COPYVTX2IN
	add DI,2h
	jmp short @@advance
@@curBehind:
	cmp AL,3h
	jz @@advance
	xchg BP, SI
	call _r3d_interp_vertex_at_zclip_long
	xchg SI, BP
	COPYVTX2IN
	add DI,2h
@@advance:
	mov BP,SI
	add CX,2h
	mov AX,CX
	shr AX,1h
	cmp AX, word ptr ds:[g_nMeshPolyVertexCount]
	jz @@done
	jmp @@nextEdge
@@done:
	mov AX,DI
	shr AX,1h
	mov word ptr ds:[g_nMeshPolyVertexCount], AX
	pop DI
	pop SI
	pop BP
	ret

; Gap 0x28c5-0x28c5: 1B zero-init
	db 0
; ============================================================================
; _r3d_polygon_clip_edge_intersect
;
; Sutherland-Hodgman helper that intersects a polygon edge with a vertical viewport clip line
; (xmin or xmax) and appends the clipped vertex to the output arrays.
;
; C equivalent:
;   /* origin = the interpolation-origin endpoint (BP-based, all deltas are
;      taken relative to it); other = the far endpoint (SI-based). Callers swap
;      BP/SI to choose which physical vertex plays the origin role. */
;   void r3d_polygon_clip_edge_intersect(unsigned char clipSide,
;                                        long far *other, long far *origin,
;                                        long far *out)
;   {
;       long clipX;
;       long t;
;       long deltaY, deltaX;
;
;       if (clipSide & 1) {
;           clipX = g_graphics_context.clip.xmin;
;       } else if (clipSide & 2) {
;           clipX = g_graphics_context.clip.xmax;
;       } else {
;           return;
;       }
;
;       out[0] = clipX;
;
;       t      = clipX    - origin[0];   /* num = xClip - originX */
;       deltaX = other[0] - origin[0];   /* den */
;       deltaY = other[1] - origin[1];   /* pScaledA, scaled by num/den */
;
;       /* corrected ldiv ABI (pScaledA, pScaledB, den, num): pScaledA=deltaY,
;          pScaledB=0, den=deltaX, num=t -> returns deltaY * t / deltaX. */
;       out[1] = origin[1] + r3d_ldiv_helper(&deltaY, /*&dummy*/ 0L, deltaX, t);
;   }
; ============================================================================
	public _r3d_polygon_clip_edge_intersect
_r3d_polygon_clip_edge_intersect:
	test CL,1h
	jz @@tryXmax
	push CX
	mov AX, word ptr SS:[_g_graphics_context.nClip_xmin]
	cwd
	ST32 DI, g_aPolyClipX
	SUB32 g_aPolyInX
	push DX
	push AX
	LD32 g_aPolyInX
	SUB32 g_aPolyInX
	push DX
	push AX
	xor AX,AX
	push AX
	push AX
	LD32 g_aPolyInY
	SUB32 g_aPolyInY
	push DX
	push AX
	call _r3d_ldiv_helper
	pop AX
	pop DX
	add SP,0ch
	ADD32 g_aPolyInY
	ST32 DI, g_aPolyClipY
	add DI,2h
	pop CX
	jmp short @@done
@@tryXmax:
	test CL,2h
	jz @@done
	push CX
	mov AX, word ptr SS:[_g_graphics_context.nClip_xmax]
	cwd
	ST32 DI, g_aPolyClipX
	SUB32 g_aPolyInX
	push DX
	push AX
	LD32 g_aPolyInX
	SUB32 g_aPolyInX
	push DX
	push AX
	xor AX,AX
	push AX
	push AX
	LD32 g_aPolyInY
	SUB32 g_aPolyInY
	push DX
	push AX
	call _r3d_ldiv_helper
	pop AX
	pop DX
	add SP,0ch
	ADD32 g_aPolyInY
	ST32 DI, g_aPolyClipY
	add DI,2h
	pop CX
@@done:
	ret

; ============================================================================
; _r3d_clip_polygon_edge_y
;
; Sutherland-Hodgman intersection of one polygon edge with the active horizontal (Y) clip line,
; emitting the clipped vertex into the output clip buffer.
;
; C equivalent:
;   void r3d_clip_polygon_edge_y(void)
;   {
;       long clipY;
;       long xDelta;
;       long yToClip;
;       long yEdge;
;       long clippedX;
;
;       if (g_edgeClipFlags & CLIP_YMIN) {
;           clipY = (long)g_graphics_context.clip.ymin;
;           g_aClipYA[g_outIdx] = clipY;
;
;           yToClip = clipY - g_aClipYB[g_prevIdx];
;           yEdge   = g_aClipYB[g_curIdx] - g_aClipYB[g_prevIdx];
;           xDelta  = g_aClipXB[g_curIdx] - g_aClipXB[g_prevIdx];
;
;           clippedX = r3d_ldiv_helper(xDelta, 0L, yEdge, yToClip);
;           g_aClipXA[g_outIdx] = clippedX + g_aClipXB[g_prevIdx];
;           g_outIdx++;
;       } else if (g_edgeClipFlags & CLIP_YMAX) {
;           clipY = (long)g_graphics_context.clip.ymax;
;           g_aClipYA[g_outIdx] = clipY;
;
;           yToClip = clipY - g_aClipYB[g_prevIdx];
;           yEdge   = g_aClipYB[g_curIdx] - g_aClipYB[g_prevIdx];
;           xDelta  = g_aClipXB[g_curIdx] - g_aClipXB[g_prevIdx];
;
;           clippedX = r3d_ldiv_helper(xDelta, 0L, yEdge, yToClip);
;           g_aClipXA[g_outIdx] = clippedX + g_aClipXB[g_prevIdx];
;           g_outIdx++;
;       }
;   }
; ============================================================================
	public _r3d_clip_polygon_edge_y
_r3d_clip_polygon_edge_y:
	test CL,8h
	jz @@tryYmax
	push CX
	mov AX, word ptr SS:[_g_graphics_context.nClip_ymin]
	cwd
	ST32 DI, g_aPolyInY
	SUB32 g_aPolyClipY
	push DX
	push AX
	LD32 g_aPolyClipY
	SUB32 g_aPolyClipY
	push DX
	push AX
	xor AX,AX
	push AX
	push AX
	LD32 g_aPolyClipX
	SUB32 g_aPolyClipX
	push DX
	push AX
	call _r3d_ldiv_helper
	pop AX
	pop DX
	add SP,0ch
	ADD32 g_aPolyClipX
	ST32 DI, g_aPolyInX
	add DI,2h
	pop CX
	jmp short @@done
@@tryYmax:
	test CL,4h
	jz @@done
	push CX
	mov AX, word ptr SS:[_g_graphics_context.nClip_ymax]
	cwd
	ST32 DI, g_aPolyInY
	SUB32 g_aPolyClipY
	push DX
	push AX
	LD32 g_aPolyClipY
	SUB32 g_aPolyClipY
	push DX
	push AX
	xor AX,AX
	push AX
	push AX
	LD32 g_aPolyClipX
	SUB32 g_aPolyClipX
	push DX
	push AX
	call _r3d_ldiv_helper
	pop AX
	pop DX
	add SP,0ch
	ADD32 g_aPolyClipX
	ST32 DI, g_aPolyInX
	add DI,2h
	pop CX
@@done:
	ret

; ============================================================================
; _r3d_polygon_clip_rect_2d
;
; Sutherland-Hodgman clip of the working polygon against the 2D screen clip rectangle: an X pass
; (xmin/xmax) then a Y pass (ymin/ymax), rewriting the vertex count.
;
; C equivalent:
;   #define CLIP_BELOW_XMIN 0x01
;   #define CLIP_ABOVE_XMAX 0x02
;   #define CLIP_ABOVE_YMAX 0x04
;   #define CLIP_BELOW_YMIN 0x08
;
;   void near r3d_polygon_clip_rect_2d(void)
;   {
;       int n, i, out;
;       int prevX, prevY;
;       int curX, curY;
;       unsigned char prevCode, curCode;
;
;       n = g_nMeshPolyVertexCount;
;       if (n < 2)
;           return;
;
;       /* ---- X pass: clip A buffer -> B buffer against xmin / xmax ---- */
;       out = 0;
;       prevX = g_polyAx[n - 1];
;       prevW = g_polyAxDenom[n - 1];
;       prevCode = 0;
;       if (prevW < 0 || (prevW == 0 &&
;           (unsigned)prevX < (unsigned)g_graphics_context.clip.xmin))
;           prevCode |= CLIP_BELOW_XMIN;
;       if (prevW > 0 || (prevW == 0 &&
;           (unsigned)g_graphics_context.clip.xmax < (unsigned)prevX))
;           prevCode |= CLIP_ABOVE_XMAX;
;
;       for (i = 0; i < n; i++) {
;           curX = g_polyAx[i];
;           curW = g_polyAxDenom[i];
;           curCode = 0;
;           if (curW < 0 || (curW == 0 &&
;               (unsigned)curX < (unsigned)g_graphics_context.clip.xmin))
;               curCode |= CLIP_BELOW_XMIN;
;           if (curW > 0 || (curW == 0 &&
;               (unsigned)g_graphics_context.clip.xmax < (unsigned)curX))
;               curCode |= CLIP_ABOVE_XMAX;
;
;           if ((prevCode | curCode) == 0) {
;               /* whole edge inside: emit current vertex */
;               g_polyBx[out] = g_polyAx[i];
;               g_polyBxDenom[out] = g_polyAxDenom[i];
;               g_polyBy[out] = g_polyAy[i];
;               g_polyByDenom[out] = g_polyAyDenom[i];
;               out++;
;           } else if ((prevCode & curCode) == 0) {
;               /* edge straddles a boundary: emit intersection(s) */
;               if (prevCode == 0) {
;                   r3d_polygon_clip_edge_intersect();
;               } else if (curCode == 0) {
;                   r3d_polygon_clip_edge_intersect();
;                   g_polyBx[out] = g_polyAx[i];
;                   g_polyBxDenom[out] = g_polyAxDenom[i];
;                   g_polyBy[out] = g_polyAy[i];
;                   g_polyByDenom[out] = g_polyAyDenom[i];
;                   out++;
;               } else {
;                   r3d_polygon_clip_edge_intersect();
;                   r3d_polygon_clip_edge_intersect();
;               }
;           }
;           prevCode = curCode;
;       }
;
;       n = out;
;       g_nMeshPolyVertexCount = n;
;       if (n < 2) {
;           /* degenerate: copy B buffer straight back to A and stop */
;           for (i = 0; i < n; i++) {
;               g_polyAx[i] = g_polyBx[i];
;               g_polyAxDenom[i] = g_polyBxDenom[i];
;           }
;           for (i = 0; i < n; i++) {
;               g_polyAy[i] = g_polyBy[i];
;               g_polyAyDenom[i] = g_polyByDenom[i];
;           }
;           return;
;       }
;
;       /* ---- Y pass: clip B buffer -> A buffer against ymin / ymax ---- */
;       out = 0;
;       prevY = g_polyBy[n - 1];
;       prevW = g_polyByDenom[n - 1];
;       prevCode = 0;
;       if (prevW < 0 || (prevW == 0 &&
;           (unsigned)prevY < (unsigned)g_graphics_context.clip.ymin))
;           prevCode |= CLIP_BELOW_YMIN;
;       if (prevW > 0 || (prevW == 0 &&
;           (unsigned)g_graphics_context.clip.ymax < (unsigned)prevY))
;           prevCode |= CLIP_ABOVE_YMAX;
;
;       for (i = 0; i < n; i++) {
;           curY = g_polyBy[i];
;           curW = g_polyByDenom[i];
;           curCode = 0;
;           if (curW < 0 || (curW == 0 &&
;               (unsigned)curY < (unsigned)g_graphics_context.clip.ymin))
;               curCode |= CLIP_BELOW_YMIN;
;           if (curW > 0 || (curW == 0 &&
;               (unsigned)g_graphics_context.clip.ymax < (unsigned)curY))
;               curCode |= CLIP_ABOVE_YMAX;
;
;           if ((prevCode | curCode) == 0) {
;               g_polyAx[out] = g_polyBx[i];
;               g_polyAxDenom[out] = g_polyBxDenom[i];
;               g_polyAy[out] = g_polyBy[i];
;               g_polyAyDenom[out] = g_polyByDenom[i];
;               out++;
;           } else if ((prevCode & curCode) == 0) {
;               if (prevCode == 0) {
;                   r3d_clip_polygon_edge_y();
;               } else if (curCode == 0) {
;                   r3d_clip_polygon_edge_y();
;                   g_polyAx[out] = g_polyBx[i];
;                   g_polyAxDenom[out] = g_polyBxDenom[i];
;                   g_polyAy[out] = g_polyBy[i];
;                   g_polyAyDenom[out] = g_polyByDenom[i];
;                   out++;
;               } else {
;                   r3d_clip_polygon_edge_y();
;                   r3d_clip_polygon_edge_y();
;               }
;           }
;           prevCode = curCode;
;       }
;
;       g_nMeshPolyVertexCount = out;
;   }
; ============================================================================
	public _r3d_polygon_clip_rect_2d
_r3d_polygon_clip_rect_2d:
	push BP
	push SI
	push DI
	xor DI,DI
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	cmp AX,2h
	jge @@xPassInit
	jmp @@done
@@xPassInit:
	dec AX
	shl AX,1h
	mov BP,AX
	xor CL,CL
	mov AX, DS:word ptr [BP+g_aPolyInX]
	mov DX, DS:word ptr [BP+g_aPolyInXHi]
	cmp DX,0h
	jg @@xPrevChkXmax
	jl @@xPrevSetXmin
	cmp AX, SS:word ptr [_g_graphics_context.nClip_xmin]
	jnc @@xPrevChkXmax
@@xPrevSetXmin:
	or CL,1h
@@xPrevChkXmax:
	cmp DX,0h
	jl @@xPrevDone
	jg @@xPrevSetXmax
	cmp AX, SS:word ptr [_g_graphics_context.nClip_xmax]
	jbe @@xPrevDone
@@xPrevSetXmax:
	or CL,2h
@@xPrevDone:
	xor SI,SI
@@xPassNext:
	xor CH,CH
	LD32 g_aPolyInX
	cmp DX,0h
	jg @@xCurChkXmax
	jl @@xCurSetXmin
	cmp AX, SS:word ptr [_g_graphics_context.nClip_xmin]
	jnc @@xCurChkXmax
@@xCurSetXmin:
	or CH,1h
@@xCurChkXmax:
	cmp DX,0h
	jl @@xCurDone
	jg @@xCurSetXmax
	cmp AX, SS:word ptr [_g_graphics_context.nClip_xmax]
	jbe @@xCurDone
@@xCurSetXmax:
	or CH,2h
@@xCurDone:
	mov AL,CL
	or AL,CH
	jnz @@xNotBothIn
	LD32 g_aPolyInX
	ST32 DI, g_aPolyClipX
	LD32 g_aPolyInY
	ST32 DI, g_aPolyClipY
	add DI,2h
	jmp short @@xAdvance
@@xNotBothIn:
	mov AL,CL
	and AL,CH
	jnz @@xAdvance
	or CL,CL
	jnz @@xPrevOut
	xchg BP, SI
	xchg CL, CH
	call _r3d_polygon_clip_edge_intersect
	xchg BP, SI
	xchg CL, CH
	jmp short @@xAdvance
@@xPrevOut:
	or CH,CH
	jnz @@xBothOut
	call _r3d_polygon_clip_edge_intersect
	LD32 g_aPolyInX
	ST32 DI, g_aPolyClipX
	LD32 g_aPolyInY
	ST32 DI, g_aPolyClipY
	add DI,2h
	jmp short @@xAdvance
@@xBothOut:
	call _r3d_polygon_clip_edge_intersect
	xchg BP, SI
	xchg CL, CH
	call _r3d_polygon_clip_edge_intersect
	xchg BP, SI
	xchg CL, CH
@@xAdvance:
	mov BP,SI
	mov CL,CH
	add SI,2h
	mov AX,SI
	shr AX,1h
	cmp AX, word ptr ds:[g_nMeshPolyVertexCount]
	jz @@xPassDone
	jmp @@xPassNext
@@xPassDone:
	mov AX,DI
	shr AX,1h
	mov word ptr ds:[g_nMeshPolyVertexCount], AX
	cmp AX,2h
	jge @@yPassInit
	jmp @@copyBack
@@yPassInit:
	dec AX
	shl AX,1h
	mov BP,AX
	xor CL,CL
	mov AX, DS:word ptr [BP+g_aPolyClipY]
	mov DX, DS:word ptr [BP+g_aPolyClipYHi]
	cmp DX,0h
	jg @@yPrevChkYmax
	jl @@yPrevSetYmin
	cmp AX, SS:word ptr [_g_graphics_context.nClip_ymin]
	jnc @@yPrevChkYmax
@@yPrevSetYmin:
	or CL,8h
@@yPrevChkYmax:
	cmp DX,0h
	jl @@yPrevDone
	jg @@yPrevSetYmax
	cmp AX, SS:word ptr [_g_graphics_context.nClip_ymax]
	jbe @@yPrevDone
@@yPrevSetYmax:
	or CL,4h
@@yPrevDone:
	xor DI,DI
	mov SI,DI
@@yPassNext:
	xor CH,CH
	LD32 g_aPolyClipY
	cmp DX,0h
	jg @@yCurChkYmax
	jl @@yCurSetYmin
	cmp AX, SS:word ptr [_g_graphics_context.nClip_ymin]
	jnc @@yCurChkYmax
@@yCurSetYmin:
	or CH,8h
@@yCurChkYmax:
	cmp DX,0h
	jl @@yCurDone
	jg @@yCurSetYmax
	cmp AX, SS:word ptr [_g_graphics_context.nClip_ymax]
	jbe @@yCurDone
@@yCurSetYmax:
	or CH,4h
@@yCurDone:
	mov AL,CL
	or AL,CH
	jnz @@yNotBothIn
	LD32 g_aPolyClipX
	ST32 DI, g_aPolyInX
	LD32 g_aPolyClipY
	ST32 DI, g_aPolyInY
	add DI,2h
	jmp short @@yAdvance
@@yNotBothIn:
	mov AL,CL
	and AL,CH
	jnz @@yAdvance
	or CL,CL
	jnz @@yPrevOut
	xchg BP, SI
	xchg CL, CH
	call _r3d_clip_polygon_edge_y
	xchg BP, SI
	xchg CL, CH
	jmp short @@yAdvance
@@yPrevOut:
	or CH,CH
	jnz @@yBothOut
	call _r3d_clip_polygon_edge_y
	LD32 g_aPolyClipX
	ST32 DI, g_aPolyInX
	LD32 g_aPolyClipY
	ST32 DI, g_aPolyInY
	add DI,2h
	jmp short @@yAdvance
@@yBothOut:
	call _r3d_clip_polygon_edge_y
	xchg BP, SI
	xchg CL, CH
	call _r3d_clip_polygon_edge_y
	xchg BP, SI
	xchg CL, CH
@@yAdvance:
	mov BP,SI
	mov CL,CH
	add SI,2h
	mov AX,SI
	shr AX,1h
	cmp AX, word ptr ds:[g_nMeshPolyVertexCount]
	jz @@yPassDone
	jmp @@yPassNext
@@yPassDone:
	mov AX,DI
	shr AX,1h
	mov word ptr ds:[g_nMeshPolyVertexCount], AX
	jmp short @@done
@@copyBack:
	push ES
	mov AX,CS
	mov ES,AX
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	mov CX,AX
	mov SI, offset g_aPolyClipX
	mov DI, offset g_aPolyInX
	rep movsw
	mov CX,AX
	mov SI, offset g_aPolyClipY
	mov DI, offset g_aPolyInY
	rep movsw
	pop ES
@@done:
	pop DI
	pop SI
	pop BP
	ret

; ============================================================================
; _r3d_poly_clip_calc_isect
;
; Interpolates the camera-space X/Z intersection of a polygon edge with the near-clip plane at Y
; = g_nActorFarClipThreshold and stores it into the current vertex's screen-space slots.
;
; C equivalent:
;   /* Called with prev vertex index in BP, curr vertex index in SI.
;      The vertex fields are 32-bit longs stored as parallel low/high word
;      arrays (structure-of-arrays), indexed by vertex.  DS = CS. */
;   void r3d_poly_clip_calc_isect(int prevIdx, int currIdx)
;   {
;       long numer;
;       long denom;
;       long deltaX;
;       long deltaZ;
;
;       /* Distance from prev vertex to the clip plane, and edge deltas. */
;       numer  = (long)g_nActorFarClipThreshold - g_aVertexCamY[prevIdx];
;       denom  = g_aVertexCamY[currIdx] - g_aVertexCamY[prevIdx];
;       deltaZ = g_aVertexCamZ[currIdx] - g_aVertexCamZ[prevIdx];
;       deltaX = g_aVertexCamX[currIdx] - g_aVertexCamX[prevIdx];
;
;       /* r3d_ldiv_helper computes the fixed-point ratio (numer / denom) and
;          multiplies it into the two edge deltas in place, returning
;          deltaX * numer/denom and deltaZ * numer/denom on the stack. */
;       r3d_ldiv_helper(&deltaX, &deltaZ, denom, numer);
;
;       /* Add the prev vertex back to land on the clip plane, and store the
;          result into the PREV (reference) vertex's screen slots -- the asm
;          writes [BP+...] (prevIdx), not currIdx. */
;       g_aVertexScrX[prevIdx] = g_aVertexCamX[prevIdx] + deltaX;
;       g_aVertexScrY[prevIdx] = g_aVertexCamZ[prevIdx] + deltaZ;
;   }
; ============================================================================
	public _r3d_poly_clip_calc_isect
_r3d_poly_clip_calc_isect:
	push BX
	push CX
	mov AX, word ptr ds:[g_nViewPlaneDist]
	cwd
	SUB32 g_aVertexCamY
	push DX
	push AX
	LD32 g_aVertexCamY
	SUB32 g_aVertexCamY
	push DX
	push AX
	LD32 g_aVertexCamZ
	SUB32 g_aVertexCamZ
	push DX
	push AX
	LD32 g_aVertexCamX
	SUB32 g_aVertexCamX
	push DX
	push AX
	call _r3d_ldiv_helper
	pop AX
	pop DX
	ADD32 g_aVertexCamX
	mov DS:word ptr [BP+g_aVertexScrX], AX
	mov DS:word ptr [BP+g_aVertexScrXHi], DX
	pop AX
	pop DX
	ADD32 g_aVertexCamZ
	mov DS:word ptr [BP+g_aVertexScrY], AX
	mov DS:word ptr [BP+g_aVertexScrYHi], DX
	add SP,8h
	pop CX
	pop BX
	ret

; ============================================================================
; _r3d_polygon_clip_near_z_lod2
;
; Sutherland-Hodgman clip pass over the polygon vertex ring: drops type-3 (outside) vertices and
; inserts edge/boundary intersection points, rewriting the screen-coordinate output arrays and
; the vertex count.
;
; Same walk and emit as r3d_polygon_clip_against_zplane, but the edge-crossing
; interpolation is done by r3d_poly_clip_calc_isect. VTX_WORD(arr, off)/
; VTX_BYTE(arr, off) denote arr indexed by the pre-doubled byte offset 'off'
; (see COPYVTX2IN and r3d_poly_emit_screen_or_world); dstIdx/srcIdx step by 2.
;
; C equivalent:
;   void r3d_polygon_clip_near_z_lod2(void)
;   {
;       int prevVtx;        /* byte offset of previous vertex into the per-vertex arrays */
;       int curVtx;         /* byte offset of current vertex into the per-vertex arrays  */
;       unsigned int srcIdx;
;       unsigned int dstIdx;
;
;       srcIdx = 0;
;       dstIdx = 0;
;
;       prevVtx = g_polygon_vertices[g_nMeshPolyVertexCount - 1];
;
;       do {
;           curVtx = VTX_WORD(g_polygon_vertices, srcIdx);
;
;           if (VTX_BYTE(g_abPolygonClipState, curVtx) == CLIPST_BEHIND) {
;               if (VTX_BYTE(g_abPolygonClipState, prevVtx) != CLIPST_BEHIND) {
;                   r3d_poly_clip_calc_isect(prevVtx, curVtx);
;
;                   VTX_WORD(g_aPolyInX,   dstIdx) = VTX_WORD(g_aVertexScrX,   curVtx);
;                   VTX_WORD(g_aPolyInXHi, dstIdx) = VTX_WORD(g_aVertexScrXHi, curVtx);
;                   VTX_WORD(g_aPolyInY,   dstIdx) = VTX_WORD(g_aVertexScrY,   curVtx);
;                   VTX_WORD(g_aPolyInYHi, dstIdx) = VTX_WORD(g_aVertexScrYHi, curVtx);
;                   dstIdx += 2;
;               }
;           }
;           else if (VTX_BYTE(g_abPolygonClipState, prevVtx) == CLIPST_BEHIND) {
;               r3d_poly_clip_calc_isect(prevVtx, curVtx);
;
;               VTX_WORD(g_aPolyInX,   dstIdx) = VTX_WORD(g_aVertexScrX,   prevVtx);
;               VTX_WORD(g_aPolyInXHi, dstIdx) = VTX_WORD(g_aVertexScrXHi, prevVtx);
;               VTX_WORD(g_aPolyInY,   dstIdx) = VTX_WORD(g_aVertexScrY,   prevVtx);
;               VTX_WORD(g_aPolyInYHi, dstIdx) = VTX_WORD(g_aVertexScrYHi, prevVtx);
;               dstIdx += 2;
;
;               VTX_WORD(g_aPolyInX,   dstIdx) = VTX_WORD(g_aVertexScrX,   curVtx);
;               VTX_WORD(g_aPolyInXHi, dstIdx) = VTX_WORD(g_aVertexScrXHi, curVtx);
;               VTX_WORD(g_aPolyInY,   dstIdx) = VTX_WORD(g_aVertexScrY,   curVtx);
;               VTX_WORD(g_aPolyInYHi, dstIdx) = VTX_WORD(g_aVertexScrYHi, curVtx);
;               dstIdx += 2;
;           }
;           else {
;               VTX_WORD(g_aPolyInX,   dstIdx) = VTX_WORD(g_aVertexScrX,   curVtx);
;               VTX_WORD(g_aPolyInXHi, dstIdx) = VTX_WORD(g_aVertexScrXHi, curVtx);
;               VTX_WORD(g_aPolyInY,   dstIdx) = VTX_WORD(g_aVertexScrY,   curVtx);
;               VTX_WORD(g_aPolyInYHi, dstIdx) = VTX_WORD(g_aVertexScrYHi, curVtx);
;               dstIdx += 2;
;           }
;
;           prevVtx = curVtx;
;           srcIdx += 2;
;       } while (srcIdx >> 1 != g_nMeshPolyVertexCount);
;
;       g_nMeshPolyVertexCount = dstIdx >> 1;
;   }
; ============================================================================
	public _r3d_polygon_clip_near_z_lod2
_r3d_polygon_clip_near_z_lod2:
	push BP
	push SI
	push DI
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	dec AX
	mov BP,AX
	shl BP,1h
	mov BP, DS:word ptr [BP+g_polygon_vertices]
	xor CX,CX
	xor DI,DI
@@nextEdge:
	mov SI,CX
	mov SI, word ptr [SI+g_polygon_vertices]
	mov AL, DS:byte ptr [BP+g_abPolygonClipState]
	mov AH, byte ptr [SI+g_abPolygonClipState]
	cmp AH,3h
	jz @@curBehind
	cmp AL,3h
	jz @@prevBehind
	COPYVTX2IN
	add DI,2h
	jmp short @@advance
@@prevBehind:
	call _r3d_poly_clip_calc_isect
	mov AX, DS:word ptr [BP+g_aVertexScrX]
	mov word ptr [DI+g_aPolyInX], AX
	mov AX, DS:word ptr [BP+g_aVertexScrXHi]
	mov word ptr [DI+g_aPolyInXHi], AX
	mov AX, DS:word ptr [BP+g_aVertexScrY]
	mov word ptr [DI+g_aPolyInY], AX
	mov AX, DS:word ptr [BP+g_aVertexScrYHi]
	mov word ptr [DI+g_aPolyInYHi], AX
	add DI,2h
	COPYVTX2IN
	add DI,2h
	jmp short @@advance
@@curBehind:
	cmp AL,3h
	jz @@advance
	xchg BP, SI
	call _r3d_poly_clip_calc_isect
	xchg SI, BP
	COPYVTX2IN
	add DI,2h
@@advance:
	mov BP,SI
	add CX,2h
	mov AX,CX
	shr AX,1h
	cmp AX, word ptr ds:[g_nMeshPolyVertexCount]
	jz @@done
	jmp @@nextEdge
@@done:
	mov AX,DI
	shr AX,1h
	mov word ptr ds:[g_nMeshPolyVertexCount], AX
	pop DI
	pop SI
	pop BP
	ret

; ============================================================================
; _r3d_apply_viewport_offset_long
;
; Adds the viewport center to every projected vertex's 32-bit screen X, and subtracts each
; screen Y from the viewport center Y (Y-axis flip), in place.
;
; C equivalent:
;   void r3d_apply_viewport_offset_long(void)
;   {
;       int i;
;       int n;
;       long sx;
;       long sy;
;
;       n = g_nMeshPolyVertexCount;
;       if (n == 0)
;           return;
;
;       for (i = 0; i < n; i++) {
;           sx = ((long)g_aVertexScrXHi[i] << 16) | (unsigned)g_aVertexScrX[i];
;           sx += (long)g_nViewportCenterX;
;           g_aVertexScrX[i] = (short)sx;
;           g_aVertexScrXHi[i] = (short)(sx >> 16);
;       }
;
;       for (i = 0; i < n; i++) {
;           sy = ((long)g_aVertexScrYHi[i] << 16) | (unsigned)g_aVertexScrY[i];
;           sy = (long)g_nViewportCenterY - sy;
;           g_aVertexScrY[i] = (short)sy;
;           g_aVertexScrYHi[i] = (short)(sy >> 16);
;       }
;   }
; ============================================================================
	public _r3d_apply_viewport_offset_long
_r3d_apply_viewport_offset_long:
	mov AX, word ptr ds:[g_nMeshPolyVertexCount]
	mov CX,AX
	jcxz @@done
	push SI
	push DI
	push CX
	mov BX, word ptr ds:[g_nViewportCenterX]
	mov SI, offset g_aPolyInX
	mov DI,offset g_aPolyInXHi
@@xLoop:
	mov AX,BX
	cwd
	add AX, word ptr [SI]
	adc DX, word ptr [DI]
	mov word ptr [SI], AX
	mov word ptr [DI], DX
	add SI,2h
	add DI,2h
	loop @@xLoop
	pop CX
	mov BX, word ptr ds:[g_nViewportCenterY]
	mov SI, offset g_aPolyInY
	mov DI,offset g_aPolyInYHi
@@yLoop:
	mov AX,BX
	cwd
	sub AX, word ptr [SI]
	sbb DX, word ptr [DI]
	mov word ptr [SI], AX
	mov word ptr [DI], DX
	add SI,2h
	add DI,2h
	loop @@yLoop
	pop DI
	pop SI
@@done:
	ret

; Gap 0x2e53-0x2e53: 1B zero-init
	db 0

S233E_TEXT	ends

	end
