; ============================================================================
; POLYRAST.ASM -- KRONDOR.EXE segment 0x169d
;               EGA/planar polygon + scaled-sprite rasterizer ("polyrast_")
;
; ONE module: all 3 functions + the CS-resident inter-function DATA block.
; Segment base linear: 0x169d0 (paragraph 0x169d); the first proc
; (_polyrast_edge_init_step) begins at offset 0x002.
;
; Layout (segment offsets):
;   0x002 .. 0x05c   _polyrast_edge_init_step          (90 bytes)
;   0x05c .. 0xf5c   CS-RESIDENT DATA block (3840 B, BSS/zero-init at load):
;                      0x05c .. 0xa5c   g_abFogRemapTable (2560 B, exported)
;                      0xa5c .. 0xb5c   g_abCursorPaletteLut (256 B, exported)
;                      0xb5c .. 0xf5c   rasterizer scratch / LUT scratch (1024 B)
;   0xf5c .. 0xf70   per-span scratchpad (_DAT_169d_0f5c..0f6f, 20 B)
;   0xf70 .. 0x131c  _polyrast_gouraud_blit_clipped    (940 bytes)
;   0x131c .. 0x1324 SMC island (_spr_data_ptr/_spr_height + 4B pad, 8 B)
;   0x1324 .. 0x16f5 _polyrast_spr_scaled_blit_planar  (977 bytes)
;
; THE DATA BLOCK IS BSS.  Every byte of 0x05c..0xf5c is ZERO at load.  It is
; the rasterizer CS-resident state + LUT scratch region, filled at RUNTIME, not
; at load time.  Two distinct runtime fills:
;   (a) The per-span edge/clip scratchpad (0xf5c..0xf6f) is owned + written by
;       _polyrast_gouraud_blit_clipped each span (labels below).
;   (b) The CURSOR PALETTE REMAP LUT at off 0xa5c is written by the inventory UI
;       (invui_*, 0x56889 / 0x56975) via FAR stores `MOV ES,0x169d; ES:[BX+0a5ch]`
;       with identity / palette index values, then consumed by the rasterizer
;       XLAT path: when g_polyRasterState.nRemapTableOff == 0xa5c the inner loops do
;       `xlat cs:bx` (BX=0xa5c) to remap each source pixel through this table.
;       Because XLAT indexes by a full 0..255 pixel byte the table is 256 bytes
;       (0xa5c..0xb5c).  Exported (g_abCursorPaletteLut) so those C consumers
;       reference it by symbol instead of a hardcoded 0x169d:0a5c.
;   The remaining scratch bytes (2560 before, 1024 after the LUT) are the
;   rasterizer general CS-resident remap/scratch space, likewise zero at load
;   and written at runtime.
;
; WHY ASM: each of the 3 procs uses idioms with no C form (frameless arg access,
; 32-bit ops in 16-bit code, XLAT CS:BX, self-modifying code, REP MOVSW RLE,
; carry-bit Bresenham).  The near CALL _polyrast_edge_init_step (PUSH CS + E8)
; resolves internally with no FIXUPP.
;
; SEGMENT/ADDRESSING: like R3D.ASM, procs are PLAIN LABELS with explicit RETF
; (never "proc far"), so "call <label>" assembles as E8 near.  CS-resident data
; is reached with an explicit "cs:" override (the procs run with DS=DGROUP, not
; DS=CS).  GENUINE DGROUP data (graphics_context, edge accumulators,
; g_polyRasterState.nRemapTableOff, g_pMainScratchBuf, _gfx_gouraud_blit_quad)
; stays extern + FIXUPP'd.
; ============================================================================

	.386p

; --- cross-segment far call (seg 180c) --------------------------------------
	extrn	_gfx_gouraud_blit_quad:far

