; ============================================================================
; GOURAUD.ASM -- segment 0x180c gouraud-shaded quad rasterizer module
; (180c:0005..180c:0740, four functions, one TASM TU).
;
; gfx_gouraud_blit_quad NEAR-calls compare_edge_slopes and
; gfx_gouraud_span_dispatch, and repeatedly calls the far-declared
; edge_step_init via the hand-written PUSH CS + NEAR CALL idiom (saves a byte
; over a real far call within the same segment). Grouped as one module so
; those intra-segment calls are real near calls, not external fixups.
;
;   0005  gfx_gouraud_blit_quad       (1248 bytes)  far,  the outer rasterizer
;   04e5  gfx_gouraud_span_dispatch    (301 bytes)  near, edge-topology dispatch
;   0612  compare_edge_slopes          (211 bytes)  near, slope comparator
;   06e5  edge_step_init                 (91 bytes)  far,  step/fraction init
; ============================================================================

	.386p

; --- DGROUP / segment declarations -----------------------------------------
_DATA   SEGMENT WORD PUBLIC 'DATA'
_DATA   ENDS
_BSS    SEGMENT WORD PUBLIC 'BSS'
_BSS    ENDS
DGROUP  GROUP _DATA, _BSS

	include	gfxctx.inc	; GfxContext struc + _g_graphics_context, _g_pRow_offset_lut (shared TASM STRUC header -- do not shadow locally)

; Polygon/scaled-sprite rasterizer shared state (DGROUP+0x28e).  Layout mirrors
; PolyRasterState (structs.h); also hand-declared in POLYRAST.ASM --
; no generated .inc exists for this struct yet.
; Only .prs_nRemapOff (the XLAT remap LUT offset) is read here.
PolyRasterState struc
prs_nRemapOff   dw      ?       ; +00h  DGROUP+0x28e  XLAT remap LUT offset
prs_e0_acc      dd      ?       ; +02h  DGROUP+0x290  edge[0].acc
prs_e0_step     dd      ?       ; +06h  DGROUP+0x294  edge[0].step
prs_e1_acc      dd      ?       ; +0ah  DGROUP+0x298  edge[1].acc
prs_e1_step     dd      ?       ; +0eh  DGROUP+0x29c  edge[1].step
prs_e2_acc      dd      ?       ; +12h  DGROUP+0x2a0  edge[2].acc
prs_e2_step     dd      ?       ; +16h  DGROUP+0x2a4  edge[2].step
PolyRasterState ends

	extrn   _g_polyRasterState:byte   ; DGROUP+0x028e (PolyRasterState)