; --- DGROUP externals (genuine DGROUP, SS:/DS: FIXUPP'd) ---------------------
	extrn	_g_graphics_context:byte		; base for gfxctx aliases
GfxContext	struc
	db	3 dup(?)
bClip_enabled	db	?
nClip_xmin	db	?
	db	1 dup(?)
nClip_xmax	db	?
	db	1 dup(?)
nClip_ymin	db	?
	db	1 dup(?)
nClip_ymax	db	?
	db	13 dup(?)
wGfxBlitDstPage	db	?
GfxContext	ends

	extrn	_g_pMainScratchBuf:dword

; --- Polygon/scaled-sprite rasterizer shared state (DGROUP+0x28e) -------------
; PolyRasterState { int nRemapTableOff; PolyEdge edge[3]; }, PolyEdge { long acc;
; long step; }.  Each edge is a 16.16 fixed-point interpolator: .acc = running
; value (integer coordinate in the high word, fraction in the low word), .step =
; per-row increment.  Every access below names a struct field.
; ".prs_eN_acc + 2" reads the integer high word of that 32-bit accumulator;
; "+ 3" its high byte.
PolyRasterState	struc
prs_nRemapOff	dw	?	; +00h  DGROUP+0x28e  XLAT remap LUT offset (edge[-]: nRemapTableOff)
prs_e0_acc	dd	?	; +02h  DGROUP+0x290  edge[0].acc
prs_e0_step	dd	?	; +06h  DGROUP+0x294  edge[0].step
prs_e1_acc	dd	?	; +0ah  DGROUP+0x298  edge[1].acc
prs_e1_step	dd	?	; +0eh  DGROUP+0x29c  edge[1].step
prs_e2_acc	dd	?	; +12h  DGROUP+0x2a0  edge[2].acc
prs_e2_step	dd	?	; +16h  DGROUP+0x2a4  edge[2].step
PolyRasterState	ends

	extrn	_g_polyRasterState:byte		; DGROUP+0x028e (PolyRasterState)

	_DATA	segment word public 'DATA'
	_DATA	ends
	_BSS	segment word public 'BSS'
	_BSS	ends
	DGROUP	group _DATA, _BSS

; In-segment label references ("cs:[reg+_lbl]", "[_lbl]", internal near CALLs)
; carry segment-relative fixups that TLINK resolves against the canonic frame.
S169D_TEXT	segment word public use16 'CODE'
	assume	cs:S169D_TEXT, ds:DGROUP

	public	_polyrast_edge_init_step
	public	_polyrast_gouraud_blit_clipped
	public	_polyrast_spr_scaled_blit_planar

; ============================================================================
; _polyrast_edge_init_step  -- offset 0x002, size 90 bytes
; ============================================================================
; void polyrast_edge_init_step(long *edge, uint steps)
;   [SP+4] = edge (near ptr),  [SP+6] = steps
_polyrast_edge_init_step:
	mov	bx,sp
	mov	cx,word ptr [bx+6]		; steps
	mov	bx,word ptr [bx+4]		; edge
	mov	word ptr [bx],0			; edge[0] low = 0
	mov	word ptr [bx+4],0		; edge[1] low = 0
	or	cx,cx
	jle	L_zero				; steps <= 0
	mov	eax,dword ptr [bx+4]		; edge[1]
	sub	eax,dword ptr [bx]		; - edge[0]
	and	ecx,0ffffh			; zero-extend steps
	cdq
	idiv	ecx				; EAX = (edge[1]-edge[0]) / steps
	mov	dword ptr [bx+4],eax		; edge[1] = quotient
	jns	L_pos				; quotient >= 0
	mov	cx,ax				; candidate low word
	and	eax,0ffff8000h
	jnz	L_store1
	mov	cx,8000h
L_store1:
	mov	word ptr [bx],cx
	retf
L_pos:
	neg	eax				; -quotient
	mov	cx,ax
	and	eax,0ffff8000h
	jnz	L_store2
	mov	cx,8000h
L_store2:
	mov	word ptr [bx],cx
	retf
L_zero:
	mov	dword ptr [bx+4],0		; edge[1] = 0
	retf
; ============================================================================
; CS-RESIDENT DATA BLOCK  0x05c .. 0xf5c  (3840 bytes, BSS / zero-init at load)
; Filled at runtime (see file header).
; ============================================================================

; 0x05c .. 0xa5c (2560 B): SPRITE FOG REMAP TABLE (zero-init at load).
; Filled at runtime by zone_load (0x7507b), which reads Z%02u.RMP into this
; block via bak_fread_chunked(g_abFogRemapTable, 0x100, g_nFogRemapTableCount,..)
; -- up to 10 banks of 256 bytes (count = g_nFogRemapTableCount).  Each bank is
; an XLAT remap table for one fog/distance bucket; the rasterizer inner loops
; XLAT cs:[bx] through it when g_polyRasterState.nRemapTableOff selects a bank in
; 0x5c..0xa5c (same mechanism as the cursor LUT at 0xa5c below).  Exported so
; the C consumer (zone_load) references it by symbol instead of MK_FP(169d,5c).
	public	_g_abFogRemapTable
_g_abFogRemapTable	label byte	; <-- export alias (C: gfx169d.h)
g_abFogRemapTable	db	0a00h dup(0)

; 0xa5c .. 0xb5c (256 B): CURSOR PALETTE REMAP LUT.
; XLAT cs:[bx+al] table used by the rasterizer inner loops when
; g_polyRasterState.nRemapTableOff == 0xa5c; written at runtime by invui_* (0x56889 /
; 0x56975) with identity / palette-index entries.  256 entries (indexed by a
; full 0..255 source-pixel byte).  Exported for the C consumers.
	public	_g_abCursorPaletteLut
_g_abCursorPaletteLut	label byte	; <-- export alias (C: r3d.h)
g_abCursorPaletteLut	db	100h dup(0)

; 0xb5c .. 0xf5c (1024 B): rasterizer CS-resident remap/scratch space (zero-init)
	db	400h dup(0)

; ============================================================================
; _polyrast_gouraud_blit_clipped  -- scratchpad @ 0xf5c, proc @ 0xf70 (940 B)
; ============================================================================
; ---- CS-resident scratchpad (owned by this module; lives before the proc) ----
; These 14 bytes hold per-span state written at span setup time and read in
; the inner pixel loop.  The scratch words are named by segment:offset.
	public	_DAT_169d_0f5c, _DAT_169d_0f5e
	public	_DAT_169d_0f64, _DAT_169d_0f66, _DAT_169d_0f68
	public	_DAT_169d_0f6a, _DAT_169d_0f6c
	public	_DAT_169d_0f6e, _DAT_169d_0f6f

_DAT_169d_0f5c	dw	0		; [0] step count (_DAT_169d_0f5c)
_DAT_169d_0f5e	dw	0		; [2] x start   (_DAT_169d_0f5e)
		dw	0		; [4] gap (0xf60-0xf61)
		dw	0		; [6] gap (0xf62-0xf63)
_DAT_169d_0f64	dw	0		; [8] height-1  (_DAT_169d_0f64)
_DAT_169d_0f66	dw	0		; [a] height    (_DAT_169d_0f66)
_DAT_169d_0f68	dw	0		; [c] source col ptr (_DAT_169d_0f68)
_DAT_169d_0f6a	dw	0		; [e] y-clip lo (_DAT_169d_0f6a)
_DAT_169d_0f6c	dw	0		; [10] y-clip hi (_DAT_169d_0f6c)
_DAT_169d_0f6e	db	0		; [12] clip-active byte (_DAT_169d_0f6e)
_DAT_169d_0f6f	db	0		; [13] swap flag (_DAT_169d_0f6f)

; ---- void polyrast_gouraud_blit_clipped(param_1, param_2, param_3) ----------
;   [BP+06h] = param_1 (ptr to sprite descriptor: seg, off, ...)
;   [BP+08h] = param_2 (ptr to x-span array: x0,x1 repeated for 2 edges)
;   [BP+0ah] = param_3 (ptr to y-span array: y0,y1 repeated)
; ---------------------------------------------------------------------------
_polyrast_gouraud_blit_clipped:
	push	bp
	mov	bp,sp
	push	si
	push	di
	push	ds

	; Check that span is axis-aligned (x0==x1 for both edges)
	mov	si,word ptr [bp+8h]
	mov	di,word ptr [bp+0ah]
	mov	ax,word ptr [si]
	cmp	ax,word ptr [si+6h]
	jnz	L_call_quad
	mov	bx,word ptr [si+2h]
	cmp	bx,word ptr [si+4h]
	jnz	L_call_quad
	; Check Y span is non-degenerate and sorted
	mov	bx,word ptr [di]
	cmp	bx,word ptr [di+6h]
	jg	L_call_quad
	mov	bx,word ptr [di+2h]
	cmp	bx,word ptr [di+4h]
	jg	L_call_quad

	; Clear swap flag; compute step count
	mov	byte ptr cs:[_DAT_169d_0f6f],0h
	mov	cx,word ptr [si+2h]
	sub	cx,word ptr [si]
	jz	L_epilogue_ds		; step == 0 -> nothing to draw
	jg	L_have_steps		; step > 0 -> already ascending

	; Swap: param_2[0]<->param_2[1] and param_3[0]<->param_3[1] etc.
	mov	bx,word ptr [si]
	xchg	word ptr [si+2h],bx
	mov	word ptr [si],bx
	mov	bx,word ptr [di]
	xchg	word ptr [di+2h],bx
	mov	word ptr [di],bx
	mov	bx,word ptr [si+4h]
	xchg	word ptr [si+6h],bx
	mov	word ptr [si+4h],bx
	mov	bx,word ptr [di+4h]
	xchg	word ptr [di+6h],bx
	mov	word ptr [di+4h],bx
	neg	cx
	mov	ax,word ptr [si]
	inc	byte ptr cs:[_DAT_169d_0f6f]

L_have_steps:
	; ax = x start, cx = step count
	mov	cs:[_DAT_169d_0f5e],ax
	mov	word ptr cs:[_DAT_169d_0f5c],cx
	jmp	short L_test_clip_y	; -> check Y clip / classify vertices

L_call_quad:
	; Degenerate span -- delegate to the general quad rasterizer
	mov	bx,word ptr [bp+6h]
	push	di
	push	si
	push	bx
	call	far ptr _gfx_gouraud_blit_quad
	add	sp,6h
	pop	ds
	pop	di
	pop	si
	pop	bp
	retf

; ---- Y-clip test: check if all four Y vertices lie within [clip_ymin,clip_ymax] ----
L_test_clip_y:
	mov	cl,0h
	test	word ptr ss:[_g_graphics_context.bClip_enabled],0fh
	jz	L_clip_result_ok
	mov	ax,word ptr ss:[_g_graphics_context.nClip_ymin]
	cmp	ax,word ptr [di]
	jg	L_clip_vertex_out
	cmp	ax,word ptr [di+2h]
	jg	L_clip_vertex_out
	cmp	ax,word ptr [di+4h]
	jg	L_clip_vertex_out
	cmp	ax,word ptr [di+6h]
	jg	L_clip_vertex_out
	mov	ax,word ptr ss:[_g_graphics_context.nClip_ymax]
	cmp	ax,word ptr [di]
	jl	L_clip_vertex_out
	cmp	ax,word ptr [di+2h]
	jl	L_clip_vertex_out
	cmp	ax,word ptr [di+4h]
	jl	L_clip_vertex_out
	cmp	ax,word ptr [di+6h]
	jl	L_clip_vertex_out
	jmp	short L_clip_result_ok
L_clip_vertex_out:
	inc	cl
L_clip_result_ok:
	mov	byte ptr cs:[_DAT_169d_0f6e],cl

	; Initialise edge 0 accumulator (y-start / y-end into SS:[0x292]/[0x296])
	mov	bx,offset _g_polyRasterState.prs_e0_acc
	mov	ax,word ptr [di]
	mov	word ptr [bx+2h],ax		; g_nPolyrastEdge0StartHi = DI[0]
	mov	ax,word ptr [di+2h]
	mov	word ptr [bx+6h],ax		; g_nPolyrastEdge0EndHi   = DI[2]
	push	word ptr cs:[_DAT_169d_0f5c]
	push	bx
	push	cs
	call	_polyrast_edge_init_step	; polyrast_edge_init_step(edge0, steps)
	add	sp,4h

	; Initialise edge 1 accumulator
	mov	ax,word ptr [di+6h]
	mov	bx,offset _g_polyRasterState.prs_e1_acc
	mov	word ptr [bx+2h],ax		; g_nPolyrastEdge1StartHi = DI[6]
	mov	ax,word ptr [di+4h]
	mov	word ptr [bx+6h],ax		; g_nPolyrastEdge1EndHi   = DI[4]
	push	word ptr cs:[_DAT_169d_0f5c]
	push	bx
	push	cs
	call	_polyrast_edge_init_step
	add	sp,4h

	; Load sprite descriptor
	mov	si,word ptr [bp+6h]
	mov	ax,word ptr [si+8h]
	mov	cs:[_DAT_169d_0f66],ax		; height
	mov	ax,word ptr [si+6h]
	mov	cs:[_DAT_169d_0f64],ax		; height-1
	dec	ax
	mov	bx,offset _g_polyRasterState.prs_e2_acc
	mov	cx,0h
	test	byte ptr cs:[_DAT_169d_0f6f],1h	; swapped?
	jz	L_edge2_no_swap
	xchg	ax,cx
L_edge2_no_swap:
	mov	word ptr [bx+2h],cx		; g_nPolyrastEdge2StartHi
	mov	word ptr [bx+6h],ax		; g_nPolyrastEdge2EndHi
	push	word ptr cs:[_DAT_169d_0f5c]
	push	bx
	push	cs
	call	_polyrast_edge_init_step	; edge2 = colour gradient
	add	sp,4h

	; Set ES = video buffer segment (g_wGfxBlitDstPage), load source pointer
	mov	es,word ptr [_g_graphics_context.wGfxBlitDstPage]
	mov	ds,word ptr [si]		; DS = sprite segment
	mov	si,word ptr ss:[si+2h]		; SI = sprite column offset
	mov	word ptr cs:[_DAT_169d_0f68],si

	; ---- X-clip gate ----
	test	word ptr ss:[_g_graphics_context.bClip_enabled],0fh
	jz	L_x_clip_done

	mov	bx,word ptr cs:[_DAT_169d_0f5e]
	cmp	bx,word ptr ss:[_g_graphics_context.nClip_xmax]
	jg	L_epilogue_ds		; span starts past right edge -> skip

	add	bx,word ptr cs:[_DAT_169d_0f5c]
	cmp	bx,word ptr ss:[_g_graphics_context.nClip_xmin]
	jl	L_epilogue_ds		; span ends before left edge -> skip

	; Left-clip: advance accumulators if span extends past left edge
	mov	cx,word ptr ss:[_g_graphics_context.nClip_xmin]
	sub	cx,word ptr cs:[_DAT_169d_0f5e]
	jle	L_no_left_clip
	mov	ax,word ptr ss:[_g_graphics_context.nClip_xmin]
	mov	cs:[_DAT_169d_0f5e],ax
	and	cx,0ffffh
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e0_step]
	cdq
	imul	ecx
	add	dword ptr ss:[_g_polyRasterState.prs_e0_acc],eax
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e1_step]
	cdq
	imul	ecx
	add	dword ptr ss:[_g_polyRasterState.prs_e1_acc],eax
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e2_step]
	cdq
	imul	ecx
	add	dword ptr ss:[_g_polyRasterState.prs_e2_acc],eax
	sub	word ptr cs:[_DAT_169d_0f5c],cx

L_no_left_clip:
	; Right-clip: truncate step count if span extends past right edge
	mov	cx,word ptr cs:[_DAT_169d_0f5e]
	add	cx,word ptr cs:[_DAT_169d_0f5c]
	dec	cx
	sub	cx,word ptr ss:[_g_graphics_context.nClip_xmax]
	jle	L_x_clip_done
	sub	word ptr cs:[_DAT_169d_0f5c],cx

L_x_clip_done:
	; ---- Check step count > 0 before entering loop ----
	cmp	word ptr cs:[_DAT_169d_0f5c],0h
	jle	L_epilogue_ds

	; ---- Branch: clipped (Y) path vs unclipped path ----
	test	byte ptr cs:[_DAT_169d_0f6e],0fh
	jnz	L_loop_clipped
	nop

; ===========================================================================
; UNCLIPPED INNER LOOP (_DAT_169d_0f6e == 0)
; One iteration = one column of the gouraud-shaded span.
; Registers on entry: DS = sprite seg, ES = video seg, SI = src ptr (below)
; ===========================================================================
L_loop_unclipped:
	mov	si,word ptr cs:[_DAT_169d_0f68]
	mov	ax,word ptr ss:[_g_polyRasterState.prs_e2_acc + 2]
	mov	dx,0h
	imul	word ptr cs:[_DAT_169d_0f66]
	add	si,ax				; SI += edge2_hi * height

	; Compute video offset: DI = edge0_hi * 80 + (x >> 2)
	mov	bx,word ptr ss:[_g_polyRasterState.prs_e0_acc + 2]
	mov	ax,bx
	shl	ax,4h
	mov	di,ax
	shl	ax,2h
	add	di,ax				; DI = bx * 0x50
	mov	ax,cs:[_DAT_169d_0f5e]
	mov	cx,ax
	shr	ax,2h
	add	di,ax				; DI += x >> 2

	; Set VGA sequencer plane mask: AH = 1 << (x & 3)
	mov	ax,0102h			; 0102h VGA seq map-mask: AL=2 idx,AH=1 (out 3c4h)
	and	cl,3h
	shl	ah,cl
	mov	dx,3c4h
	out	dx,ax

	; Compute row span: CX = edge1_hi - edge0_hi
	mov	cx,word ptr ss:[_g_polyRasterState.prs_e1_acc + 2]
	sub	cx,bx
	cmp	cx,1h
	jle	L_unclip_advance	; <= 1 row -> skip pixel draw

	; Colour gradient: lVar10 = (height-1 * 0x100) / span_rows
	;   DX.AX = ((height-1) << 8) / cx  (signed 16-bit idiv)
	;   BP    = MOVZX(AH) -- fractional step (zero-extended)
	;   DH    = AL        -- integer step
	;   DL    = 0x80      -- initial carry accumulator
	mov	dx,0h
	mov	al,0h
	mov	ah,byte ptr cs:[_DAT_169d_0f66]
	dec	ah
	idiv	cx
	movzx	bp,ah			; BP = fractional (remainder high byte)
	mov	dh,al			; DH = integer step
	mov	dl,80h			; DL = 0x80 (carry accumulator seed)
	dec	bp
	sub	di,50h			; pre-adjust video ptr (incremented in loop)

	; Check for colour LUT
	mov	bx,word ptr ss:[_g_polyRasterState.prs_nRemapOff]
	or	bx,bx
	jz	L_unclip_no_lut

	; UNCLIPPED LOOP WITH LUT (XLAT through CS colour table)