; The sprite remap table lives in segment S169D (u_169d2/polyrast's segment).
; Declared empty here so `mov si,S169D_TEXT` emits a segment FIXUPP -> MZ reloc.
; BYTE-aligned: a zero-length foreign declaration must not raise the real
; segment's link alignment.
S169D_TEXT      SEGMENT BYTE PUBLIC USE16 'CODE'
S169D_TEXT      ENDS

S180C_TEXT      SEGMENT BYTE PUBLIC USE16 'CODE'
	ASSUME CS:S180C_TEXT, DS:DGROUP

	PUBLIC _gfx_gouraud_blit_quad
	PUBLIC _gfx_gouraud_span_dispatch
	PUBLIC _compare_edge_slopes
	PUBLIC _edge_step_init

; ============================================================================
; gfx_gouraud_blit_quad @ 180c:0005  (1248 bytes)
;
; Inner gouraud-shaded textured quad rasterizer (4-vertex). Builds a 320-entry
; row offset table from the quad header, finds top/bottom verts, walks both
; polygon edges scanline-by-scanline writing through EGA SC map mask
; (port 0x3c4/0x3c5).  Honors g_clip_xmin/xmax/ymin/ymax.
;
;   void gfx_gouraud_blit_quad(undefined2 *quad, int *vy_array, int *vx_array);
;   (__cdecl16far, RETF)
;
; WHY ASM (not C): The inner pixel-write loops require explicit segment register
; manipulation that BCC 3.1 cannot express in C:
;   1. ES is loaded from g_graphics_context.wGfxBlitDstPage (VRAM dest segment)
;      at function entry and kept live across the entire scanline loop.
;   2. DS is switched mid-loop to the texture data segment loaded from quad[0],
;      enabling DS:[SI] reads from the texture page.  After the loop, DS is
;      restored to SS (DGROUP).
;   3. PUSH GS / POP GS save/restore the sprite remap table segment (0x169d)
;      for the remap path; XLAT GS:BX performs the remap lookup.
;   4. SS:[0x28e] (g_polyRasterState.nRemapTableOff) is read directly through SS: override
;      after DS has been switched, since DS no longer points to DGROUP.
; All DGROUP data is referenced by symbol: g_graphics_context fields via the
; generated gfxctx.inc struc, and the row-offset LUT via the standalone
; _g_pRow_offset_lut global (DGROUP:0x2702, carved out of the gfxctx para block).
;
; Calls compare_edge_slopes and gfx_gouraud_span_dispatch (near, plain call --
; both are intra-unit NEAR procs below) and edge_step_init (intra-unit FAR
; proc, called via PUSH CS + CALL NEAR PTR to reproduce the original's
; 4-byte near-call encoding instead of a 5-byte real far call).
; ============================================================================

; void gfx_gouraud_blit_quad(undefined2 *quad, int *vy_array, int *vx_array)
;                             [BP+6]             [BP+8]          [BP+A]
_gfx_gouraud_blit_quad  PROC FAR
	push    bp
	mov     bp,sp
	sub     sp,6fah                     ; 180c:0008
	push    di                          ; 180c:000c
	push    si                          ; 180c:000d
	; --- build row-offset table: local_6f2[0..0x13e] ---
	mov     cx,13fh                     ; 13fh row-fill loop count 319, feeds LOOP (do/while)
	mov     ax,ds                       ; 180c:0011
	mov     es,ax                       ; 180c:0013  ES = DS = DGROUP
	lea     di,[bp + 0f910h]            ; 180c:0015
	mov     bx,word ptr [bp + 6]        ; 180c:0019  BX = quad
	mov     ax,word ptr [bx + 2]        ; 180c:001c  AX = quad[1] (base offset)
	mov     bx,word ptr [bx + 8]        ; 180c:001f  BX = quad[4] (step)
L_row_fill:                                 ; target of LOOP at 0x0025
	stosw                               ; 180c:0022
	add     ax,bx                       ; 180c:0023
	loop    L_row_fill                  ; 180c:0025
	; load ES = wGfxBlitDstPage (VRAM segment)
	mov     es,word ptr [_g_graphics_context.wGfxBlitDstPage] ; 180c:0027
	; OUT 0x3c4, 2  (EGA sequencer - map mask register index)
	mov     dx,3c4h                     ; 3c4h EGA SC index I/O port, feeds OUT (out(0x3c4,2))
	mov     al,2                        ; 180c:002e
	out     dx,al                       ; 180c:0030
	; zero locals
	xor     ax,ax                       ; 180c:0031
	mov     word ptr [bp + 0fe16h],ax   ; 180c:0033  span_clip_skip = 0
	mov     word ptr [bp - 0ch],ax      ; 180c:0037  edge_dir = 0
	mov     word ptr [bp + 0fe2ch],ax   ; 180c:003a  vi = 0
	mov     word ptr [bp + 0fe4ah],7d00h ; 180c:003e  min_y = 32000
	mov     word ptr [bp - 018h],8300h  ; 180c:0044  max_y = -32000
	; --- find top and bottom vertices (vi = 0..3) ---
L_find_verts:                               ; 180c:0049
	mov     bx,word ptr [bp + 0fe2ch]   ; 180c:0049
	shl     bx,1                        ; 180c:004d  bx = vi*2
	mov     si,word ptr [bp + 8]        ; 180c:004f  si = vy_array
	mov     ax,word ptr [bx + si]       ; 180c:0052  ax = vy_array[vi]
	mov     word ptr [bp + 0fe10h],ax   ; 180c:0054
	cmp     ax,word ptr [bp + 0fe4ah]   ; 180c:0058  ax > min_y?
	jg      short L_not_new_min         ; 180c:005c
	mov     word ptr [bp + 0fe4ah],ax   ; 180c:005e  min_y = ax
	mov     ax,word ptr [bp + 0fe2ch]   ; 180c:0062
	mov     word ptr [bp - 0ah],ax      ; 180c:0066  top_vert = vi
L_not_new_min:                              ; 180c:0069
	mov     ax,word ptr [bp - 018h]     ; 180c:0069  ax = max_y
	cmp     word ptr [bp + 0fe10h],ax   ; 180c:006c
	jle     short L_not_new_max         ; 180c:0070
	mov     ax,word ptr [bp + 0fe10h]   ; 180c:0072
	mov     word ptr [bp - 018h],ax     ; 180c:0076  max_y = ax
	mov     ax,word ptr [bp + 0fe2ch]   ; 180c:0079
	mov     word ptr [bp - 01ah],ax     ; 180c:007d  bot_vert = vi
L_not_new_max:                              ; 180c:0080
	inc     word ptr [bp + 0fe2ch]      ; 180c:0080  vi++
	cmp     word ptr [bp + 0fe2ch],4    ; 180c:0084
	jl      L_find_verts                ; 180c:0089
	; --- init top state ---
	mov     ax,word ptr [bp - 0ah]      ; 180c:008b  ax = top_vert
	mov     word ptr [bp + 0fe2ch],ax   ; 180c:008e  vi = top_vert
	mov     bx,ax                       ; 180c:0092
	inc     bl                          ; 180c:0094
	and     bx,3                        ; 180c:0096
	mov     word ptr [bp - 01ch],bx     ; 180c:0099  next_vert = (top+1)&3
	shl     bx,1                        ; 180c:009c
	mov     si,word ptr [bp + 8]        ; 180c:009e  si = vy_array
	push    word ptr [bx + si]          ; 180c:00a1  vy_array[next_vert]
	mov     di,word ptr [bp + 0ah]      ; 180c:00a3  di = vx_array
	push    word ptr [bx + di]          ; 180c:00a6  vx_array[next_vert]
	mov     bx,ax                       ; 180c:00a8
	shl     bx,1                        ; 180c:00aa
	push    word ptr [bx + si]          ; 180c:00ac  vy_array[top]
	push    word ptr [bx + di]          ; 180c:00ae  vx_array[top]
	mov     cx,bx                       ; 180c:00b0  cx = top*2
	mov     bx,ax                       ; 180c:00b2
	shl     bl,1                        ; 180c:00b4
	dec     bl                          ; 180c:00b6
	and     bx,6                        ; 180c:00b8  bx = prev_vert*2 (wrap)
	push    word ptr [bx + si]          ; 180c:00bb  vy_array[prev_vert]
	push    word ptr [bx + di]          ; 180c:00bd  vx_array[prev_vert]
	mov     si,cx                       ; 180c:00bf  si = top*2
	call    _compare_edge_slopes        ; 180c:00c1
	add     sp,0ch                      ; 180c:00c4
	mov     word ptr [bp - 0ch],ax      ; 180c:00c7  edge_dir = result
	add     ax,word ptr [bp - 0ah]      ; 180c:00ca  ax += top_vert
	and     ax,3                        ; 180c:00cd
	mov     word ptr [bp + 0fe1ch],ax   ; 180c:00d0  long_edge_next = ax
	; span_height = -(vy[top] - vy[long_edge_next]) = vy[lnext]-vy[top]
	mov     bx,word ptr [bp + 8]        ; 180c:00d4  bx = vy_array
	mov     cx,word ptr [bx + si]       ; 180c:00d7  cx = vy_array[top]
	mov     bx,ax                       ; 180c:00d9
	shl     bx,1                        ; 180c:00db
	mov     di,word ptr [bp + 8]        ; 180c:00dd
	sub     cx,word ptr [bx + di]       ; 180c:00e0  cx -= vy[long_next]
	neg     cx                          ; 180c:00e2
	mov     word ptr [bp + 0fe10h],cx   ; 180c:00e4  span_height = cx
	mov     word ptr [bp + 0fe18h],cx   ; 180c:00e8  long_edge_remain = cx
	; setup x-step struct for long edge: step[0].lo = vx[top], step[1].lo = vx[lnext]
	mov     cx,bx                       ; 180c:00ec  cx = long_next*2
	mov     bx,word ptr [bp + 0ah]      ; 180c:00ee  bx = vx_array
	mov     dx,word ptr [bx + si]       ; 180c:00f1  dx = vx_array[top]
	mov     word ptr [bp + 0f908h],dx   ; 180c:00f3
	mov     bx,cx                       ; 180c:00f7
	mov     si,word ptr [bp + 0ah]      ; 180c:00f9
	mov     cx,word ptr [bx + si]       ; 180c:00fc  cx = vx_array[long_next]
	mov     word ptr [bp + 0f90ch],cx   ; 180c:00fe
	; edge_step_init(&local_6fc, span_height)
	push    word ptr [bp + 0fe18h]      ; 180c:0102  count = span_height
	lea     cx,[bp + 0f906h]            ; 180c:0106
	push    cx                          ; 180c:010a  &step
	mov     si,ax                       ; 180c:010b  si = long_next
	push    cs                          ; 180c:010d
	call    near ptr _edge_step_init    ; 180c:010e
	add     sp,4                        ; 180c:0111
	; gfx_gouraud_span_dispatch(top, long_next, quad, out...)
	lea     ax,[bp + 0f90eh]            ; 180c:0114
	push    ax                          ; 180c:0118
	lea     cx,[bp + 0fe14h]            ; 180c:0119
	push    cx                          ; 180c:011d
	lea     dx,[bp + 0fe12h]            ; 180c:011e
	push    dx                          ; 180c:0122
	lea     bx,[bp + 0fe1ah]            ; 180c:0123
	push    bx                          ; 180c:0127
	push    word ptr [bp + 6]           ; 180c:0128  quad
	push    si                          ; 180c:012b  long_next
	push    word ptr [bp - 0ah]         ; 180c:012c  top
	call    _gfx_gouraud_span_dispatch  ; 180c:012f
	add     sp,0eh                      ; 180c:0132
	; init long-edge color-u span struct
	lea     bx,[bp + 0fe38h]            ; 180c:0135
	mov     ax,word ptr [bp + 0fe1ah]   ; 180c:0139
	mov     word ptr [bx + 2],ax        ; 180c:013d
	mov     ax,word ptr [bp + 0fe12h]   ; 180c:0140
	mov     word ptr [bx + 6],ax        ; 180c:0144
	push    word ptr [bp + 0fe10h]      ; 180c:0147
	push    bx                          ; 180c:014b
	push    cs                          ; 180c:014c
	call    near ptr _edge_step_init    ; 180c:014d
	add     sp,4                        ; 180c:0150
	; init long-edge color-v span struct
	lea     bx,[bp + 0fe20h]            ; 180c:0153
	mov     ax,word ptr [bp + 0fe14h]   ; 180c:0157
	mov     word ptr [bx + 2],ax        ; 180c:015b
	mov     ax,word ptr [bp + 0f90eh]   ; 180c:015e
	mov     word ptr [bx + 6],ax        ; 180c:0162
	push    word ptr [bp + 0fe10h]      ; 180c:0165
	push    bx                          ; 180c:0169
	push    cs                          ; 180c:016a
	call    near ptr _edge_step_init    ; 180c:016b
	add     sp,4                        ; 180c:016e
	; --- outer loop: iterate over short edges ---
L_outer_loop:                               ; 180c:0171
	; short_vert = (vi - edge_dir) & 3
	mov     bx,word ptr [bp + 0fe2ch]   ; 180c:0171
	sub     bx,word ptr [bp - 0ch]      ; 180c:0175
	and     bx,3                        ; 180c:0178
	mov     word ptr [bp - 016h],bx     ; 180c:017b  short_vert = bx
	shl     bx,1                        ; 180c:017e
	mov     si,word ptr [bp + 8]        ; 180c:0180  si = vy_array
	mov     ax,bx                       ; 180c:0183  ax = short_vert*2
	mov     bx,word ptr [bp + 0fe2ch]   ; 180c:0185
	mov     cx,bx                       ; 180c:0189  cx = vi
	mov     bx,ax                       ; 180c:018b
	mov     dx,word ptr [bx + si]       ; 180c:018d  dx = vy[short_vert]
	mov     bx,cx                       ; 180c:018f
	shl     bx,1                        ; 180c:0191
	sub     dx,word ptr [bx + si]       ; 180c:0193  dx = vy[short] - vy[vi]
	mov     word ptr [bp + 0fe10h],dx   ; 180c:0195  span_height = dx
	; gfx_gouraud_span_dispatch(vi, short_vert, quad, out...)
	lea     cx,[bp + 0f90eh]            ; 180c:0199
	push    cx                          ; 180c:019d
	lea     dx,[bp + 0fe14h]            ; 180c:019e
	push    dx                          ; 180c:01a2
	lea     di,[bp + 0fe12h]            ; 180c:01a3
	push    di                          ; 180c:01a7
	lea     cx,[bp + 0fe1ah]            ; 180c:01a8
	push    cx                          ; 180c:01ac
	push    word ptr [bp + 6]           ; 180c:01ad  quad
	push    word ptr [bp - 016h]        ; 180c:01b0  short_vert
	push    word ptr [bp + 0fe2ch]      ; 180c:01b3  vi
	mov     si,ax                       ; 180c:01b7  si = short_vert*2
	mov     di,bx                       ; 180c:01b9  di = vi*2
	call    _gfx_gouraud_span_dispatch  ; 180c:01bb
	add     sp,0eh                      ; 180c:01be
	; init short-edge step struct (color-a)
	lea     bx,[bp - 8]                 ; 180c:01c1
	mov     ax,word ptr [bp + 0fe1ah]   ; 180c:01c4
	mov     word ptr [bx + 2],ax        ; 180c:01c8
	mov     ax,word ptr [bp + 0fe12h]   ; 180c:01cb
	mov     word ptr [bx + 6],ax        ; 180c:01cf
	push    word ptr [bp + 0fe10h]      ; 180c:01d2
	push    bx                          ; 180c:01d6
	push    cs                          ; 180c:01d7
	call    near ptr _edge_step_init    ; 180c:01d8
	add     sp,4                        ; 180c:01db
	; init short-edge step struct (color-b)
	lea     bx,[bp - 014h]              ; 180c:01de
	mov     ax,word ptr [bp + 0fe14h]   ; 180c:01e1
	mov     word ptr [bx + 2],ax        ; 180c:01e5
	mov     ax,word ptr [bp + 0f90eh]   ; 180c:01e8
	mov     word ptr [bx + 6],ax        ; 180c:01ec
	push    word ptr [bp + 0fe10h]      ; 180c:01ef
	push    bx                          ; 180c:01f3
	push    cs                          ; 180c:01f4
	call    near ptr _edge_step_init    ; 180c:01f5
	add     sp,4                        ; 180c:01f8
	; load x endpoints: vx[vi] and vx[short_vert]
	mov     bx,word ptr [bp + 0ah]      ; 180c:01fb  bx = vx_array
	mov     ax,word ptr [bx + di]       ; 180c:01fe  ax = vx_array[vi]
	mov     word ptr [bp + 0fe32h],ax   ; 180c:0200
	mov     ax,word ptr [bx + si]       ; 180c:0204  ax = vx_array[short_vert]
	mov     word ptr [bp + 0fe36h],ax   ; 180c:0206
	push    word ptr [bp + 0fe10h]      ; 180c:020a
	lea     ax,[bp + 0fe30h]            ; 180c:020e
	push    ax                          ; 180c:0212
	push    cs                          ; 180c:0213
	call    near ptr _edge_step_init    ; 180c:0214
	add     sp,4                        ; 180c:0217
	; y = vy_array[vi]
	mov     bx,word ptr [bp + 8]        ; 180c:021a
	mov     ax,word ptr [bx + di]       ; 180c:021d  ax = vy_array[vi]
	mov     word ptr [bp + 0fe2eh],ax   ; 180c:021f  y_cur = vy_array[vi]
	; --- inner scanline loop ---
	; entry: y++, span_height--
L_inner_next:                               ; 180c:0223
	inc     word ptr [bp + 0fe2eh]      ; 180c:0223  y_cur++
	dec     word ptr [bp + 0fe10h]      ; 180c:0227  span_height--
	cmp     word ptr [bp + 0fe10h],0    ; 180c:022b
	jl      L_inner_exit                ; 180c:0230  -> 0x04c7
	; check if long edge needs restart
	cmp     word ptr [bp + 0fe18h],0    ; 180c:0234
	jnz     L_no_edge_restart           ; 180c:0239  -> 0x02f0
	; --- restart long edge ---
	mov     ax,word ptr [bp + 0fe1ch]   ; 180c:023d  ax = long_next
	mov     word ptr [bp - 01ch],ax     ; 180c:0241  long_cur = ax
	add     ax,word ptr [bp - 0ch]      ; 180c:0244  ax += edge_dir
	and     ax,3                        ; 180c:0247
	mov     word ptr [bp + 0fe1ch],ax   ; 180c:024a  long_next = ax
	mov     bx,ax                       ; 180c:024e
	shl     bx,1                        ; 180c:0250
	mov     si,word ptr [bp + 8]        ; 180c:0252  si = vy_array
	mov     ax,bx                       ; 180c:0255  ax = long_next*2
	mov     bx,word ptr [bp - 01ch]     ; 180c:0257  bx = long_cur
	mov     cx,bx                       ; 180c:025a
	mov     bx,ax                       ; 180c:025c
	mov     dx,word ptr [bx + si]       ; 180c:025e  dx = vy[long_next]
	mov     bx,cx                       ; 180c:0260
	shl     bx,1                        ; 180c:0262
	sub     dx,word ptr [bx + si]       ; 180c:0264  dx = vy[lnext]-vy[lcur]
	mov     word ptr [bp + 0fe18h],dx   ; 180c:0266  long_remain = dx
	mov     si,word ptr [bp + 0ah]      ; 180c:026a  si = vx_array
	mov     cx,word ptr [bx + si]       ; 180c:026d  cx = vx[long_cur]
	mov     word ptr [bp + 0f908h],cx   ; 180c:026f
	mov     bx,ax                       ; 180c:0273
	mov     ax,word ptr [bx + si]       ; 180c:0275  ax = vx[long_next]
	mov     word ptr [bp + 0f90ch],ax   ; 180c:0277
	; edge_step_init(&local_6fc, long_remain)
	push    dx                          ; 180c:027b
	lea     ax,[bp + 0f906h]            ; 180c:027c
	push    ax                          ; 180c:0280
	push    cs                          ; 180c:0281
	call    near ptr _edge_step_init    ; 180c:0282
	add     sp,4                        ; 180c:0285
	; gfx_gouraud_span_dispatch(long_cur, long_next, quad, out...)
	lea     ax,[bp + 0f90eh]            ; 180c:0288
	push    ax                          ; 180c:028c
	lea     cx,[bp + 0fe14h]            ; 180c:028d
	push    cx                          ; 180c:0291
	lea     dx,[bp + 0fe12h]            ; 180c:0292
	push    dx                          ; 180c:0296
	lea     bx,[bp + 0fe1ah]            ; 180c:0297
	push    bx                          ; 180c:029b
	push    word ptr [bp + 6]           ; 180c:029c  quad
	push    word ptr [bp + 0fe1ch]      ; 180c:029f  long_next
	push    word ptr [bp - 01ch]        ; 180c:02a3  long_cur
	call    _gfx_gouraud_span_dispatch  ; 180c:02a6
	add     sp,0eh                      ; 180c:02a9
	; update long-edge u step
	mov     ax,word ptr [bp + 0fe1ah]   ; 180c:02ac
	mov     word ptr [bp + 0fe3ah],ax   ; 180c:02b0
	mov     ax,word ptr [bp + 0fe12h]   ; 180c:02b4
	mov     word ptr [bp + 0fe3eh],ax   ; 180c:02b8
	push    word ptr [bp + 0fe18h]      ; 180c:02bc
	lea     ax,[bp + 0fe38h]            ; 180c:02c0
	push    ax                          ; 180c:02c4
	push    cs                          ; 180c:02c5
	call    near ptr _edge_step_init    ; 180c:02c6
	add     sp,4                        ; 180c:02c9
	; update long-edge v step
	mov     ax,word ptr [bp + 0fe14h]   ; 180c:02cc
	mov     word ptr [bp + 0fe22h],ax   ; 180c:02d0
	mov     ax,word ptr [bp + 0f90eh]   ; 180c:02d4
	mov     word ptr [bp + 0fe26h],ax   ; 180c:02d8
	push    word ptr [bp + 0fe18h]      ; 180c:02dc
	lea     ax,[bp + 0fe20h]            ; 180c:02e0
	push    ax                          ; 180c:02e4
	push    cs                          ; 180c:02e5
	call    near ptr _edge_step_init    ; 180c:02e6
	add     sp,4                        ; 180c:02e9
	inc     word ptr [bp + 0fe18h]      ; 180c:02ec  long_remain++
L_no_edge_restart:                          ; 180c:02f0  = JNZ target
	dec     word ptr [bp + 0fe18h]      ; 180c:02f0  long_remain--
	; --- advance all 32-bit step accumulators ---
	mov     ax,word ptr [bp + 0fe32h]   ; 180c:02f4  x_step lo word
	mov     word ptr [bp + 0fe40h],ax   ; 180c:02f8  x_cur = lo_word
	mov     eax,dword ptr [bp + 0fe34h] ; 180c:02fc
	add     dword ptr [bp + 0fe30h],eax ; 180c:0301
	mov     ax,word ptr [bp + 0f908h]   ; 180c:0306  long_x lo
	mov     word ptr [bp + 0fe1eh],ax   ; 180c:030a
	mov     eax,dword ptr [bp + 0f90ah] ; 180c:030e
	add     dword ptr [bp + 0f906h],eax ; 180c:0313
	mov     ax,word ptr [bp - 6]        ; 180c:0318  short-a lo
	mov     word ptr [bp + 0fe1ah],ax   ; 180c:031b
	mov     eax,dword ptr [bp - 4]      ; 180c:031f
	add     dword ptr [bp - 8],eax      ; 180c:0323
	shr     eax,10h                     ; 180c:0327  (dead: SHR EAX,16)
	mov     ax,word ptr [bp + 0fe3ah]   ; 180c:032b  long-u lo
	mov     word ptr [bp + 0fe12h],ax   ; 180c:032f
	mov     eax,dword ptr [bp + 0fe3ch] ; 180c:0333
	add     dword ptr [bp + 0fe38h],eax ; 180c:0338
	mov     ax,word ptr [bp - 012h]     ; 180c:033d  short-b lo
	mov     word ptr [bp + 0fe14h],ax   ; 180c:0340
	mov     eax,dword ptr [bp - 010h]   ; 180c:0344
	add     dword ptr [bp - 014h],eax   ; 180c:0348
	mov     ax,word ptr [bp + 0fe22h]   ; 180c:034c  long-v lo
	mov     word ptr [bp + 0f90eh],ax   ; 180c:0350
	mov     eax,dword ptr [bp + 0fe24h] ; 180c:0354
	add     dword ptr [bp + 0fe20h],eax ; 180c:0359
	; --- clip y test (x-axis in EGA plane coordinates) ---
	mov     ax,word ptr [_g_graphics_context.nClip_xmin] ; 180c:035e
	cmp     word ptr [bp + 0fe2eh],ax   ; 180c:0361  y_cur < clip_xmin?
	jl      L_inner_next                ; 180c:0365  skip this scanline
	mov     ax,word ptr [_g_graphics_context.nClip_xmax] ; 180c:0369
	cmp     word ptr [bp + 0fe2eh],ax   ; 180c:036c
	jg      L_inner_next                ; 180c:0370  skip this scanline
	; --- within clip band: setup span ---
	mov     ax,word ptr [bp + 0fe1ah]   ; 180c:0374  u lo
	mov     word ptr [bp + 0fe4eh],ax   ; 180c:0378
	mov     ax,word ptr [bp + 0fe12h]   ; 180c:037c  v lo
	mov     word ptr [bp + 0fe52h],ax   ; 180c:0380
	; span_width = x_end - x_start
	mov     ax,word ptr [bp + 0fe1eh]   ; 180c:0384  x_end
	sub     ax,word ptr [bp + 0fe40h]   ; 180c:0388  - x_start
	mov     word ptr [bp - 01ch],ax     ; 180c:038c  span_width
	; edge_step_init for u-span
	push    ax                          ; 180c:038f
	lea     cx,[bp + 0fe4ch]            ; 180c:0390
	push    cx                          ; 180c:0394
	push    cs                          ; 180c:0395
	call    near ptr _edge_step_init    ; 180c:0396
	add     sp,4                        ; 180c:0399
	; setup v-span step
	mov     ax,word ptr [bp + 0fe14h]   ; 180c:039c
	mov     word ptr [bp + 0fe44h],ax   ; 180c:03a0
	mov     ax,word ptr [bp + 0f90eh]   ; 180c:03a4
	mov     word ptr [bp + 0fe48h],ax   ; 180c:03a8
	push    word ptr [bp - 01ch]        ; 180c:03ac
	lea     ax,[bp + 0fe42h]            ; 180c:03af
	push    ax                          ; 180c:03b3
	push    cs                          ; 180c:03b4
	call    near ptr _edge_step_init    ; 180c:03b5
	add     sp,4                        ; 180c:03b8
	; --- clip ymin (x_start clipping) ---
	mov     ax,word ptr [bp + 0fe40h]   ; 180c:03bb  x_start
	cmp     word ptr [_g_graphics_context.nClip_ymin],ax ; 180c:03bf
	jle     short L_ymin_ok             ; 180c:03c3  -> 0x03dc
	sub     ax,word ptr [_g_graphics_context.nClip_ymin] ; 180c:03c5
	neg     ax                          ; 180c:03c9
	mov     word ptr [bp + 0fe16h],ax   ; 180c:03cb  clip_skip = ax
	mov     ax,word ptr [_g_graphics_context.nClip_ymin] ; 180c:03cf
	mov     word ptr [bp + 0fe40h],ax   ; 180c:03d2  x_start = clip_ymin
	; load clip_skip into SI (only on the clip path)
	mov     si,word ptr [bp + 0fe16h]   ; 180c:03d6
	shl     si,1                        ; 180c:03da  si = clip_skip*2
L_ymin_ok:                                  ; 180c:03dc  target of JLE at 03c3
	mov     ax,word ptr [bp + 0fe1eh]   ; 180c:03dc  x_end
	sub     ax,word ptr [bp + 0fe40h]   ; 180c:03e0  - x_start
	mov     word ptr [bp - 01ch],ax     ; 180c:03e4  draw_width
	or      ax,ax                       ; 180c:03e7
	jl      L_inner_next                ; 180c:03e9  skip if <= 0
	; clip ymax
	mov     ax,word ptr [bp - 01ch]     ; 180c:03ed
	add     ax,word ptr [bp + 0fe40h]   ; 180c:03f0
	cmp     ax,word ptr [_g_graphics_context.nClip_ymax] ; 180c:03f4
	jl      short L_ymax_ok             ; 180c:03f8  -> 0x0404
	; clamp to ymax
	mov     ax,word ptr [_g_graphics_context.nClip_ymax] ; 180c:03fa
	sub     ax,word ptr [bp + 0fe40h]   ; 180c:03fd
	mov     word ptr [bp - 01ch],ax     ; 180c:0401
L_ymax_ok:                                  ; 180c:0404  target of JL at 03f8
	or      ax,ax                       ; 180c:0404
	jl      L_inner_next                ; 180c:0406
	; DI = pRow_offset_lut[x_start] + (y_cur >> 2)
	mov     di,word ptr [bp + 0fe40h]   ; 180c:040a  x_start
	shl     di,1                        ; 180c:040e
	mov     di,word ptr [di + _g_pRow_offset_lut] ; 180c:0410  row-offset LUT (DGROUP:0x2702)
	; OUT 0x3c5, 1 << (y_cur & 3)
	mov     cx,word ptr [bp + 0fe2eh]   ; 180c:0414  y_cur
	and     cx,3                        ; 180c:0418
	mov     dx,3c5h                     ; 3c5h EGA SC data I/O port, feeds OUT (out(0x3c5,..))
	mov     al,1                        ; 180c:041e
	shl     al,cl                       ; 180c:0420
	out     dx,al                       ; 180c:0422
	mov     ax,word ptr [bp + 0fe2eh]   ; 180c:0423  y_cur
	shr     ax,2                        ; 180c:0427
	add     di,ax                       ; 180c:042a
	; load span accumulators: EAX=u_step, EDX=v_step
	mov     eax,dword ptr [bp + 0fe50h] ; 180c:042c
	mov     edx,dword ptr [bp + 0fe46h] ; 180c:0431
	; skip clipped pixels
	mov     cx,word ptr [bp + 0fe16h]   ; 180c:0436
	or      cx,cx                       ; 180c:043a
	jz      short L_skip_done           ; 180c:043c  -> 0x044a
L_skip_loop:                                ; 180c:043e
	add     dword ptr [bp + 0fe4ch],eax ; 180c:043e
	add     dword ptr [bp + 0fe42h],edx ; 180c:0443
	loop    L_skip_loop                 ; 180c:0448
L_skip_done:                                ; 180c:044a
	; draw_width+1 iterations
	mov     cx,word ptr [bp - 01ch]     ; 180c:044a
	inc     cx                          ; 180c:044d
	; switch DS to texture segment
	mov     bx,word ptr [bp + 6]        ; 180c:044e  bx = quad
	mov     ds,word ptr [bx]            ; 180c:0451  DS = texture segment
	; check remap table (read via SS: since DS now != DGROUP)
	mov     bx,word ptr ss:[_g_polyRasterState.prs_nRemapOff] ; 180c:0453
	or      bx,bx                       ; 180c:0458
	jnz     short L_remap_path          ; 180c:045a  -> 0x0489
	; --- no-remap pixel loop ---
L_norem_loop:                               ; 180c:045c
	mov     si,word ptr [bp + 0fe4eh]   ; 180c:045c  u_idx
	shl     si,1                        ; 180c:0460
	mov     si,word ptr [bp + si + 0f910h] ; 180c:0462  row_table[u_idx]
	add     si,word ptr [bp + 0fe44h]   ; 180c:0466  + v_off
	add     dword ptr [bp + 0fe4ch],eax ; 180c:046a  u += u_step
	add     dword ptr [bp + 0fe42h],edx ; 180c:046f  v += v_step
	mov     bl,byte ptr [si]            ; 180c:0474  pixel = DS:[SI]
	or      bl,bl                       ; 180c:0476
	jz      short L_norem_skip          ; 180c:0478  transparent
	mov     byte ptr es:[di],bl         ; 180c:047a  VRAM write
L_norem_skip:                               ; 180c:047d
	add     di,50h                      ; 180c:047d  next column
	loop    L_norem_loop                ; 180c:0480
	; restore DS = DGROUP (via SS)
	mov     ax,ss                       ; 180c:0482
	mov     ds,ax                       ; 180c:0484
	jmp     L_inner_next                ; 180c:0486
	; --- remap pixel loop ---
L_remap_path:                               ; 180c:0489
	push    gs                          ; 180c:0489
	xchg    eax,ecx                     ; 180c:048b
	mov     si,S169D_TEXT               ; 180c:048d  remap-table seg (FIXUPP)
	mov     gs,si                       ; 180c:0490  GS = remap table segment
	mov     ah,al                       ; 180c:0492  AH = loop count (CX low byte)
L_remap_loop:                               ; 180c:0494
	mov     si,word ptr [bp + 0fe4eh]   ; 180c:0494  u_idx
	shl     si,1                        ; 180c:0498
	mov     si,word ptr [bp + si + 0f910h] ; 180c:049a  row_table[u_idx]
	add     si,word ptr [bp + 0fe44h]   ; 180c:049e  + v_off
	add     dword ptr [bp + 0fe4ch],ecx ; 180c:04a2  u += u_step (ecx after xchg)
	add     dword ptr [bp + 0fe42h],edx ; 180c:04a7  v += v_step
	mov     al,byte ptr [si]            ; 180c:04ac  pixel = DS:[SI]
	or      al,al                       ; 180c:04ae
	jz      short L_remap_skip          ; 180c:04b0  transparent
	xlat    gs:bx                       ; 180c:04b2  AL = remap_tbl[AL]
	mov     byte ptr es:[di],al         ; 180c:04b4  VRAM write
L_remap_skip:                               ; 180c:04b7
	add     di,50h                      ; 180c:04b7  next column
	dec     ah                          ; 180c:04ba
	jnz     L_remap_loop                ; 180c:04bc
	pop     gs                          ; 180c:04be
	mov     ax,ss                       ; 180c:04c0
	mov     ds,ax                       ; 180c:04c2  restore DS
	jmp     L_inner_next                ; 180c:04c4
L_inner_exit:                               ; 180c:04c7
	; --- outer loop update ---
	mov     ax,word ptr [bp + 0fe2ch]   ; 180c:04c7  vi
	sub     ax,word ptr [bp - 0ch]      ; 180c:04cb  vi -= edge_dir
	and     ax,3                        ; 180c:04ce
	mov     word ptr [bp + 0fe2ch],ax   ; 180c:04d1  vi = result
	; check exit condition
	mov     ax,word ptr [bp - 016h]     ; 180c:04d5  short_vert
	cmp     word ptr [bp - 01ah],ax     ; 180c:04d8  bot_vert == short_vert?
	jnz     L_outer_loop                ; 180c:04db
	; --- epilogue ---
	pop     si                          ; 180c:04df
	pop     di                          ; 180c:04e0
	mov     sp,bp                       ; 180c:04e1
	pop     bp                          ; 180c:04e3
	retf                                ; 180c:04e4
_gfx_gouraud_blit_quad  ENDP

; ============================================================================
; gfx_gouraud_span_dispatch @ 180c:04e5  (301 bytes)
;
; Computes the row-clip-edge endpoint 4-tuple for a quad-corner topology.
; Dispatches by (v0*2 + v1 - 1) through an 8-entry dense jump table
; immediately following the JMP dispatch instruction to write one of 8
; permutations of {0, quad[3]-2, quad[4]-2} into
; (*out_a, *out_b, *out_c, *out_d).
;
;   void near gfx_gouraud_span_dispatch(
;       int v0, int v1, undefined2 *quad,
;       int *out_a, int *out_b, int *out_c, int *out_d);
;
; Near calling convention: return via RET (not RETF).
; Stack frame (no locals, BP frame):
;   [BP+4]  = v0
;   [BP+6]  = v1
;   [BP+8]  = quad *
;   [BP+a]  = out_a *
;   [BP+c]  = out_b *
;   [BP+e]  = out_c *
;   [BP+10] = out_d *
;
; WHY ASM: three codegen shapes BCC 3.1 does not produce: the 16-byte 8-entry
; jump table sits immediately after the dispatch JMP (function-relative 0x0014,
; before the first case body) rather than after the last RET; zeroes are stored
; via SUB AX,AX + MOV [BX],AX rather than MOV word ptr [BX],0; and there is no
; switch bounds check.  References no DGROUP data.
;
; The CS-relative jump table (L_table label word + 8 x dw case label) is
; segment-relative -- TASM emits OFFSET_16 FIXUPPs for each entry.
; ============================================================================

; void near gfx_gouraud_span_dispatch(int v0, int v1, undefined2 *quad,
;                                     int *out_a, int *out_b, int *out_c, int *out_d)
;                    [BP+4]  [BP+6]  [BP+8]       [BP+a]   [BP+c]   [BP+e]   [BP+10]
_gfx_gouraud_span_dispatch	proc near
	push	bp				; 04e5
	mov	bp,sp				; 04e6
	push	si				; 04e8

	mov	bx,word ptr [bp + 4]		; 04e9  v0
	shl	bx,1				; 04ec
	add	bx,word ptr [bp + 6]		; 04ee  v0*2 + v1
	dec	bx				; 04f1  - 1
	shl	bx,1				; 04f2  * 2 (byte index into table)
	jmp	word ptr cs:[bx + L_table]	; 04f4  dispatch through 8-entry table

; ---- 8-entry dense jump table (immediately after dispatch JMP) ------------
L_table	label	word
	dw	L_case0				; -> 180c:0509
	dw	L_case1				; -> 180c:0520
	dw	L_case2				; -> 180c:0540
	dw	L_case3				; -> 180c:0556
	dw	L_case4				; -> 180c:057c
	dw	L_case5				; -> 180c:05a6
	dw	L_case6				; -> 180c:05c5
	dw	L_case7				; -> 180c:05e8

; ---- case 0: *out_d=0, *out_c=0, *out_a=0; fall to shared tail (0602) ----
L_case0:				; 0509
	sub	ax,ax				; zero AX
	mov	bx,word ptr [bp + 10h]		; out_d
	mov	word ptr [bx],ax		; *out_d = 0
	mov	bx,word ptr [bp + 0eh]		; out_c
	mov	word ptr [bx],ax		; *out_c = 0
	mov	bx,word ptr [bp + 0ah]		; out_a
	mov	word ptr [bx],ax		; *out_a = 0
	mov	bx,word ptr [bp + 8]		; quad (for shared tail)
	jmp	L_tail0602			; -> 011d (LAB_180c_0602)

; ---- case 1: *out_d=0, *out_c=0, *out_b=0; iVar1=quad[3]-2; out_b=out_a ---
L_case1:				; 0520
	sub	ax,ax
	mov	bx,word ptr [bp + 10h]		; out_d
	mov	word ptr [bx],ax		; *out_d = 0
	mov	bx,word ptr [bp + 0eh]		; out_c
	mov	word ptr [bx],ax		; *out_c = 0
	mov	bx,word ptr [bp + 0ch]		; out_b
	mov	word ptr [bx],ax		; *out_b = 0
	mov	bx,word ptr [bp + 8]		; quad
	mov	ax,word ptr [bx + 6]		; quad[3]
	sub	ax,2				; quad[3]-2
	mov	bx,word ptr [bp + 0ah]		; out_a (new dest = out_b slot)
	jmp	L_tail060b			; -> 0126 (LAB_180c_060b): *out_a=iVar1

; ---- case 2: *out_c=0, *out_b=0, *out_a=0; fall to LAB_0570 ---------------
L_case2:				; 0540
	sub	ax,ax
	mov	bx,word ptr [bp + 0eh]		; out_c
	mov	word ptr [bx],ax		; *out_c = 0
	mov	bx,word ptr [bp + 0ch]		; out_b
	mov	word ptr [bx],ax		; *out_b = 0
	mov	bx,word ptr [bp + 0ah]		; out_a
	mov	word ptr [bx],ax		; *out_a = 0
	mov	bx,word ptr [bp + 8]		; quad (for LAB_0570)
	jmp	short L_tail0570		; -> 008b (LAB_180c_0570)

; ---- case 3: *out_b=quad[3]-2, *out_a=quad[3]-2, *out_c=0; then LAB_0570 --
L_case3:				; 0556
	mov	bx,word ptr [bp + 8]		; quad
	mov	ax,word ptr [bx + 6]		; quad[3]
	sub	ax,2
	mov	si,word ptr [bp + 0ch]		; out_b
	mov	word ptr [si],ax		; *out_b = quad[3]-2
	mov	si,word ptr [bp + 0ah]		; out_a
	mov	word ptr [si],ax		; *out_a = quad[3]-2
	mov	si,word ptr [bp + 0eh]		; out_c
	mov	word ptr [si],0			; *out_c = 0
; fall through to LAB_0570
L_tail0570:				; 0570 (LAB_180c_0570)
	mov	ax,word ptr [bx + 8]		; quad[4]  (BX=quad from case3 or case2)
	sub	ax,2
	mov	bx,word ptr [bp + 10h]		; out_d (new dest for LAB_060b)
	jmp	L_tail060b			; -> 0126 (LAB_180c_060b): *out_d=iVar1

; ---- case 4: *out_b=quad[3]-2, *out_a=quad[3]-2, *out_c=quad[4]-2; --------
;              then LAB_059d (*out_d=0; return)
L_case4:				; 057c
	mov	bx,word ptr [bp + 8]		; quad
	mov	ax,word ptr [bx + 6]		; quad[3]
	sub	ax,2
	mov	si,word ptr [bp + 0ch]		; out_b
	mov	word ptr [si],ax		; *out_b = quad[3]-2
	mov	si,word ptr [bp + 0ah]		; out_a
	mov	word ptr [si],ax		; *out_a = quad[3]-2
	mov	ax,word ptr [bx + 8]		; quad[4]
	sub	ax,2
	mov	bx,word ptr [bp + 0eh]		; out_c
	mov	word ptr [bx],ax		; *out_c = quad[4]-2
	mov	bx,word ptr [bp + 10h]		; out_d (dest for LAB_059d: *out_d=0)
; fall through to LAB_059d
L_tail059d:				; 059d (LAB_180c_059d)
	mov	word ptr [bx],0			; *out_d (or *out_b via case6) = 0
	pop	si				; 05a1
	mov	sp,bp				; 05a2
	pop	bp				; 05a4
	ret					; 05a5

; ---- case 5: *out_d=0, *out_b=0, *out_a=0; iVar1=quad[4]-2; out_b=out_c ---
L_case5:				; 05a6
	sub	ax,ax
	mov	bx,word ptr [bp + 10h]		; out_d
	mov	word ptr [bx],ax		; *out_d = 0
	mov	bx,word ptr [bp + 0ch]		; out_b
	mov	word ptr [bx],ax		; *out_b = 0
	mov	bx,word ptr [bp + 0ah]		; out_a
	mov	word ptr [bx],ax		; *out_a = 0
	mov	bx,word ptr [bp + 8]		; quad
	mov	ax,word ptr [bx + 8]		; quad[4]
	sub	ax,2
	mov	bx,word ptr [bp + 0eh]		; out_c (new dest for LAB_060b)
	jmp	short L_tail060b		; -> 0126 (LAB_180c_060b): *out_c=iVar1

; ---- case 6: *out_d=quad[4]-2, *out_c=quad[4]-2, *out_a=quad[3]-2; --------
;              then LAB_059d (*out_b=0; return)
L_case6:				; 05c5
	mov	bx,word ptr [bp + 8]		; quad
	mov	ax,word ptr [bx + 8]		; quad[4]
	sub	ax,2
	mov	si,word ptr [bp + 10h]		; out_d
	mov	word ptr [si],ax		; *out_d = quad[4]-2
	mov	si,word ptr [bp + 0eh]		; out_c
	mov	word ptr [si],ax		; *out_c = quad[4]-2
	mov	ax,word ptr [bx + 6]		; quad[3]
	sub	ax,2
	mov	bx,word ptr [bp + 0ah]		; out_a
	mov	word ptr [bx],ax		; *out_a = quad[3]-2
	mov	bx,word ptr [bp + 0ch]		; out_b (dest for LAB_059d: *out_b=0)
	jmp	short L_tail059d		; -> 00b8 (LAB_180c_059d)

; ---- case 7: *out_d=quad[4]-2, *out_c=quad[4]-2, *out_a=0; -----------------
;              then fall to shared tail (0602): iVar1=quad[3]-2; *out_b=iVar1
L_case7:				; 05e8
	mov	bx,word ptr [bp + 8]		; quad
	mov	ax,word ptr [bx + 8]		; quad[4]
	sub	ax,2
	mov	si,word ptr [bp + 10h]		; out_d
	mov	word ptr [si],ax		; *out_d = quad[4]-2
	mov	si,word ptr [bp + 0eh]		; out_c
	mov	word ptr [si],ax		; *out_c = quad[4]-2
	mov	si,word ptr [bp + 0ah]		; out_a
	mov	word ptr [si],0			; *out_a = 0
; fall through to LAB_0602
L_tail0602:				; 0602 (LAB_180c_0602)
	mov	ax,word ptr [bx + 6]		; quad[3]  (BX=quad)
	sub	ax,2
	mov	bx,word ptr [bp + 0ch]		; out_b
; fall through to LAB_060b
L_tail060b:				; 060b (LAB_180c_060b)
	mov	word ptr [bx],ax		; *out_b = iVar1
	pop	si				; 060d
	mov	sp,bp				; 060e
	pop	bp				; 0610
	ret					; 0611

_gfx_gouraud_span_dispatch	endp

; ============================================================================
; compare_edge_slopes @ 180c:0612  (211 bytes)
;
; Slope comparator for polygon scan-conversion.  Given two edges (each
; described by dx=x_bot-y_base and dy=x_top-y1), computes the integer
; quotient dy/dx (slope) for each edge with a 16-bit-fractional tiebreak;
; returns 1 if slope2 <= slope1 (edge2 is "shallower"), -1 otherwise.
; Vertical-edge sentinel: dx==0 is replaced by 1 with dy forced to 0x7fff.
; The opposite-quadrant case (one dx positive, one negative) is
; short-circuited before the division.  Used by the polygon fill driver
; gfx_gouraud_blit_quad (above).
;
;   int near compare_edge_slopes(int x1, int x2, int y_base, int y1,
;                                int x3, int x4);
;   Stack: [BP+4]=x1 [BP+6]=x2 [BP+8]=y_base [BP+a]=y1 [BP+c]=x3 [BP+e]=x4
;   Returns 1 or -1 (0xFFFF) in AX.
;
; WHY ASM: the division section pairs CWD with unsigned DIV (a mixed
; signed/unsigned idiom), holds the first division's quotient/remainder in BX/CX
; across the second, then scales the remainders by 2^16 via XOR AX,AX;DIV for the
; fraction tiebreak (a C source emits F_LUDIV@ library calls instead), and it
; saves no SI/DI (temporaries live in AX/BX/CX/DX only).
;
; Epilogue layout (two distinct return-1 blocks, one return-(-1) block):
;   069a: MOV AX,1; MOV SP,BP; POP BP; RET        -- early return 1 (before divide)
;   06a1: check_neg8:
;   06ad: MOV AX,0FFFFh; MOV SP,BP; POP BP; RET   -- return -1 (JL/JA 06ca/06dc target)
;   06b4: L_divide: ...
;   06c8: JL 069a   (backward to early return-1)
;   06ca: JA 06ad   (backward to return-(-1))
;   06dc: JA 06ad   (backward to return-(-1))
;   06de: MOV AX,1; MOV SP,BP; POP BP; RET        -- late return 1 (fallthrough)
; ============================================================================

; int near compare_edge_slopes(int x1, int x2, int y_base, int y1, int x3, int x4)
;  [BP+4]=x1  [BP+6]=x2  [BP+8]=y_base  [BP+a]=y1  [BP+c]=x3  [BP+e]=x4
; locals: [BP-2]=temp  [BP-4]=local_6(dx1)  [BP-6]=local_8(dx2)
;         [BP-8]=local_a(dy1)  [BP-a]=local_c(dy2)
_compare_edge_slopes    proc near
	push    bp                              ; 0612
	mov     bp,sp                           ; 0613
	sub     sp,0ah                          ; 0615  10 bytes locals
	; local_a = x2 - y1
	mov     ax,word ptr [bp + 6]            ; 0618
	sub     ax,word ptr [bp + 0ah]          ; 061b
	mov     word ptr [bp - 8],ax            ; 061e
	; local_c = x4 - y1
	mov     ax,word ptr [bp + 0eh]          ; 0621
	sub     ax,word ptr [bp + 0ah]          ; 0624
	mov     word ptr [bp - 0ah],ax          ; 0627
	; local_6 = x1 - y_base
	mov     ax,word ptr [bp + 4]            ; 062a
	sub     ax,word ptr [bp + 8]            ; 062d
	mov     word ptr [bp - 4],ax            ; 0630
	or      ax,ax                           ; 0633
	jnz     short L_dx1_nz                  ; 0635
	mov     word ptr [bp - 4],1             ; 0637
	mov     word ptr [bp - 8],07fffh        ; 063c
L_dx1_nz:
	; local_8 = x3 - y_base
	mov     ax,word ptr [bp + 0ch]          ; 0641
	sub     ax,word ptr [bp + 8]            ; 0644
	mov     word ptr [bp - 6],ax            ; 0647
	or      ax,ax                           ; 064a
	jnz     short L_dx2_nz                  ; 064c
	mov     word ptr [bp - 6],1             ; 064e
	mov     word ptr [bp - 0ah],07fffh      ; 0653
L_dx2_nz:
	; Both-negative check: if local_6>=0 OR local_8>=0 -> not-both-neg
	cmp     word ptr [bp - 4],0             ; 0658
	jge     short L_not_both_neg            ; 065c
	cmp     word ptr [bp - 6],0             ; 065e
	jge     short L_not_both_neg            ; 0662
	; Both negative: negate both dx, swap dy values
	mov     ax,word ptr [bp - 6]            ; 0664
	mov     word ptr [bp - 2],ax            ; 0667  temp = local_8
	mov     ax,word ptr [bp - 4]            ; 066a
	neg     ax                              ; 066d
	mov     word ptr [bp - 6],ax            ; 066f  local_8 = -local_6
	mov     ax,word ptr [bp - 2]            ; 0672
	neg     ax                              ; 0675
	mov     word ptr [bp - 4],ax            ; 0677  local_6 = -(old local_8)
	mov     ax,word ptr [bp - 0ah]          ; 067a
	mov     word ptr [bp - 2],ax            ; 067d  temp = local_c
	mov     ax,word ptr [bp - 8]            ; 0680
	mov     word ptr [bp - 0ah],ax          ; 0683  local_c = local_a
	mov     ax,word ptr [bp - 2]            ; 0686
	mov     word ptr [bp - 8],ax            ; 0689  local_a = old local_c
	jmp     short L_divide                  ; 068c
L_not_both_neg:
	; local_6<0 && local_8>0 -> return 1 (early)
	cmp     word ptr [bp - 4],0             ; 068e
	jge     short L_check_neg8              ; 0692
	cmp     word ptr [bp - 6],0             ; 0694
	jle     short L_check_neg8              ; 0698
	; Return 1 (early exit -- also JL target from 06c8)
L_ret_1_early:
	mov     ax,1                            ; 069a
	mov     sp,bp                           ; 069d
	pop     bp                              ; 069f
	ret                                     ; 06a0
L_check_neg8:
	; local_8<0 && local_6>0 -> return -1 (early)
	cmp     word ptr [bp - 6],0             ; 06a1
	jge     short L_divide                  ; 06a5
	cmp     word ptr [bp - 4],0             ; 06a7
	jle     short L_divide                  ; 06ab
	; Return -1 (also JA target from 06ca and 06dc)
L_ret_neg1:
	mov     ax,0ffffh                       ; 06ad
	mov     sp,bp                           ; 06b0
	pop     bp                              ; 06b2
	ret                                     ; 06b3
L_divide:
	; quotient1 = local_a / local_6 via CWD + unsigned DIV
	mov     ax,word ptr [bp - 8]            ; 06b4
	cwd                                     ; 06b7
	div     word ptr [bp - 4]               ; 06b8  AX=q1, DX=r1
	mov     bx,ax                           ; 06bb  BX = q1
	mov     cx,dx                           ; 06bd  CX = r1
	; quotient2 = local_c / local_8 via CWD + unsigned DIV
	mov     ax,word ptr [bp - 0ah]          ; 06bf
	cwd                                     ; 06c2
	div     word ptr [bp - 6]               ; 06c3  AX=q2, DX=r2
	cmp     ax,bx                           ; 06c6
	jl      short L_ret_1_early             ; 06c8  signed: q2<q1 -> ret 1 (BACKWARD)
	ja      short L_ret_neg1                ; 06ca  unsigned: q2>q1 -> ret -1 (BACKWARD)
	; Quotients equal: compare fractional parts
	; frac2 = (r2 * 65536) / local_8;  DX still = r2
	xor     ax,ax                           ; 06cc
	div     word ptr [bp - 6]               ; 06ce  frac2 in AX
	mov     bx,ax                           ; 06d1
	xor     ax,ax                           ; 06d3
	mov     dx,cx                           ; 06d5  DX = r1
	div     word ptr [bp - 4]               ; 06d7  frac1 in AX
	cmp     bx,ax                           ; 06da  frac2 vs frac1
	ja      short L_ret_neg1                ; 06dc  frac2>frac1 -> ret -1 (BACKWARD)
	; frac2 <= frac1: return 1 (late -- fallthrough)
	mov     ax,1                            ; 06de
	mov     sp,bp                           ; 06e1
	pop     bp                              ; 06e3
	ret                                     ; 06e4
_compare_edge_slopes    endp

; ============================================================================
; edge_step_init @ 180c:06e5  (91 bytes)
;
; Initializes an x-step/fraction accumulator for one polygon edge over the
; given scanline count.  Computes step = (step[1] - step[0]) / (count + 1),
; stores the integer step in step[1], and the clamped negated low-word fraction
; in step[0] (clamped to 0x8000 when the masked value is 0).  Heavily used by
; the polygon-fill driver (gfx_gouraud_blit_quad, above), which calls it via
; PUSH CS + CALL NEAR PTR to reproduce the original's near-call encoding
; despite this proc's own FAR/RETF declaration.
;
;   void edge_step_init(long *step, int count);   (__cdecl16far, RETF)
;
; WHY ASM (not C): the original is a tight, frameless 386 routine that addresses
; its incoming stack args through `MOV BX,SP` + `[BX+4]`/`[BX+6]` with NO BP
; frame, keeps the 32-bit `long` working value live in EAX (and its low word in
; CX) across the whole body, and branches into two parallel negate/clamp tails.
; BCC 3.1 in this environment cannot reproduce that from any C source/flag
; combination: on a 386 `long` function it ALWAYS sets up a BP frame (push bp /
; mov bp,sp), pushes SI/DI, and spills the long to a `[bp-N]` stack slot.  No
; -O / -O1 / -O2 / -k / -3 combo drops the frame or keeps the long register-
; resident -- the same frame-omission + register-allocation wall as the sibling
; frameless 386 long routine distdir_octagonal_distance_dxdy (DISTDIR.ASM).  The
; routine references no data.
; ============================================================================

; void edge_step_init(long *step, int count)
_edge_step_init	proc far
	mov	bx,sp
	mov	cx,word ptr [bx + 6]		; count
	mov	bx,word ptr [bx + 4]		; step ptr
	mov	word ptr [bx],0			; fraction low word = 0
	mov	word ptr [bx + 4],0		; step = 0
	or	cx,cx
	jle	short L_zero			; count <= 0 -> step[1]=0, done
	inc	cx				; count + 1
	mov	eax,dword ptr [bx + 4]
	sub	eax,dword ptr [bx]		; step[1] - step[0]
	and	ecx,0ffffh			; zero-extend divisor
	cdq
	idiv	ecx				; eax = (step[1]-step[0]) / (count+1)
	mov	dword ptr [bx + 4],eax		; step[1] = quotient
	jns	short L_neg			; quotient >= 0 -> negate path
	mov	cx,ax				; quotient < 0: fraction = low word
	and	eax,0ffff8000h
	jnz	short L_store
	mov	cx,8000h			; clamp
L_store:
	mov	word ptr [bx],cx
	retf
L_neg:
	neg	eax				; fraction = -quotient
	mov	cx,ax
	and	eax,0ffff8000h
	jnz	short L_store2
	mov	cx,8000h			; clamp
L_store2:
	mov	word ptr [bx],cx
	retf
L_zero:
	mov	dword ptr [bx + 4],0		; step[1] = 0
	retf
_edge_step_init	endp

S180C_TEXT ENDS
	END