L_unclip_lut_loop:
	lodsb				; AL = *SI++  (source pixel)
	add	dl,dh			; accumulate fractional step
	adc	si,bp			; SI += carry + integer step
	add	di,50h			; advance video ptr by 1 row (80 bytes)
	or	al,al
	jz	L_unclip_lut_skip
	xlat	cs:bx			; AL = cs:[BX + AL]  (colour remap)
	mov	byte ptr es:[di],al	; write pixel to video buffer
L_unclip_lut_skip:
	loop	L_unclip_lut_loop
	jmp	short L_unclip_advance

	; UNCLIPPED LOOP WITHOUT LUT (direct pixel write)
L_unclip_no_lut:
	lodsb				; AL = *SI++
	add	dl,dh
	adc	si,bp
	add	di,50h
	or	al,al
	jz	L_unclip_nolut_skip
	mov	byte ptr es:[di],al
L_unclip_nolut_skip:
	loop	L_unclip_no_lut

L_unclip_advance:
	; Step all three edge accumulators
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e0_step]
	add	dword ptr ss:[_g_polyRasterState.prs_e0_acc],eax
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e1_step]
	add	dword ptr ss:[_g_polyRasterState.prs_e1_acc],eax
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e2_step]
	add	dword ptr ss:[_g_polyRasterState.prs_e2_acc],eax

	inc	word ptr cs:[_DAT_169d_0f5e]
	dec	word ptr cs:[_DAT_169d_0f5c]
	jnz	L_loop_unclipped

L_epilogue_ds:
	pop	ds
	pop	di
	pop	si
	pop	bp
	retf

; ===========================================================================
; CLIPPED INNER LOOP (_DAT_169d_0f6e != 0)
; Same as unclipped but with per-column Y-clip testing.
; ===========================================================================
L_loop_clipped:
	mov	si,word ptr cs:[_DAT_169d_0f68]
	mov	ax,word ptr ss:[_g_polyRasterState.prs_e2_acc + 2]
	mov	dx,0h
	imul	word ptr cs:[_DAT_169d_0f66]
	add	si,ax

	mov	bx,word ptr ss:[_g_polyRasterState.prs_e0_acc + 2]
	mov	ax,bx
	shl	ax,4h
	mov	di,ax
	shl	ax,2h
	add	di,ax
	mov	ax,cs:[_DAT_169d_0f5e]
	mov	cx,ax
	shr	ax,2h
	add	di,ax
	mov	ax,0102h			; 0102h VGA seq map-mask: AL=2 idx,AH=1 (out 3c4h)
	and	cl,3h
	shl	ah,cl
	mov	dx,3c4h
	out	dx,ax

	mov	cx,word ptr ss:[_g_polyRasterState.prs_e1_acc + 2]

	; Compute Y-clip lo/hi for this column
	mov	word ptr cs:[_DAT_169d_0f6a],0h
	mov	word ptr cs:[_DAT_169d_0f6c],0h

	mov	ax,word ptr ss:[_g_graphics_context.nClip_ymin]
	sub	ax,bx
	jle	L_no_yclip_lo		; clip_ymin <= edge0 -> no top clip
	mov	cs:[_DAT_169d_0f6a],ax	; _DAT_169d_0f6a = clip_ymin - edge0

L_no_yclip_lo:
	mov	ax,word ptr ss:[_g_polyRasterState.prs_e1_acc + 2]
	dec	ax
	sub	ax,word ptr ss:[_g_graphics_context.nClip_ymax]
	jle	L_no_yclip_hi		; edge1-1 <= clip_ymax -> no bottom clip
	mov	cs:[_DAT_169d_0f6c],ax	; _DAT_169d_0f6c = (edge1-1) - clip_ymax

L_no_yclip_hi:
	sub	cx,bx			; CX = row span (edge1 - edge0)
	cmp	cx,1h
	jle	L_clipped_advance	; <= 1 row -> skip

	; Colour gradient (same as unclipped path)
	mov	dx,0h
	mov	al,0h
	mov	ah,byte ptr cs:[_DAT_169d_0f66]
	dec	ah
	idiv	cx
	movzx	bp,ah
	mov	dh,al
	mov	dl,80h

	; Apply bottom clip to CX
	sub	cx,word ptr cs:[_DAT_169d_0f6c]
	jle	L_clipped_advance

	; Skip top-clipped rows (_DAT_169d_0f6a iterations)
	mov	ax,cs:[_DAT_169d_0f6a]
	or	ax,ax
	jz	L_after_skip		; no top clip -> skip advance loop
	sub	cx,ax
	jle	L_clipped_advance
	xchg	ax,cx			; AX = drawable count, CX = skip count

L_skip_loop:
	add	dl,dh			; advance accumulator without writing
	adc	si,bp
	add	di,50h
	loop	L_skip_loop
	xchg	ax,cx			; restore CX = drawable count

L_after_skip:
	dec	bp
	sub	di,50h			; pre-adjust (loop adds 0x50 on entry)

	; Check for colour LUT
	mov	bx,word ptr ss:[_g_polyRasterState.prs_nRemapOff]
	or	bx,bx
	jz	L_clipped_no_lut

	; CLIPPED LOOP WITH LUT
L_clipped_lut_loop:
	lodsb
	add	dl,dh
	adc	si,bp
	add	di,50h
	or	al,al
	jz	L_clipped_lut_skip
	xlat	cs:bx
	mov	byte ptr es:[di],al
L_clipped_lut_skip:
	loop	L_clipped_lut_loop
	jmp	short L_clipped_advance

	; CLIPPED LOOP WITHOUT LUT
L_clipped_no_lut:
	lodsb
	add	dl,dh
	adc	si,bp
	add	di,50h
	or	al,al
	jz	L_clipped_nolut_skip
	mov	byte ptr es:[di],al
L_clipped_nolut_skip:
	loop	L_clipped_no_lut

L_clipped_advance:
	; Step all three edge accumulators
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e0_step]
	add	dword ptr ss:[_g_polyRasterState.prs_e0_acc],eax
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e1_step]
	add	dword ptr ss:[_g_polyRasterState.prs_e1_acc],eax
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e2_step]
	add	dword ptr ss:[_g_polyRasterState.prs_e2_acc],eax

	inc	word ptr cs:[_DAT_169d_0f5e]
	dec	word ptr cs:[_DAT_169d_0f5c]
	jnz	L_loop_clipped

	pop	ds
	pop	di
	pop	si
	pop	bp
	retf

; ============================================================================
; _polyrast_spr_scaled_blit_planar -- SMC island @ 0x131c, proc @ 0x1324 (977 B)
; ============================================================================
; ---------------------------------------------------------------------------
; CS-resident data island: 8 bytes immediately before the function body
; (at CS:131ch-CS:1323h, between polyrast_gouraud_blit_clipped and this fn).
; These slots are patched at function entry and read by the inner loops.
; ---------------------------------------------------------------------------
_spr_data_ptr	dw	0		; CS:131ch -- sprite data ptr (low word)
_spr_height	dw	0		; CS:131eh -- sprite height for IMUL
		db	4 dup(0)	; CS:1320h-1323h: gap padding

; ---------------------------------------------------------------------------
; void polyrast_spr_scaled_blit_planar(void *sprite, int x, int y,
;                                         uint flags, int w, int h, int colour)
; ---------------------------------------------------------------------------
_polyrast_spr_scaled_blit_planar:
; 169d:1324
	push	bp
	mov	bp,sp
	push	si
	push	di
	push	ds
; 169d:132a
	mov	dx,word ptr [bp + 0eh]		; w
	mov	cx,word ptr [bp + 10h]		; h
; 169d:1330  if w < 0: negate, flip x
	cmp	dx,0
	jge	L_w_ok
	neg	dx
	mov	word ptr [bp + 0eh],dx
	xor	word ptr [bp + 0ch],2
L_w_ok:
; 169d:133e  if h < 0: negate, flip y
	cmp	cx,0
	jge	L_h_ok
	neg	cx
	mov	word ptr [bp + 10h],cx
	xor	word ptr [bp + 0ch],1
L_h_ok:
; 169d:134c  init x-stepper
	mov	si,word ptr [bp + 6]		; sprite near ptr
	mov	di,offset _g_polyRasterState.prs_e0_acc	; = DGROUP+0x290
	mov	ax,word ptr [si + 6]		; sprite width
	dec	ax
	mov	bx,0
	test	word ptr [bp + 0ch],2
	jz	L_x_no_flip
	xchg	ax,bx
L_x_no_flip:
	mov	word ptr [di + 2],bx		; DGROUP+0x292 = x start
	mov	word ptr [di + 6],ax		; DGROUP+0x296 = x end
	dec	dx				; steps = w-1
	push	dx
	push	di				; = DGROUP+0x290
	push	cs
	call	_polyrast_edge_init_step
	add	sp,4
; 169d:1371  init y-stepper
	mov	di,offset _g_polyRasterState.prs_e1_acc	; = DGROUP+0x298
	mov	ax,word ptr [si + 8]		; sprite height
	mov	word ptr cs:[_spr_height],ax	; patch SMC at CS:131eh
	dec	ax
	mov	bx,0
	test	word ptr [bp + 0ch],1
	jz	L_y_no_flip
	xchg	ax,bx
L_y_no_flip:
	mov	word ptr [di + 2],bx		; DGROUP+0x29a = y start
	mov	word ptr [di + 6],ax		; DGROUP+0x29e = y end
	mov	cx,word ptr [bp + 10h]		; h
	dec	cx				; steps = h-1
	push	cx
	push	di				; = DGROUP+0x298
	push	cs
	call	_polyrast_edge_init_step
	add	sp,4
; 169d:139a
	mov	ax,word ptr [si + 4]		; sprite flags byte
	mov	es,word ptr [_g_graphics_context + 18h]	; ES = wGfxBlitDstPage
	mov	ds,word ptr [si]		; DS = sprite data segment
	mov	si,word ptr ss:[si + 2]		; SI = sprite data offset
	mov	word ptr cs:[_spr_data_ptr],si	; patch SMC at CS:131ch
; 169d:13ac  RLE check
	and	ax,80h
	jz	L_no_rle

; RLE decompression into g_pMainScratchBuf
	push	es
	les	di,ss:[_g_pMainScratchBuf]
	xor	ch,ch
	jmp	L_rle_loop_top

L_rle_run:
; 169d:13bb
	mov	cl,al
	and	cl,7fh
	lodsb
	mov	ah,al
	shr	cx,1
	rep	stosw
	jnc	L_rle_loop_top
	stosb
L_rle_loop_top:
; 169d:13ca
	lodsb
	test	al,80h
	jnz	L_rle_run
	or	al,al
	jz	L_rle_done
; 169d:13d3  literal copy
	mov	cl,al
	shr	cx,1
	rep	movsw
	jnc	L_rle_loop_top
	movsb
	jmp	L_rle_loop_top

L_rle_done:
; 169d:13de
	lds	si,ss:[_g_pMainScratchBuf]
	mov	word ptr cs:[_spr_data_ptr],si
	pop	es

L_no_rle:
; 169d:13e9  clipping
	test	word ptr ss:[_g_graphics_context + 3],0fh
	jz	L_after_clip

; x-range checks
	mov	bx,word ptr [bp + 8]		; x
	cmp	bx,word ptr ss:[_g_graphics_context + 6]	; nClip_xmax
	jg	L_return
	add	bx,word ptr [bp + 0eh]		; x + w
	cmp	bx,word ptr ss:[_g_graphics_context + 4]	; nClip_xmin
	jl	L_return
	mov	cx,word ptr ss:[_g_graphics_context + 4]
	sub	cx,word ptr [bp + 8]		; nClip_xmin - x
	jle	L_x_left_done
	mov	ax,word ptr ss:[_g_graphics_context + 4]
	mov	word ptr [bp + 8],ax
	and	cx,0ffffh
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e0_step]	; x-step (DGROUP+0x294)
	cdq
	imul	ecx
	sub	word ptr [bp + 0eh],cx
	add	dword ptr ss:[_g_polyRasterState.prs_e0_acc],eax	; DGROUP+0x290 += EAX
L_x_left_done:
	mov	cx,word ptr [bp + 8]
	add	cx,word ptr [bp + 0eh]
	dec	cx
	sub	cx,word ptr ss:[_g_graphics_context + 6]	; nClip_xmax
	jle	L_x_right_done
	sub	word ptr [bp + 0eh],cx
L_x_right_done:

; y-range checks
	mov	bx,word ptr [bp + 0ah]		; y
	cmp	bx,word ptr ss:[_g_graphics_context + 0ah]	; nClip_ymax
	jg	L_return
	add	bx,word ptr [bp + 10h]		; y + h
	cmp	bx,word ptr ss:[_g_graphics_context + 8]	; nClip_ymin
	jl	L_return
	mov	cx,word ptr ss:[_g_graphics_context + 8]
	sub	cx,word ptr [bp + 0ah]		; nClip_ymin - y
	jle	L_y_top_done
	mov	ax,word ptr ss:[_g_graphics_context + 8]
	mov	word ptr [bp + 0ah],ax
	and	cx,0ffffh
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e1_step]	; y-step (DGROUP+0x29c)
	cdq
	imul	ecx
	sub	word ptr [bp + 10h],cx
	add	dword ptr ss:[_g_polyRasterState.prs_e1_acc],eax	; DGROUP+0x298 += EAX
L_y_top_done:
	mov	cx,word ptr [bp + 0ah]
	add	cx,word ptr [bp + 10h]
	dec	cx
	sub	cx,word ptr ss:[_g_graphics_context + 0ah]	; nClip_ymax
	jle	L_after_clip
	sub	word ptr [bp + 10h],cx

L_after_clip:
; 169d:1496  bounds check
	cmp	word ptr [bp + 0eh],0
	jle	L_return
	cmp	word ptr [bp + 10h],0
	jle	L_return

; compute screen byte offset
	mov	bx,word ptr [bp + 0ah]		; y
	mov	ax,bx
	shl	ax,4
	mov	di,ax
	shl	ax,2
	add	di,ax				; DI = y*0x50
	mov	ax,word ptr [bp + 8]		; x
	mov	cx,ax
	shr	ax,2
	add	di,ax				; DI += x/4
	mov	bx,1
	and	cl,3
	shl	bl,cl				; BL = 1 << (x & 3)

; VGA plane-select register
	mov	al,2
	mov	dx,3c4h
	out	dx,al

; dispatch on flags
	mov	ax,word ptr [bp + 0ch]
	test	ax,4
	jnz	L_fill_mode
	test	ax,8
	jnz	L_outline_setup
	cmp	word ptr ss:[_g_polyRasterState.prs_nRemapOff],0
	jnz	L_remap_setup

; ===========================================================================
; NORMAL BLIT (copy non-transparent pixels)
; ===========================================================================
L_normal_col:
; 169d:14e8
	mov	si,word ptr cs:[_spr_data_ptr]
	mov	ax,word ptr ss:[_g_polyRasterState.prs_e0_acc + 2]	; DGROUP+0x292
	mov	dx,0
	imul	word ptr cs:[_spr_height]
	add	si,ax
	add	si,word ptr ss:[_g_polyRasterState.prs_e1_acc + 2]	; DGROUP+0x29a
	mov	al,bl
	mov	dx,3c5h
	out	dx,al
	push	bx
	push	di
	mov	cx,word ptr [bp + 10h]		; h
	mov	bx,word ptr ss:[_g_polyRasterState.prs_e1_step + 2]	; DGROUP+0x29e
	mov	dx,word ptr ss:[_g_polyRasterState.prs_e1_step]	; DGROUP+0x29c
	mov	dl,byte ptr ss:[_g_polyRasterState.prs_e1_acc + 3]	; DGROUP+0x29b
	dec	bx
	inc	cx
	sub	di,50h
L_normal_row:
; 169d:151f  ADD DI,50h  ← JZ target
	add	di,50h
; 169d:1522
	dec	cx
	jle	L_normal_col_done
L_normal_pixel:
; 169d:1525  LODSB  ← LOOP target
	lodsb
	add	dl,dh
	adc	si,bx
	or	al,al
	jz	L_normal_row
	stosb
	add	di,4fh
	loop	L_normal_pixel

L_normal_col_done:
; 169d:1534
	pop	di
	pop	bx
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e0_step]	; DGROUP+0x294
	add	dword ptr ss:[_g_polyRasterState.prs_e0_acc],eax	; DGROUP+0x290 += step
	shl	bl,1
	test	bl,0fh
	jnz	L_normal_no_wrap
	mov	bl,1
	inc	di
L_normal_no_wrap:
	dec	word ptr [bp + 0eh]
	jnz	L_normal_col

L_return:
; 169d:1550
	pop	ds
	pop	di
	pop	si
	pop	bp
	retf

; ===========================================================================
; FILL MODE (flags & 4): write colour byte for non-transparent pixels
; ===========================================================================
L_fill_mode:
L_fill_col:
; 169d:1555
	mov	si,word ptr cs:[_spr_data_ptr]
	mov	ax,word ptr ss:[_g_polyRasterState.prs_e0_acc + 2]
	mov	dx,0
	imul	word ptr cs:[_spr_height]
	add	si,ax
	add	si,word ptr ss:[_g_polyRasterState.prs_e1_acc + 2]
	mov	al,bl
	mov	dx,3c5h
	out	dx,al
	mov	ah,byte ptr [bp + 12h]		; colour in AH
	push	bx
	push	di
	mov	cx,word ptr [bp + 10h]
	mov	bx,word ptr ss:[_g_polyRasterState.prs_e1_step + 2]
	mov	dx,word ptr ss:[_g_polyRasterState.prs_e1_step]
	mov	dl,byte ptr ss:[_g_polyRasterState.prs_e1_acc + 3]
	dec	bx
	inc	cx
	sub	di,50h
L_fill_row:
; 169d:158f  ADD DI,50h  ← JZ target
	add	di,50h
	dec	cx
	jle	L_fill_col_done
L_fill_pixel:
; 169d:1595  LODSB  ← LOOP target
	lodsb
	add	dl,dh
	adc	si,bx
	or	al,al
	jz	L_fill_row
	mov	byte ptr es:[di],ah		; write colour
	add	di,50h
	loop	L_fill_pixel

L_fill_col_done:
; 169d:15a6
	pop	di
	pop	bx
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e0_step]
	add	dword ptr ss:[_g_polyRasterState.prs_e0_acc],eax
	shl	bl,1
	test	bl,0fh
	jnz	L_fill_no_wrap
	mov	bl,1
	inc	di
L_fill_no_wrap:
	dec	word ptr [bp + 0eh]
	jnz	L_fill_col
; 169d:15c2
	jmp	L_return

; ---------------------------------------------------------------------------
; SMC data at CS:15c4h-CS:15c8h (between fill and outline code)
; Patched as w, h, colour at outline setup.
; ---------------------------------------------------------------------------
_smc_w_ctr	dw	0			; CS:15c4h
_smc_h_ctr	dw	0			; CS:15c6h
_smc_colour	db	0			; CS:15c8h

; ===========================================================================
; OUTLINE MODE setup: entered from JNZ at 169d:14dah
; Patches _smc_w_ctr, _smc_h_ctr, _smc_colour then runs column loop
; ===========================================================================
L_outline_setup:
; 169d:15c9
	mov	ax,word ptr [bp + 0eh]
	mov	word ptr cs:[_smc_w_ctr],ax
	mov	ax,word ptr [bp + 10h]
	mov	word ptr cs:[_smc_h_ctr],ax
	mov	ax,word ptr [bp + 12h]
	mov	byte ptr cs:[_smc_colour],al

L_outline_col:
; 169d:15de
	mov	si,word ptr cs:[_spr_data_ptr]
	mov	ax,word ptr ss:[_g_polyRasterState.prs_e0_acc + 2]
	mov	dx,0
	imul	word ptr cs:[_spr_height]
	add	si,ax
	add	si,word ptr ss:[_g_polyRasterState.prs_e1_acc + 2]
	mov	al,bl
	mov	dx,3c5h
	out	dx,al
	push	bx
	push	di
	mov	cx,word ptr cs:[_smc_h_ctr]
	mov	bx,word ptr ss:[_g_polyRasterState.prs_e1_step + 2]
	mov	dx,word ptr ss:[_g_polyRasterState.prs_e1_step]
	mov	dl,byte ptr ss:[_g_polyRasterState.prs_e1_acc + 3]
	mov	ah,byte ptr cs:[_smc_colour]
	dec	bx
	inc	cx
	sub	di,50h
L_outline_row:
; 169d:161c  ADD DI,50h  ← JZ target
	add	di,50h
	dec	cx
	jle	L_outline_col_done
L_outline_pixel:
; 169d:1622  LODSB  ← LOOP target (back here after writing source pixel)
	lodsb
	add	dl,dh
	adc	si,bx
	or	al,al
	jz	L_outline_row
; write outline colour, then source pixel
	mov	al,ah
	stosb
	add	di,4fh
	dec	cx
	jle	L_outline_col_done
; 169d:1634
	lodsb
	add	dl,dh
	adc	si,bx
	or	al,al
	jz	L_outline_row
	stosb
	add	di,4fh
	loop	L_outline_pixel		; LOOP target = first LODSB (L_outline_pixel)

L_outline_col_done:
; 169d:1643
	pop	di
	pop	bx
	mov	eax,dword ptr ss:[_g_polyRasterState.prs_e0_step]
	add	dword ptr ss:[_g_polyRasterState.prs_e0_acc],eax
	shl	bl,1
	test	bl,0fh
	jnz	L_outline_no_wrap
	mov	bl,1
	inc	di
L_outline_no_wrap:
	dec	word ptr cs:[_smc_w_ctr]
	jnz	L_outline_col
; 169d:1663
	jmp	L_return

; ---------------------------------------------------------------------------
; SMC data at CS:1666h-CS:1669h (between outline and remap code)
; ---------------------------------------------------------------------------
_smc_remap_w	dw	0			; CS:1666h
_smc_remap_h	dw	0			; CS:1668h

; ===========================================================================
; REMAP MODE setup: entered from JNZ at 169d:14e4h
; ===========================================================================
L_remap_setup:
; 169d:166a
	mov	ah,bl				; save plane mask in AH
	mov	bx,word ptr ss:[_g_polyRasterState.prs_nRemapOff]	; remap table offset
	mov	cx,word ptr [bp + 0eh]		; w
	mov	word ptr cs:[_smc_remap_w],cx
	mov	cx,word ptr [bp + 10h]		; h
	mov	word ptr cs:[_smc_remap_h],cx

L_remap_col:
; 169d:1681  MOV CX,AX  ← JNZ target (column loop re-entry includes this)
	mov	cx,ax				; CX = AH:AL (plane in CH)
; 169d:1683
	mov	si,word ptr cs:[_spr_data_ptr]
	mov	ax,word ptr ss:[_g_polyRasterState.prs_e0_acc + 2]
	mov	dx,0
	imul	word ptr cs:[_spr_height]
	add	si,ax
	add	si,word ptr ss:[_g_polyRasterState.prs_e1_acc + 2]
	mov	al,ch				; plane mask from CH
	mov	dx,3c5h
	out	dx,al
	mov	ax,cx
	push	di
	mov	cx,word ptr cs:[_smc_remap_h]
	mov	bp,word ptr ss:[_g_polyRasterState.prs_e1_step + 2]
	mov	dx,word ptr ss:[_g_polyRasterState.prs_e1_step]
	mov	dl,byte ptr ss:[_g_polyRasterState.prs_e1_acc + 3]
	dec	bp
	inc	cx
	sub	di,50h
L_remap_row:
; 169d:16bd  ADD DI,50h  ← JZ target
	add	di,50h
	dec	cx
	jle	L_remap_col_done
L_remap_pixel:
; 169d:16c3  LODSB  ← LOOP target
	lodsb
	add	dl,dh
	adc	si,bp			; Bresenham: BP used instead of BX
	or	al,al
	jz	L_remap_row
	db	02Eh			; CS segment override prefix for XLAT
	xlat				; AL = byte ptr CS:[BX + AL]
	stosb
	add	di,4fh
	loop	L_remap_pixel

L_remap_col_done:
; 169d:16d4
	pop	di
	mov	ecx,dword ptr ss:[_g_polyRasterState.prs_e0_step]	; DGROUP+0x294 via ECX
	add	dword ptr ss:[_g_polyRasterState.prs_e0_acc],ecx
	shl	ah,1
	test	ah,0fh
	jnz	L_remap_no_wrap
	mov	ah,1
	inc	di
L_remap_no_wrap:
	dec	word ptr cs:[_smc_remap_w]
	jnz	L_remap_col
	jmp	L_return

S169D_TEXT	ends
	end
