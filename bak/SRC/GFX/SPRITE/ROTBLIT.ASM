; ============================================================================
; ROTBLIT.ASM -- rotated-sprite blitter module (KRONDOR.EXE segment 180c)
;
; Four procedures in definition order:
;
;   180c:3ef4  stretch_walk_x_clipped      (0x1bfb4) -- span x-walker w/ clip
;   180c:3f62  vga_reset_gc_default_thunk  (0x1c022) -- in-overlay GC-reset trampoline
;   180c:3f6d  jmp_via_2f48                (0x1c02d) -- rotated-blit dispatcher + renderer
;   180c:4834  read_4words_from_2tables    (0x1c8f4) -- 4 out-ptrs <- 2 vertex tables
;
; The module's private DGROUP state family (g_*RotBlit*, the g_apRotBlitStepN
; octant dispatch tables, the rotated-span scratch buffers) names this TU.
;
; Recipe (unit-wide): bc31, -O2 -b- -i64 -k -mm.
;
; The blitter's entry (first 4 bytes, JMPF [g_pRotBlitDispatchFp]) is a far
; indirect tail-call thunk; g_pRotBlitDispatchFp is a static DGROUP pointer
; (initialised in this module's _DATA to 180c:3f71) that lands one instruction past the
; JMPF, on the real body. So a CALLF to the proc entry tail-jumps straight
; into its own body -- a no-cost indirection the original kept so the dispatch
; target could in principle be swapped at runtime.
;
; WHY ASM: JMPF [mem] bare tail-call dispatch; JCXZ / LOOP
; (seg-180c codegen wall, no BC 3.1 flag emits these); LODSW / REP STOSW string
; ops; JMP word ptr [g_pRotBlit*Fp] near-slot dispatch; CALLF [vtable] indirect
; far call; the NOP/PUSH CS/CALL NEAR intra-segment near-call-to-far idiom; and
; the trampoline's non-standard epilogue. None of these are expressible in C.
;
; INTRA-UNIT near calls/jumps (resolved within this object):
;   - jmp_via_2f48 CALLs stretch_walk_x_clipped (backward, same TU) -- near.
;   - jmp_via_2f48 JZ/JMPs into vga_reset_gc_default_thunk (backward) -- near.
; Calls that STAY external (the callee lives in a DIFFERENT seg-180c TU):
;   - stretch_step_init (0x19731), vga_reset_gc_default (0x18b02): reached via
;     the PUSH CS + CALL NEAR overlay idiom; declared extrn ...:near.
;
; OCTANT STEP LABELS: jmp_via_2f48 dispatches each scanline through one of four
; near fn-ptr slots (g_pRotBlitStep{1..4}Fp), loaded from the four
; g_apRotBlitStepNFpTable[4] arrays in this module's own _DATA, which take the address of the
; 16 case-body labels (rotblit_stepN_octM); they are PUBLIC here so the whole-EXE
; relink resolves &rotblit_stepN_octM. Borland C emits a single leading
; underscore, so the public symbols are _rotblit_stepN_octM. The labels alias the
; existing internal case-body labels and emit no bytes.
;
; LITERAL DGROUP OFFSETS in jmp_via_2f48:
;   0x5976 g_aStretchYSrcTable base   0x5476 g_aStretchXSrcTable base
;   0x2702 g_graphics_context.pRow_offset_lut   0x2b56 renderer_vtable blit slot
;   0x202d bVideoAdapter  0x2028 wGfxBlitDstPage  0x2018/0x201a nClip_ymin/ymax
;   0x2014/0x2016 nClip_xmin/xmax
; ============================================================================

; ----------------------------------------------------------------------------
; What this module is (plain-English overview)
;
; This is the engine's "rotated-sprite blitter": given a source image, a
; rotation angle and an X/Y scale, it draws the image rotated and stretched
; onto the screen. The main proc has a 0x6ca-byte stack frame holding several
; scanline scratch buffers, a far indirect tail-call entry, and four
; computed-jump dispatches into 16 inline case bodies.
;
; The work splits across four procedures (definition order):
;
;   stretch_walk_x_clipped     private helper: walks a Bresenham-style
;                              fixed-point X accumulator across one span,
;                              clipping each emitted X. Called near, only by
;                              the blitter.
;   vga_reset_gc_default_thunk private early-out target: a degenerate input
;                              (zero scale, or a degenerate quad) jumps here
;                              to reset the VGA Graphics Controller and bail.
;                              It deliberately *borrows the blitter's stack
;                              frame* (see its plate).
;   jmp_via_2f48               THE blitter. Computes the four rotated corner
;                              vertices, picks a rotation "octant", and walks
;                              the rotated quad scanline by scanline, calling
;                              the active renderer's horizontal-blit slot for
;                              each clipped span. Also drives the VGA hardware
;                              directly (see the hardware primer below).
;   read_4words_from_2tables   geometry read-back accessor: copies the four
;                              corner vertices the blitter last produced out
;                              to four caller-supplied pointers.
;
; PRODUCER / CONSUMER: the blitter is the *producer* of the rotated-quad
; geometry (g_anRotBlitVert{X,Y}, the g_wRotBlitIdx* corner indices); it
; writes that state into the module's private DGROUP block. read_4words_-
; from_2tables is the *consumer* read-back path and is NOT called by the
; blitter -- its sole caller lives in a different segment (seg 52d6,
; ttmscript_interpret_loop in TTM.C). Producer and consumer communicate only through the shared
; private g_*RotBlit* DGROUP block, which is touched by NO other module in
; the whole binary.
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; Hardware primer: the VGA Graphics Controller / Sequencer (planar EGA/VGA)
;
; On a planar EGA/VGA adapter, screen memory is split into four bit-planes
; that share the same CPU addresses; small register files inside the chip
; decide how a CPU byte write fans out to those planes. This module pokes two
; of those register files directly to put the chip into the "write mode" the
; renderer's blit slot expects, then resets it on the way out.
;
; Each register file is reached through an INDEX/DATA port pair. You select a
; sub-register by writing its number to the index port, then write the value
; to the data port; on a 16-bit OUT (OUT DX,AX) the chip accepts the index in
; AL and the data in AH in one instruction.
;
;   port 0x3CE  Graphics Controller index    0x3CF  GC data
;   port 0x3C4  Sequencer index              0x3C5  Sequencer data
;
; The GC reset sequence this module emits (at L_0621, guarded so it only runs
; on planar adapters -- bVideoAdapter 2 / 0x0C / 0x0D) is:
;
;   OUT 0x3CE, AX with AX=0x0001  -> GC reg 1 (Enable Set/Reset) = 0
;   OUT 0x3CE, AX with AX=0x0005  -> GC reg 5 (Graphics Mode)    = 0
;   OUT 0x3CE, AL with AL=0x08    -> select GC reg 8 (Bit Mask), data left
;                                    for the renderer slot to fill in
;
; i.e. it returns Set/Reset and write-mode to their defaults and arms the Bit
; Mask register index. On exit the blitter calls vga_reset_gc_default (in a
; sibling TU) to fully restore the chip. For the register reference see
; FreeVGA (osdever.net/FreeVGA) -- "Graphics Registers" and "Sequencer
; Registers".
; ----------------------------------------------------------------------------

	.286
	nosmart

	include	gfxctx.inc		; _g_graphics_context.nClip_xmax / .wScreen_width -> _g_graphics_context+offset

; --- far externals ----------------------------------------------------------
	extrn	_r3d_tbl_cos:far
	extrn	_r3d_tbl_sin:far

; --- DGROUP data externals --------------------------------------------------
; The module's private g_*RotBlit* block (DG 0x2f48..0x2f8c) is emitted from
; this obj's OWN _DATA below. The shared stretch scratch tables live in this
; obj's OWN _BSS below; TASM allocates _BSS in file order, giving the
; XSrc-below-YSrc order -- do not reorder them. Out-of-block DGROUP data stays
; extrn.
	extrn	_g_renderer_vtable:word		; DGROUP+0x2ac6 (200B) RendererVtable
	extrn	_g_graphics_context:byte	; DGROUP+0x2010 (2742B) GraphicsContext
; GfxContext field names (nClip_*, wGfxBlitDstPage, bVideoAdapter) and the render-tail
; pRow_offset_lut (GfxContextRender) + the standalone _g_wScreen_width come from gfxctx.inc.

; --- far callees in other seg-180c TUs: FAR calls; TLINK's backward far->near
; collapse emits the 90 0e e8 bytes at each call site ------------------------
	extrn	_stretch_step_init:far
	extrn	_vga_reset_gc_default:far

; --- DGROUP / segment declarations ------------------------------------------
	_DATA	segment word public 'DATA'

	public	_g_pRotBlitDispatchFp
	public	_g_anRotBlitVertX, _g_anRotBlitVertY
	public	_g_wRotBlitIdxTop, _g_wRotBlitIdxBottom, _g_wRotBlitIdxNextCW, _g_wRotBlitIdxOppCW
	public	_g_pRotBlitStep1Fp, _g_apRotBlitStep1FpTable
	public	_g_pRotBlitStep2Fp, _g_apRotBlitStep2FpTable
	public	_g_pRotBlitStep3Fp, _g_apRotBlitStep3FpTable
	public	_g_pRotBlitStep4Fp, _g_apRotBlitStep4FpTable

	; DG+0x2f48 (4B) void*32: init image [71 3f 0c 18] = far ptr 180c:3f71 (rotblit body
	; = jmp_via_2f48+4, the JMPF [0x2f48] thunk target = rotblit_dispatch_body below).
_g_pRotBlitDispatchFp	dd	rotblit_dispatch_body	; DGROUP+0x2f48 (4B) void *32 -> 180c:3f71
_g_anRotBlitVertX	dw	0,0,0,0	; DGROUP+0x2f4c (8B) short[4]
_g_anRotBlitVertY	dw	0,0,0,0	; DGROUP+0x2f54 (8B) short[4]
_g_wRotBlitIdxTop	dw	0	; DGROUP+0x2f5c (2B) ushort
_g_wRotBlitIdxBottom	dw	0	; DGROUP+0x2f5e (2B) ushort
_g_wRotBlitIdxNextCW	dw	0	; DGROUP+0x2f60 (2B) ushort
_g_wRotBlitIdxOppCW	dw	0	; DGROUP+0x2f62 (2B) ushort
_g_pRotBlitStep1Fp	dw	0	; DGROUP+0x2f64 (2B) void *16 (relocated ptr, {0})
_g_apRotBlitStep1FpTable	dw	offset _rotblit_step1_oct0, offset _rotblit_step1_oct1, offset _rotblit_step1_oct2, offset _rotblit_step1_oct3	; DGROUP+0x2f66 (8B) void *16[4]
_g_pRotBlitStep2Fp	dw	0	; DGROUP+0x2f6e (2B) void *16 (relocated ptr, {0})
_g_apRotBlitStep2FpTable	dw	offset _rotblit_step2_oct0, offset _rotblit_step2_oct1, offset _rotblit_step2_oct2, offset _rotblit_step2_oct3	; DGROUP+0x2f70 (8B) void *16[4]
_g_pRotBlitStep3Fp	dw	0	; DGROUP+0x2f78 (2B) void *16 (relocated ptr, {0})
_g_apRotBlitStep3FpTable	dw	offset _rotblit_step3_oct0, offset _rotblit_step3_oct1, offset _rotblit_step3_oct2, offset _rotblit_step3_oct3	; DGROUP+0x2f7a (8B) void *16[4]
_g_pRotBlitStep4Fp	dw	0	; DGROUP+0x2f82 (2B) void *16 (relocated ptr, {0})
_g_apRotBlitStep4FpTable	dw	offset _rotblit_step4_oct0, offset _rotblit_step4_oct1, offset _rotblit_step4_oct2, offset _rotblit_step4_oct3	; DGROUP+0x2f84 (8B) void *16[4]
	_DATA	ends
	_BSS	segment word public 'BSS'
	public	_g_aStretchXSrcTable, _g_aStretchYSrcTable
_g_aStretchXSrcTable	dw	640 dup(?)	; DGROUP+0x5476 (1280B) short[640]
_g_aStretchYSrcTable	dw	400 dup(?)	; DGROUP+0x5976 (800B) short[400]
	_BSS	ends
	DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_stretch_walk_x_clipped
	public	_vga_reset_gc_default_thunk
	public	_jmp_via_2f48
	public	_read_4words_from_2tables

	; octant case-body label aliases (referenced by the step tables in _DATA below)
	public	_rotblit_step1_oct0, _rotblit_step1_oct1, _rotblit_step1_oct2, _rotblit_step1_oct3
	public	_rotblit_step2_oct0, _rotblit_step2_oct1, _rotblit_step2_oct2, _rotblit_step2_oct3
	public	_rotblit_step3_oct0, _rotblit_step3_oct1, _rotblit_step3_oct2, _rotblit_step3_oct3
	public	_rotblit_step4_oct0, _rotblit_step4_oct1, _rotblit_step4_oct2, _rotblit_step4_oct3

; ============================================================================
; stretch_walk_x_clipped (180c:3ef4, 0x1bfb4)
;
; Walks a Bresenham-style fixed-point x accumulator for `span-(count-1)` steps,
; clipping each emitted x to [0, g_clip_xmax) against wScreen_width on the
; source side. Writes successive x coordinates into out_xs.
;
; void stretch_walk_x_clipped(int *out_xs, int x_start, int count, int x_step, int span)
;   __cdecl16near; BP+4 out_xs, BP+6 x_start, BP+8 count, BP+0A x_step, BP+0C span
; ============================================================================
_stretch_walk_x_clipped	proc near
	push	bp
	mov	bp,sp
	sub	sp,0ah
	push	si
	mov	ax,word ptr [bp+8]		; count
	dec	ax
	sub	word ptr [bp+0ch],ax		; span -= (count-1) -> dest_steps in place
	lea	bx,[bp-0ah]			; BX -> step record
	mov	ax,word ptr [bp+6]		; x_start
	mov	word ptr [bx+2],ax		; step[1] = x_start
	mov	ax,word ptr [bp+0ah]		; x_step
	mov	word ptr [bx+6],ax		; step[3] = x_step
	push	word ptr [bp+0ch]		; dest_steps
	push	bx				; &step record
	call	_stretch_step_init		; 90 0e e8 after TLINK's backward far->near collapse
	add	sp,4
	mov	cx,word ptr [bp+0ch]		; dest_steps
	jcxz	L_swxc_exit			; if dest_steps == 0 -> exit
	mov	si,word ptr [bp+8]		; SI = count (x coordinate index)
L_swxc_loop_top:
	lea	bx,[bp-0ah]			; BX -> step record
	mov	ax,word ptr [bx+2]		; x_pos (src_cur)
	mov	word ptr [bp-2],ax		; save to local_a
	mov	ax,word ptr [bx+4]		; step increment lo
	mov	dx,word ptr [bx+6]		; step increment hi
	add	word ptr [bx],ax		; accum_lo += step_lo
	adc	word ptr [bx+2],dx		; accum_hi += step_hi + carry (updates x_pos)
	or	si,si
	jl	L_swxc_skip_write		; if x < 0: skip write
	cmp	si,word ptr [_g_wScreen_width]	; compare x with wScreen_width
	jge	L_swxc_skip_write		; if x >= wScreen_width: skip write
	mov	ax,word ptr [bp-2]		; local_a (clipped x value)
	cmp	ax,word ptr [_g_graphics_context.nClip_xmax]	; compare with nClip_xmax
	jle	L_swxc_no_clip			; if <= nClip_xmax: no clipping needed
	mov	ax,word ptr [_g_graphics_context.nClip_xmax]	; clip: AX = nClip_xmax
L_swxc_no_clip:
	mov	bx,word ptr [bp+4]		; out_xs pointer
	mov	word ptr [bx],ax		; *out_xs = ax
	add	bx,2				; out_xs++
	mov	word ptr [bp+4],bx		; store updated pointer
L_swxc_skip_write:
	inc	si				; x++
	loop	L_swxc_loop_top			; --CX; if CX!=0 goto L_swxc_loop_top
L_swxc_exit:
	pop	si
	mov	sp,bp
	pop	bp
	ret
_stretch_walk_x_clipped	endp

; ============================================================================
; vga_reset_gc_default_thunk (180c:3f62, 0x1c022)
;
; Overlay-local trampoline to vga_reset_gc_default. The PUSH CS + CALL near
; idiom puts the overlay segment on the stack as far-return CS; the callee's
; RETF pops IP then CS, landing back at the POP SI cleanup here. The epilogue
; (MOV SP,BP / POP BP, no matching PUSH BP) is borrowed from the FAR caller.
; ============================================================================
_vga_reset_gc_default_thunk	proc far
	call	_vga_reset_gc_default		; 90 0e e8 after TLINK's backward far->near collapse
	pop	si
	pop	di
	mov	sp,bp
	pop	bp
	retf
_vga_reset_gc_default_thunk	endp

; ============================================================================
; jmp_via_2f48 / sprite_blit_rotozoom (180c:3f6d, 0x1c02d)  --  THE blitter
;
; Draws a source image rotated by `angle` and scaled by (scale_x, scale_y)
; into the current blit destination, clipped to the graphics-context clip
; rectangle. The 0x6ca-byte stack frame holds the per-scanline scratch:
; column-start tables for the upper and lower halves of the rotated quad
; ([bp+0xfafc..], [bp+0xfd7c..]), a row-offset working buffer ([bp+0xf960..]),
; and a handful of fixed-point locals (named by their large positive BP
; displacements, which are negative frame offsets in two's complement).
;
;   Producer of: g_anRotBlitVert{X,Y}[4] (the four rotated corner vertices)
;                and g_wRotBlitIdx{Top,Bottom,NextCW,OppCW} (which array slot
;                is the top / bottom / clockwise-neighbour corner). These are
;                read back later via read_4words_from_2tables.
;
;   Inputs (stack args, far __cdecl):
;     [bp+6]  src image descriptor ptr (fields at +6,+8 = h-1,w-1 source dims)
;     [bp+8]  dst origin X (fixed-point, copied to local at [bp-4])
;     [bp+0a] dst origin Y (fixed-point, copied to local at [bp-2])
;     [bp+0c] rotation angle, a 16-bit binary angle: 0x10000 == 360 deg, so
;             0x4000 == 90 deg, 0x8000 == 180 deg (the two angle compares
;             below test those quadrant boundaries)
;     [bp+0e] scale numerator X        [bp+10] scale numerator Y
;     [bp+12] / [bp+14] enable flags for the X / Y shear terms
;
;   Trig: cos/sin of the angle come from the far tables r3d_tbl_cos /
;   r3d_tbl_sin (return a signed 1.14-ish fixed-point short); the IMUL +
;   double-SHL/RCL idiom multiplies a coordinate by the trig value and keeps
;   the high word (a fixed-point multiply with a 2-bit upshift).
;
;   Octant dispatch: after deriving the four corners, the code picks a
;   rotation octant in [0..3] and JMPs through one of four near function-ptr
;   slots g_pRotBlitStep{1..4}Fp. Each slot was loaded (at L_0197 below) from
;   g_apRotBlitStep{1..4}FpTable[octant] -- arrays of &rotblit_stepN_octM that
;   live in this module's _DATA and point back at the 16 inline case bodies in this proc.
;   The octant index is ((8 - idxTop) & 6) >> 1; see the comment at L_0197.
;
;   Per-span output goes through the active renderer's horizontal-blit slot,
;   an indirect far call CALLF [g_renderer_vtable+0x90].
;
;   Early-out: a zero scale or a degenerate (zero-area) quad JMP/JZs to
;   vga_reset_gc_default_thunk, which shares THIS frame and returns for us.
;
; Entry (first 4 bytes) is JMPF [g_pRotBlitDispatchFp] -- a far indirect
; tail-call thunk into the body at 180c:3f71 (g_pRotBlitDispatchFp is a static
; static pointer in this module's _DATA initialised to that address; see the module header).
; ============================================================================
_jmp_via_2f48	proc far

	jmp	dword ptr [_g_pRotBlitDispatchFp]	; 180c:3f6d  JMPF [0x2f48] -> body at 3f71
rotblit_dispatch_body:				; 180c:3f71  the pointer's initial target
	push	bp	; 180c:3f71  PUSH BP
	mov	bp,sp	; 180c:3f72  MOV BP,SP
	sub	sp,6cah	; 180c:3f74  SUB SP,0x6ca
	push	di	; 180c:3f78  PUSH DI
	push	si	; 180c:3f79  PUSH SI
	mov	ax,word ptr [bp + 0eh]	; 180c:3f7a  MOV AX,word ptr [BP + 0xe]
	or	ax,ax	; 180c:3f7d  OR AX,AX
	jz	_vga_reset_gc_default_thunk	; 180c:3f7f  JZ 0x1000:c022
	jns	L_0019	; 180c:3f81  JNS 0x1000:c046
	neg	word ptr [bp + 0eh]	; 180c:3f83  NEG word ptr [BP + 0xe]
L_0019:
	mov	ax,word ptr [bp + 10h]	; 180c:3f86  MOV AX,word ptr [BP + 0x10]
	or	ax,ax	; 180c:3f89  OR AX,AX
	jz	_vga_reset_gc_default_thunk	; 180c:3f8b  JZ 0x1000:c022
	jns	L_0025	; 180c:3f8d  JNS 0x1000:c052
	neg	word ptr [bp + 10h]	; 180c:3f8f  NEG word ptr [BP + 0x10]
L_0025:
	; Look up cos(angle) and sin(angle). Both far tables take the same
	; pushed angle arg; cos is cached in local [bp+0xf95a], sin in
	; [bp+0xf95c]. ADD SP,2 below pops the single shared arg afterwards.
	push	word ptr [bp + 0ch]	; 180c:3f92  PUSH angle
	call	far ptr _r3d_tbl_cos	; 180c:3f95  CALLF 0x2000:6259
	mov	word ptr [bp + 0f95ah],ax	; 180c:3f9a  cos_fx = AX
	call	far ptr _r3d_tbl_sin	; 180c:3f9e  CALLF 0x2000:6234
	mov	word ptr [bp + 0f95ch],ax	; 180c:3fa3  sin_fx = AX
	add	sp,2h	; 180c:3fa7  pop the shared angle arg
	mov	ax,ds	; 180c:3faa  MOV AX,DS
	mov	es,ax	; 180c:3fac  MOV ES,AX
	mov	ax,word ptr [bp + 8h]	; 180c:3fae  MOV AX,word ptr [BP + 0x8]
	mov	word ptr [bp + -4h],ax	; 180c:3fb1  MOV word ptr [BP + -0x4],AX
	mov	ax,word ptr [bp + 0ah]	; 180c:3fb4  MOV AX,word ptr [BP + 0xa]
	mov	word ptr [bp + -2h],ax	; 180c:3fb7  MOV word ptr [BP + -0x2],AX
	mov	ax,word ptr [bp + 14h]	; 180c:3fba  MOV AX,word ptr [BP + 0x14]
	or	ax,ax	; 180c:3fbd  OR AX,AX
	jz	L_007f	; 180c:3fbf  JZ 0x1000:c0ac
	mov	bx,word ptr [bp + 6h]	; 180c:3fc1  MOV BX,word ptr [BP + 0x6]
	imul	word ptr [bp + 10h]	; 180c:3fc4  IMUL word ptr [BP + 0x10]
	idiv	word ptr [bx + 8h]	; 180c:3fc7  IDIV word ptr [BX + 0x8]
	mov	bx,ax	; 180c:3fca  MOV BX,AX
	imul	word ptr [bp + 0f95ah]	; 180c:3fcc  IMUL word ptr [BP + 0xf95a]
	shl	ax,1h	; 180c:3fd0  SHL AX,0x1
	rcl	dx,1h	; 180c:3fd2  RCL DX,0x1
	shl	ax,1h	; 180c:3fd4  SHL AX,0x1
	rcl	dx,1h	; 180c:3fd6  RCL DX,0x1
	sub	word ptr [bp + -2h],dx	; 180c:3fd8  SUB word ptr [BP + -0x2],DX
	mov	ax,bx	; 180c:3fdb  MOV AX,BX
	imul	word ptr [bp + 0f95ch]	; 180c:3fdd  IMUL word ptr [BP + 0xf95c]
	shl	ax,1h	; 180c:3fe1  SHL AX,0x1
	rcl	dx,1h	; 180c:3fe3  RCL DX,0x1
	shl	ax,1h	; 180c:3fe5  SHL AX,0x1
	rcl	dx,1h	; 180c:3fe7  RCL DX,0x1
	add	word ptr [bp + -4h],dx	; 180c:3fe9  ADD word ptr [BP + -0x4],DX
L_007f:
	mov	ax,word ptr [bp + 12h]	; 180c:3fec  MOV AX,word ptr [BP + 0x12]
	or	ax,ax	; 180c:3fef  OR AX,AX
	jz	L_00b1	; 180c:3ff1  JZ 0x1000:c0de
	mov	bx,word ptr [bp + 6h]	; 180c:3ff3  MOV BX,word ptr [BP + 0x6]
	imul	word ptr [bp + 0eh]	; 180c:3ff6  IMUL word ptr [BP + 0xe]
	idiv	word ptr [bx + 6h]	; 180c:3ff9  IDIV word ptr [BX + 0x6]
	mov	bx,ax	; 180c:3ffc  MOV BX,AX
	imul	word ptr [bp + 0f95ah]	; 180c:3ffe  IMUL word ptr [BP + 0xf95a]
	shl	ax,1h	; 180c:4002  SHL AX,0x1
	rcl	dx,1h	; 180c:4004  RCL DX,0x1
	shl	ax,1h	; 180c:4006  SHL AX,0x1
	rcl	dx,1h	; 180c:4008  RCL DX,0x1
	sub	word ptr [bp + -4h],dx	; 180c:400a  SUB word ptr [BP + -0x4],DX
	mov	ax,bx	; 180c:400d  MOV AX,BX
	imul	word ptr [bp + 0f95ch]	; 180c:400f  IMUL word ptr [BP + 0xf95c]
	shl	ax,1h	; 180c:4013  SHL AX,0x1
	rcl	dx,1h	; 180c:4015  RCL DX,0x1
	shl	ax,1h	; 180c:4017  SHL AX,0x1
	rcl	dx,1h	; 180c:4019  RCL DX,0x1
	sub	word ptr [bp + -2h],dx	; 180c:401b  SUB word ptr [BP + -0x2],DX
L_00b1:
	mov	bx,word ptr [bp + 10h]	; 180c:401e  MOV BX,word ptr [BP + 0x10]
	mov	ax,bx	; 180c:4021  MOV AX,BX
	imul	word ptr [bp + 0f95ah]	; 180c:4023  IMUL word ptr [BP + 0xf95a]
	shl	ax,1h	; 180c:4027  SHL AX,0x1
	rcl	dx,1h	; 180c:4029  RCL DX,0x1
	shl	ax,1h	; 180c:402b  SHL AX,0x1
	rcl	dx,1h	; 180c:402d  RCL DX,0x1
	mov	word ptr [bp + 0faf6h],dx	; 180c:402f  MOV word ptr [BP + 0xfaf6],DX
	mov	ax,bx	; 180c:4033  MOV AX,BX
	imul	word ptr [bp + 0f95ch]	; 180c:4035  IMUL word ptr [BP + 0xf95c]
	shl	ax,1h	; 180c:4039  SHL AX,0x1
	rcl	dx,1h	; 180c:403b  RCL DX,0x1
	shl	ax,1h	; 180c:403d  SHL AX,0x1
	rcl	dx,1h	; 180c:403f  RCL DX,0x1
	mov	word ptr [bp + 0faf4h],dx	; 180c:4041  MOV word ptr [BP + 0xfaf4],DX
	mov	bx,word ptr [bp + 0eh]	; 180c:4045  MOV BX,word ptr [BP + 0xe]
	mov	ax,bx	; 180c:4048  MOV AX,BX
	imul	word ptr [bp + 0f95ah]	; 180c:404a  IMUL word ptr [BP + 0xf95a]
	shl	ax,1h	; 180c:404e  SHL AX,0x1
	rcl	dx,1h	; 180c:4050  RCL DX,0x1
	shl	ax,1h	; 180c:4052  SHL AX,0x1
	rcl	dx,1h	; 180c:4054  RCL DX,0x1
	mov	word ptr [bp + 0fafah],dx	; 180c:4056  MOV word ptr [BP + 0xfafa],DX
	mov	ax,bx	; 180c:405a  MOV AX,BX
	imul	word ptr [bp + 0f95ch]	; 180c:405c  IMUL word ptr [BP + 0xf95c]
	shl	ax,1h	; 180c:4060  SHL AX,0x1
	rcl	dx,1h	; 180c:4062  RCL DX,0x1
	shl	ax,1h	; 180c:4064  SHL AX,0x1
	rcl	dx,1h	; 180c:4066  RCL DX,0x1
	mov	word ptr [bp + 0faf8h],dx	; 180c:4068  MOV word ptr [BP + 0xfaf8],DX
	; Emit the four rotated corner X coordinates into g_anRotBlitVertX[0..3]
	; by walking the rotated edge vectors out from the origin corner (in
	; [bp-4]) and back: +dx_along, +dx_down, -dx_along. (Y corners follow.)
	mov	di,offset DGROUP:_g_anRotBlitVertX	; 180c:406c  DI -> g_anRotBlitVertX
	mov	ax,word ptr [bp + -4h]	; 180c:406f  AX = origin X
	mov	cx,word ptr [bp + 0fafah]	; 180c:4072  CX = X edge delta
	stosw	; 180c:4076  corner 0
	add	ax,cx	; 180c:4077
	stosw	; 180c:4079  corner 1
	sub	ax,word ptr [bp + 0faf4h]	; 180c:407a
	stosw	; 180c:407e  corner 2
	sub	ax,cx	; 180c:407f
	stosw	; 180c:4081  corner 3
	mov	di,offset DGROUP:_g_anRotBlitVertY	; 180c:4082  DI -> g_anRotBlitVertY
	mov	ax,word ptr [bp + -2h]	; 180c:4085  MOV AX,word ptr [BP + -0x2]
	mov	cx,word ptr [bp + 0faf8h]	; 180c:4088  MOV CX,word ptr [BP + 0xfaf8]
	stosw	; 180c:408c  STOSW ES:DI
	add	ax,cx	; 180c:408d  ADD AX,CX
	stosw	; 180c:408f  STOSW ES:DI
	add	ax,word ptr [bp + 0faf6h]	; 180c:4090  ADD AX,word ptr [BP + 0xfaf6]
	stosw	; 180c:4094  STOSW ES:DI
	sub	ax,cx	; 180c:4095  SUB AX,CX
	stosw	; 180c:4097  STOSW ES:DI
	mov	bx,word ptr [bp + 6h]	; 180c:4098  MOV BX,word ptr [BP + 0x6]
	mov	dx,word ptr [bx + 6h]	; 180c:409b  MOV DX,word ptr [BX + 0x6]
	lea	di,[bp + 0f960h]	; 180c:409e  LEA DI,[BP + 0xf960]
	xor	ax,ax	; 180c:40a2  XOR AX,AX
	mov	cx,0c8h	; 180c:40a4  MOV CX,0xc8
L_013a:
	stosw	; 180c:40a7  STOSW ES:DI
	add	ax,dx	; 180c:40a8  ADD AX,DX
	loop	L_013a	; 180c:40aa  LOOP 0x1000:c167
	lea	di,[bp + 0f960h]	; 180c:40ac  LEA DI,[BP + 0xf960]
	mov	ax,word ptr [bx + 8h]	; 180c:40b0  MOV AX,word ptr [BX + 0x8]
	shl	ax,1h	; 180c:40b3  SHL AX,0x1
	add	di,ax	; 180c:40b5  ADD DI,AX
	mov	ax,word ptr [di]	; 180c:40b7  MOV AX,word ptr [DI]
	mov	word ptr [bp + 0faf0h],ax	; 180c:40b9  MOV word ptr [BP + 0xfaf0],AX
	mov	si,offset DGROUP:_g_anRotBlitVertY	; 180c:40bd  MOV SI,0x2f54
	mov	bx,7d00h	; 180c:40c0  MOV BX,0x7d00
	mov	cx,4h	; 180c:40c3  MOV CX,0x4
L_0159:
	lodsw	; 180c:40c6  LODSW SI
	cmp	ax,bx	; 180c:40c7  CMP AX,BX
	jge	L_0162	; 180c:40c9  JGE 0x1000:c18f
	mov	bx,ax	; 180c:40cb  MOV BX,AX
	mov	dx,cx	; 180c:40cd  MOV DX,CX
L_0162:
	loop	L_0159	; 180c:40cf  LOOP 0x1000:c186
	; The loop above (L_0159) found the corner with the smallest Y; turn its
	; slot index (4-cx) into the even slot number (*2) and store as idxTop.
	sub	dx,4h	; 180c:40d1  DX = -(loop index - 4)
	neg	dx	; 180c:40d4
	shl	dx,1h	; 180c:40d6  -> even slot number 0/2/4/6
	mov	word ptr [_g_wRotBlitIdxTop],dx	; 180c:40d8  idxTop = top corner slot
	; Angle tie-breaks when two corners share the topmost Y (exact 90/180-deg
	; rotations): nudge idxTop to the clockwise neighbour so the scanline walk
	; below picks the correct starting edge. 0x4000 = 90 deg, 0x8000 = 180 deg
	; in the 16-bit binary-angle space (0x10000 == full circle).
	or	dx,dx	; 180c:40dc  idxTop == 0 (corner 0 on top)?
	jnz	L_0180	; 180c:40de
	cmp	word ptr [bp + 0ch],4000h	; 4000h angle cmp 90deg (param feeds cos/sin; paired 0x8000)
	jc	L_0180	; 180c:40e5  angle < 90 deg -> leave idxTop = 0
	mov	word ptr [_g_wRotBlitIdxTop],6h	; 180c:40e7  else start at corner 6
L_0180:
	cmp	word ptr [bp + 0ch],8000h	; 180c:40ed  angle < 180 deg?
	jnc	L_0197	; 180c:40f2  no -> skip the second tie-break
	mov	bx,offset DGROUP:_g_anRotBlitVertY	; 180c:40f4  MOV BX,0x2f54
	mov	ax,word ptr [bx + 4h]	; 180c:40f7  MOV AX,word ptr [BX + 0x4]
	cmp	ax,word ptr [bx + 6h]	; 180c:40fa  CMP AX,word ptr [BX + 0x6]
	jnz	L_0197	; 180c:40fd  JNZ 0x1000:c1c4
	add	word ptr [_g_wRotBlitIdxTop],2h	; 180c:40ff  ADD word ptr [0x2f5c],0x2
L_0197:
	; The four corners are slots 0,2,4,6 of g_anRotBlitVert{X,Y}. Starting
	; from the top corner (idxTop), walk clockwise by repeatedly adding 2 and
	; masking with 6 (modulo-8 step on even slots): NextCW, then Bottom (the
	; diagonally opposite corner), then OppCW.
	mov	ax,[_g_wRotBlitIdxTop]	; 180c:4104  AX = idxTop
	mov	bx,6h	; 180c:4107  BX = wrap mask 6
	inc	ax	; 180c:410a  +2  (idxTop + 2, mod 8)
	inc	ax	; 180c:410b
	and	ax,bx	; 180c:410c
	mov	[_g_wRotBlitIdxNextCW],ax	; 180c:410e  next clockwise corner
	inc	ax	; 180c:4111  +2  (the opposite corner)
	inc	ax	; 180c:4112
	and	ax,bx	; 180c:4113
	mov	[_g_wRotBlitIdxBottom],ax	; 180c:4115  bottom corner
	inc	ax	; 180c:4118  +2  (the remaining corner)
	inc	ax	; 180c:4119
	and	ax,bx	; 180c:411a
	mov	[_g_wRotBlitIdxOppCW],ax	; 180c:411c  opposite-clockwise corner
	; Derive the rotation octant in [0..3]:  octant = ((8 - idxTop) & 6) >> 1.
	; idxTop is the corner-array slot (0,2,4,6) of the topmost vertex; (8-it)&6
	; folds it back into 0..6, and >>1 turns that into the 0..3 octant index.
	; Stored as a byte at [bp+0xf94c]; bit 0 of it is reused later (L_02a0) as
	; a "swap X/Y axes" flag for the steep-vs-shallow octants.
	mov	ax,8h	; 180c:411f  MOV AX,0x8
	sub	ax,word ptr [_g_wRotBlitIdxTop]	; 180c:4122  8 - idxTop
	and	ax,bx	; 180c:4126  & 6  (BX = 6)
	shr	al,1h	; 180c:4128  >> 1  -> octant 0..3
	mov	byte ptr [bp + 0f94ch],al	; 180c:412a  cache octant byte
	; octant * 2 = word index into each of the four step-function tables;
	; copy the per-octant case-body address from each table into the active
	; near-call slot the scanline loops JMP through.
	mov	bl,al	; 180c:412e  BX = octant
	xor	bh,bh	; 180c:4130
	shl	bx,1h	; 180c:4132  BX = octant * 2
	mov	ax,word ptr [bx + offset DGROUP:_g_apRotBlitStep1FpTable]	; 180c:4134  step1 slot
	mov	[_g_pRotBlitStep1Fp],ax	; 180c:4138
	mov	ax,word ptr [bx + offset DGROUP:_g_apRotBlitStep2FpTable]	; 180c:413b  step2 slot
	mov	[_g_pRotBlitStep2Fp],ax	; 180c:413f
	mov	ax,word ptr [bx + offset DGROUP:_g_apRotBlitStep3FpTable]	; 180c:4142  step3 slot
	mov	[_g_pRotBlitStep3Fp],ax	; 180c:4146
	mov	ax,word ptr [bx + offset DGROUP:_g_apRotBlitStep4FpTable]	; 180c:4149  step4 slot
	mov	[_g_pRotBlitStep4Fp],ax	; 180c:414d
	mov	ax,offset DGROUP:_g_aStretchYSrcTable	; 180c:4150  MOV AX,0x5976
	mov	word ptr [bp + 0f94ah],ax	; 180c:4153  MOV word ptr [BP + 0xf94a],AX
	mov	bx,word ptr [_g_wRotBlitIdxTop]	; 180c:4157  MOV BX,word ptr [0x2f5c]
	mov	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:415b  MOV AX,word ptr [BX + 0x2f54]
	cwd	; 180c:415f  CWD
	not	dx	; 180c:4160  NOT DX
	and	ax,dx	; 180c:4162  AND AX,DX
	mov	word ptr [bp + 0f952h],ax	; 180c:4164  MOV word ptr [BP + 0xf952],AX
	mov	bx,word ptr [bp + 0f94ah]	; 180c:4168  MOV BX,word ptr [BP + 0xf94a]
	mov	word ptr [bx],ax	; 180c:416c  MOV word ptr [BX],AX
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]	; 180c:416e  MOV BX,word ptr [0x2f62]
	push	word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:4172  PUSH word ptr [BX + 0x2f54]
	push	word ptr [bx + offset DGROUP:_g_anRotBlitVertX]	; 180c:4176  PUSH word ptr [BX + 0x2f4c]
	mov	bx,word ptr [_g_wRotBlitIdxTop]	; 180c:417a  MOV BX,word ptr [0x2f5c]
	push	word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:417e  PUSH word ptr [BX + 0x2f54]
	push	word ptr [bx + offset DGROUP:_g_anRotBlitVertX]	; 180c:4182  PUSH word ptr [BX + 0x2f4c]
	mov	ax,word ptr [bp + 0f94ah]	; 180c:4186  MOV AX,word ptr [BP + 0xf94a]
	inc	ax	; 180c:418a  INC AX
	inc	ax	; 180c:418b  INC AX
	push	ax	; 180c:418c  PUSH AX
	call	near ptr _stretch_walk_x_clipped	; 180c:418d  CALL 0x1000:bfb4
	add	sp,0ah	; 180c:4190  ADD SP,0xa
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]	; 180c:4193  MOV BX,word ptr [0x2f62]
	mov	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:4197  MOV AX,word ptr [BX + 0x2f54]
	sub	ax,word ptr [bp + 0f952h]	; 180c:419b  SUB AX,word ptr [BP + 0xf952]
	cwd	; 180c:419f  CWD
	not	dx	; 180c:41a0  NOT DX
	and	ax,dx	; 180c:41a2  AND AX,DX
	mov	word ptr [bp + 0f954h],ax	; 180c:41a4  MOV word ptr [BP + 0xf954],AX
	mov	bx,word ptr [_g_wRotBlitIdxBottom]	; 180c:41a8  MOV BX,word ptr [0x2f5e]
	push	word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:41ac  PUSH word ptr [BX + 0x2f54]
	push	word ptr [bx + offset DGROUP:_g_anRotBlitVertX]	; 180c:41b0  PUSH word ptr [BX + 0x2f4c]
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]	; 180c:41b4  MOV BX,word ptr [0x2f62]
	push	word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:41b8  PUSH word ptr [BX + 0x2f54]
	push	word ptr [bx + offset DGROUP:_g_anRotBlitVertX]	; 180c:41bc  PUSH word ptr [BX + 0x2f4c]
	mov	ax,word ptr [bp + 0f954h]	; 180c:41c0  MOV AX,word ptr [BP + 0xf954]
	inc	ax	; 180c:41c4  INC AX
	shl	ax,1h	; 180c:41c5  SHL AX,0x1
	add	ax,word ptr [bp + 0f94ah]	; 180c:41c7  ADD AX,word ptr [BP + 0xf94a]
	push	ax	; 180c:41cb  PUSH AX
	call	near ptr _stretch_walk_x_clipped	; 180c:41cc  CALL 0x1000:bfb4
	add	sp,0ah	; 180c:41cf  ADD SP,0xa
	mov	bx,word ptr [bp + 6h]	; 180c:41d2  MOV BX,word ptr [BP + 0x6]
	mov	ax,word ptr [bx + 8h]	; 180c:41d5  MOV AX,word ptr [BX + 0x8]
	dec	ax	; 180c:41d8  DEC AX
	mov	word ptr [bp + 0f936h],ax	; 180c:41d9  MOV word ptr [BP + 0xf936],AX
	mov	ax,word ptr [bx + 6h]	; 180c:41dd  MOV AX,word ptr [BX + 0x6]
	dec	ax	; 180c:41e0  DEC AX
	mov	word ptr [bp + 0f938h],ax	; 180c:41e1  MOV word ptr [BP + 0xf938],AX
	test	byte ptr [bp + 0f94ch],1h	; 180c:41e5  TEST byte ptr [BP + 0xf94c],0x1
	jz	L_02a0	; 180c:41ea  JZ 0x1000:c2cd
	mov	ax,word ptr [bp + 0f936h]	; 180c:41ec  MOV AX,word ptr [BP + 0xf936]
	xchg	word ptr [bp + 0f938h],ax	; 180c:41f0  XCHG word ptr [BP + 0xf938],AX
	mov	word ptr [bp + 0f936h],ax	; 180c:41f4  MOV word ptr [BP + 0xf936],AX
	mov	ax,word ptr [bp + 0f95ch]	; 180c:41f8  MOV AX,word ptr [BP + 0xf95c]
	xchg	word ptr [bp + 0f95ah],ax	; 180c:41fc  XCHG word ptr [BP + 0xf95a],AX
	mov	word ptr [bp + 0f95ch],ax	; 180c:4200  MOV word ptr [BP + 0xf95c],AX
	mov	ax,word ptr [bp + 0eh]	; 180c:4204  MOV AX,word ptr [BP + 0xe]
	xchg	word ptr [bp + 10h],ax	; 180c:4207  XCHG word ptr [BP + 0x10],AX
	mov	word ptr [bp + 0eh],ax	; 180c:420a  MOV word ptr [BP + 0xe],AX
L_02a0:
	xor	ax,ax	; 180c:420d  XOR AX,AX
	mov	word ptr [bp + 0f94eh],ax	; 180c:420f  MOV word ptr [BP + 0xf94e],AX
	mov	word ptr [bp + 0f950h],ax	; 180c:4213  MOV word ptr [BP + 0xf950],AX
	mov	bx,word ptr [_g_wRotBlitIdxNextCW]	; 180c:4217  MOV BX,word ptr [0x2f60]
	mov	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:421b  MOV AX,word ptr [BX + 0x2f54]
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]	; 180c:421f  MOV BX,word ptr [0x2f62]
	cmp	word ptr [bx + offset DGROUP:_g_anRotBlitVertY],ax	; 180c:4223  CMP word ptr [BX + 0x2f54],AX
	jl	L_02bf	; 180c:4227  JL 0x1000:c2ec
	jmp	L_0437	; 180c:4229  JMP 0x1000:c464
L_02bf:
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]	; 180c:422c  MOV BX,word ptr [0x2f62]
	mov	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:4230  MOV AX,word ptr [BX + 0x2f54]
	mov	bx,word ptr [_g_wRotBlitIdxTop]	; 180c:4234  MOV BX,word ptr [0x2f5c]
	sub	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:4238  SUB AX,word ptr [BX + 0x2f54]
	mov	cx,word ptr [bx + offset DGROUP:_g_anRotBlitVertX]	; 180c:423c  MOV CX,word ptr [BX + 0x2f4c]
	mov	bx,word ptr [_g_wRotBlitIdxNextCW]	; 180c:4240  MOV BX,word ptr [0x2f60]
	sub	cx,word ptr [bx + offset DGROUP:_g_anRotBlitVertX]	; 180c:4244  SUB CX,word ptr [BX + 0x2f4c]
	neg	cx	; 180c:4248  NEG CX
	imul	cx	; 180c:424a  IMUL CX
	mov	cx,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:424c  MOV CX,word ptr [BX + 0x2f54]
	mov	bx,word ptr [_g_wRotBlitIdxTop]	; 180c:4250  MOV BX,word ptr [0x2f5c]
	sub	cx,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:4254  SUB CX,word ptr [BX + 0x2f54]
	jz	L_02ef	; 180c:4258  JZ 0x1000:c31c
	idiv	cx	; 180c:425a  IDIV CX
L_02ef:
	add	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertX]	; 180c:425c  ADD AX,word ptr [BX + 0x2f4c]
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]	; 180c:4260  MOV BX,word ptr [0x2f62]
	sub	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertX]	; 180c:4264  SUB AX,word ptr [BX + 0x2f4c]
	or	ax,ax	; 180c:4268  OR AX,AX
	jnz	L_0302	; 180c:426a  JNZ 0x1000:c32f
	jmp	near ptr _vga_reset_gc_default_thunk	; 180c:426c  JMP 0x1000:c022 (near, intra-seg)
L_0302:
	mov	word ptr [bp + 0faf2h],ax	; 180c:426f  MOV word ptr [BP + 0xfaf2],AX
	mov	ax,word ptr [bp + 0f95ch]	; 180c:4273  MOV AX,word ptr [BP + 0xf95c]
	mov	bx,ax	; 180c:4277  MOV BX,AX
	or	ax,ax	; 180c:4279  OR AX,AX
	jz	L_031e	; 180c:427b  JZ 0x1000:c34b
	mov	ax,word ptr [bp + 10h]	; 180c:427d  MOV AX,word ptr [BP + 0x10]
	imul	word ptr [bp + 0f95ah]	; 180c:4280  IMUL word ptr [BP + 0xf95a]
	idiv	bx	; 180c:4284  IDIV BX
	cwd	; 180c:4286  CWD
	xor	ax,dx	; 180c:4287  XOR AX,DX
	sub	ax,dx	; 180c:4289  SUB AX,DX
L_031e:
	imul	word ptr [bp + 0f938h]	; 180c:428b  IMUL word ptr [BP + 0xf938]
	or	dx,dx	; 180c:428f  OR DX,DX
	jz	L_032b	; 180c:4291  JZ 0x1000:c358
	mov	ax,0ffffh	; 180c:4293  MOV AX,0xffff
	xor	dx,dx	; 180c:4296  XOR DX,DX
L_032b:
	div	word ptr [bp + 0eh]	; 180c:4298  DIV word ptr [BP + 0xe]
	cmp	ax,140h	; 140h span-w clamp 320 (AX=divided px, cmp/jc/mov idiom)
	jc	L_0336	; 180c:429e  JC 0x1000:c363
	mov	ax,140h	; 140h span-w clamp 320 (AX=divided px, cmp/jc/mov idiom)
L_0336:
	mov	word ptr [bp + 0f952h],ax	; 180c:42a3  MOV word ptr [BP + 0xf952],AX
	push	word ptr [bp + 0faf2h]	; 180c:42a7  PUSH word ptr [BP + 0xfaf2]
	lea	bx,[bp + 0f942h]	; 180c:42ab  LEA BX,[BP + 0xf942]
	xor	ax,ax	; 180c:42af  XOR AX,AX
	mov	word ptr [bx + 2h],ax	; 180c:42b1  MOV word ptr [BX + 0x2],AX
	mov	ax,word ptr [bp + 0f936h]	; 180c:42b4  MOV AX,word ptr [BP + 0xf936]
	mov	word ptr [bx + 6h],ax	; 180c:42b8  MOV word ptr [BX + 0x6],AX
	push	bx	; 180c:42bb  PUSH BX
	call	_stretch_step_init	; 180c:42bc  CALL 0x1000:9731 (90 0e e8 after backward collapse)
	add	sp,2h	; 180c:42c1  ADD SP,0x2
	lea	bx,[bp + 0f93ah]	; 180c:42c4  LEA BX,[BP + 0xf93a]
	xor	ax,ax	; 180c:42c8  XOR AX,AX
	mov	word ptr [bx + 2h],ax	; 180c:42ca  MOV word ptr [BX + 0x2],AX
	mov	ax,word ptr [bp + 0f952h]	; 180c:42cd  MOV AX,word ptr [BP + 0xf952]
	mov	word ptr [bx + 6h],ax	; 180c:42d1  MOV word ptr [BX + 0x6],AX
	push	bx	; 180c:42d4  PUSH BX
	call	_stretch_step_init	; 180c:42d5  CALL 0x1000:9731 (90 0e e8 after backward collapse)
	add	sp,4h	; 180c:42da  ADD SP,0x4
	xor	si,si	; 180c:42dd  XOR SI,SI
L_0372:
	lea	bx,[bp + 0f942h]	; 180c:42df  LEA BX,[BP + 0xf942]
	mov	ax,word ptr [bx + 2h]	; 180c:42e3  MOV AX,word ptr [BX + 0x2]
	mov	word ptr [bp + 0f956h],ax	; 180c:42e6  MOV word ptr [BP + 0xf956],AX
	mov	ax,word ptr [bx + 4h]	; 180c:42ea  MOV AX,word ptr [BX + 0x4]
	mov	dx,word ptr [bx + 6h]	; 180c:42ed  MOV DX,word ptr [BX + 0x6]
	add	word ptr [bx],ax	; 180c:42f0  ADD word ptr [BX],AX
	adc	word ptr [bx + 2h],dx	; 180c:42f2  ADC word ptr [BX + 0x2],DX
	lea	bx,[bp + 0f93ah]	; 180c:42f5  LEA BX,[BP + 0xf93a]
	mov	ax,word ptr [bx + 2h]	; 180c:42f9  MOV AX,word ptr [BX + 0x2]
	mov	word ptr [bp + 0f958h],ax	; 180c:42fc  MOV word ptr [BP + 0xf958],AX
	mov	ax,word ptr [bx + 4h]	; 180c:4300  MOV AX,word ptr [BX + 0x4]
	mov	dx,word ptr [bx + 6h]	; 180c:4303  MOV DX,word ptr [BX + 0x6]
	add	word ptr [bx],ax	; 180c:4306  ADD word ptr [BX],AX
	adc	word ptr [bx + 2h],dx	; 180c:4308  ADC word ptr [BX + 0x2],DX
	mov	cx,word ptr [bp + 0f956h]	; 180c:430b  MOV CX,word ptr [BP + 0xf956]
	mov	ax,word ptr [bp + 0f94eh]	; 180c:430f  MOV AX,word ptr [BP + 0xf94e]
	sub	cx,ax	; 180c:4313  SUB CX,AX
	inc	cx	; 180c:4315  INC CX
	jle	L_03bb	; 180c:4316  JLE 0x1000:c3e8
	add	word ptr [bp + 0f94eh],cx	; 180c:4318  ADD word ptr [BP + 0xf94e],CX
	lea	di,[bp + 0fafch]	; 180c:431c  LEA DI,[BP + 0xfafc]
	shl	ax,1h	; 180c:4320  SHL AX,0x1
	add	di,ax	; 180c:4322  ADD DI,AX
	mov	ax,si	; 180c:4324  MOV AX,SI
	rep	stosw	; 180c:4326  STOSW.REP ES:DI
L_03bb:
	mov	cx,word ptr [bp + 0f958h]	; 180c:4328  MOV CX,word ptr [BP + 0xf958]
	mov	ax,word ptr [bp + 0f950h]	; 180c:432c  MOV AX,word ptr [BP + 0xf950]
	sub	cx,ax	; 180c:4330  SUB CX,AX
	inc	cx	; 180c:4332  INC CX
	jl	L_03d8	; 180c:4333  JL 0x1000:c405
	add	word ptr [bp + 0f950h],cx	; 180c:4335  ADD word ptr [BP + 0xf950],CX
	lea	di,[bp + 0fd7ch]	; 180c:4339  LEA DI,[BP + 0xfd7c]
	shl	ax,1h	; 180c:433d  SHL AX,0x1
	add	di,ax	; 180c:433f  ADD DI,AX
	mov	ax,si	; 180c:4341  MOV AX,SI
	rep	stosw	; 180c:4343  STOSW.REP ES:DI
L_03d8:
	lea	bx,[bp + 0f960h]	; 180c:4345  LEA BX,[BP + 0xf960]
	jmp	word ptr [_g_pRotBlitStep1Fp]	; 180c:4349  JMP word ptr [0x2f64]
L_03e0:
_rotblit_step1_oct0:				; 180c:434d -> g_apRotBlitStep1FpTable[0]
	mov	ax,word ptr [bp + 0f956h]	; 180c:434d  MOV AX,word ptr [BP + 0xf956]
	shl	ax,1h	; 180c:4351  SHL AX,0x1
	add	bx,ax	; 180c:4353  ADD BX,AX
	mov	ax,word ptr [bp + 0f958h]	; 180c:4355  MOV AX,word ptr [BP + 0xf958]
	sub	ax,word ptr [bx]	; 180c:4359  SUB AX,word ptr [BX]
	jmp	short L_0422	; 180c:435b  JMP 0x1000:c44f
L_03f0:
_rotblit_step1_oct1:				; 180c:435d -> g_apRotBlitStep1FpTable[1]
	mov	ax,word ptr [bp + 0f958h]	; 180c:435d  MOV AX,word ptr [BP + 0xf958]
	shl	ax,1h	; 180c:4361  SHL AX,0x1
	add	bx,ax	; 180c:4363  ADD BX,AX
	mov	ax,word ptr [bp + 0f956h]	; 180c:4365  MOV AX,word ptr [BP + 0xf956]
	neg	ax	; 180c:4369  NEG AX
	sub	ax,word ptr [bx]	; 180c:436b  SUB AX,word ptr [BX]
	jmp	short L_0422	; 180c:436d  JMP 0x1000:c44f
L_0402:
_rotblit_step1_oct2:				; 180c:436f -> g_apRotBlitStep1FpTable[2]
	mov	ax,word ptr [bp + 0f956h]	; 180c:436f  MOV AX,word ptr [BP + 0xf956]
	shl	ax,1h	; 180c:4373  SHL AX,0x1
	add	bx,ax	; 180c:4375  ADD BX,AX
	mov	ax,word ptr [bp + 0f958h]	; 180c:4377  MOV AX,word ptr [BP + 0xf958]
	neg	ax	; 180c:437b  NEG AX
	add	ax,word ptr [bx]	; 180c:437d  ADD AX,word ptr [BX]
	jmp	short L_0422	; 180c:437f  JMP 0x1000:c44f
L_0414:
_rotblit_step1_oct3:				; 180c:4381 -> g_apRotBlitStep1FpTable[3]
	mov	ax,word ptr [bp + 0f958h]	; 180c:4381  MOV AX,word ptr [BP + 0xf958]
	shl	ax,1h	; 180c:4385  SHL AX,0x1
	add	bx,ax	; 180c:4387  ADD BX,AX
	mov	ax,word ptr [bp + 0f956h]	; 180c:4389  MOV AX,word ptr [BP + 0xf956]
	add	ax,word ptr [bx]	; 180c:438d  ADD AX,word ptr [BX]
L_0422:
	mov	bx,si	; 180c:438f  MOV BX,SI
	shl	bx,1h	; 180c:4391  SHL BX,0x1
	mov	word ptr [bx + offset DGROUP:_g_aStretchXSrcTable],ax	; 180c:4393  MOV word ptr [BX + 0x5476],AX
	inc	si	; 180c:4397  INC SI
	cmp	si,word ptr [bp + 0faf2h]	; 180c:4398  CMP SI,word ptr [BP + 0xfaf2]
	jge	L_0434	; 180c:439c  JGE 0x1000:c461
	jmp	L_0372	; 180c:439e  JMP 0x1000:c39f
L_0434:
	jmp	L_05ae	; 180c:43a1  JMP 0x1000:c5db
L_0437:
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]	; 180c:43a4  MOV BX,word ptr [0x2f62]
	mov	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:43a8  MOV AX,word ptr [BX + 0x2f54]
	mov	bx,word ptr [_g_wRotBlitIdxBottom]	; 180c:43ac  MOV BX,word ptr [0x2f5e]
	sub	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:43b0  SUB AX,word ptr [BX + 0x2f54]
	mov	cx,word ptr [bx + offset DGROUP:_g_anRotBlitVertX]	; 180c:43b4  MOV CX,word ptr [BX + 0x2f4c]
	mov	bx,word ptr [_g_wRotBlitIdxNextCW]	; 180c:43b8  MOV BX,word ptr [0x2f60]
	sub	cx,word ptr [bx + offset DGROUP:_g_anRotBlitVertX]	; 180c:43bc  SUB CX,word ptr [BX + 0x2f4c]
	neg	cx	; 180c:43c0  NEG CX
	imul	cx	; 180c:43c2  IMUL CX
	mov	cx,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:43c4  MOV CX,word ptr [BX + 0x2f54]
	mov	bx,word ptr [_g_wRotBlitIdxBottom]	; 180c:43c8  MOV BX,word ptr [0x2f5e]
	sub	cx,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:43cc  SUB CX,word ptr [BX + 0x2f54]
	jz	L_0467	; 180c:43d0  JZ 0x1000:c494
	idiv	cx	; 180c:43d2  IDIV CX
L_0467:
	add	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertX]	; 180c:43d4  ADD AX,word ptr [BX + 0x2f4c]
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]	; 180c:43d8  MOV BX,word ptr [0x2f62]
	sub	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertX]	; 180c:43dc  SUB AX,word ptr [BX + 0x2f4c]
	or	ax,ax	; 180c:43e0  OR AX,AX
	jnz	L_047a	; 180c:43e2  JNZ 0x1000:c4a7
	jmp	L_08bc	; 180c:43e4  JMP 0x1000:c8e9
L_047a:
	mov	word ptr [bp + 0faf2h],ax	; 180c:43e7  MOV word ptr [BP + 0xfaf2],AX
	mov	ax,word ptr [bp + 0f95ah]	; 180c:43eb  MOV AX,word ptr [BP + 0xf95a]
	mov	bx,ax	; 180c:43ef  MOV BX,AX
	or	ax,ax	; 180c:43f1  OR AX,AX
	jz	L_0496	; 180c:43f3  JZ 0x1000:c4c3
	mov	ax,word ptr [bp + 0eh]	; 180c:43f5  MOV AX,word ptr [BP + 0xe]
	imul	word ptr [bp + 0f95ch]	; 180c:43f8  IMUL word ptr [BP + 0xf95c]
	idiv	bx	; 180c:43fc  IDIV BX
	cwd	; 180c:43fe  CWD
	xor	ax,dx	; 180c:43ff  XOR AX,DX
	sub	ax,dx	; 180c:4401  SUB AX,DX
L_0496:
	imul	word ptr [bp + 0f936h]	; 180c:4403  IMUL word ptr [BP + 0xf936]
	or	dx,dx	; 180c:4407  OR DX,DX
	jz	L_04a3	; 180c:4409  JZ 0x1000:c4d0
	mov	ax,0ffffh	; 180c:440b  MOV AX,0xffff
	xor	dx,dx	; 180c:440e  XOR DX,DX
L_04a3:
	div	word ptr [bp + 10h]	; 180c:4410  DIV word ptr [BP + 0x10]
	cmp	ax,140h	; 140h span-w clamp 320 (AX=divided px, cmp/jc/mov idiom)
	jc	L_04ae	; 180c:4416  JC 0x1000:c4db
	mov	ax,140h	; 140h span-w clamp 320 (AX=divided px, cmp/jc/mov idiom)
L_04ae:
	mov	word ptr [bp + 0f952h],ax	; 180c:441b  MOV word ptr [BP + 0xf952],AX
	xor	ax,ax	; 180c:441f  XOR AX,AX
	push	word ptr [bp + 0faf2h]	; 180c:4421  PUSH word ptr [BP + 0xfaf2]
	lea	bx,[bp + 0f942h]	; 180c:4425  LEA BX,[BP + 0xf942]
	xor	ax,ax	; 180c:4429  XOR AX,AX
	mov	word ptr [bx + 2h],ax	; 180c:442b  MOV word ptr [BX + 0x2],AX
	mov	ax,word ptr [bp + 0f952h]	; 180c:442e  MOV AX,word ptr [BP + 0xf952]
	mov	word ptr [bx + 6h],ax	; 180c:4432  MOV word ptr [BX + 0x6],AX
	push	bx	; 180c:4435  PUSH BX
	call	_stretch_step_init	; 180c:4436  CALL 0x1000:9731 (90 0e e8 after backward collapse)
	add	sp,2h	; 180c:443b  ADD SP,0x2
	lea	bx,[bp + 0f93ah]	; 180c:443e  LEA BX,[BP + 0xf93a]
	xor	ax,ax	; 180c:4442  XOR AX,AX
	mov	word ptr [bx + 2h],ax	; 180c:4444  MOV word ptr [BX + 0x2],AX
	mov	ax,word ptr [bp + 0f938h]	; 180c:4447  MOV AX,word ptr [BP + 0xf938]
	mov	word ptr [bx + 6h],ax	; 180c:444b  MOV word ptr [BX + 0x6],AX
	push	bx	; 180c:444e  PUSH BX
	call	_stretch_step_init	; 180c:444f  CALL 0x1000:9731 (90 0e e8 after backward collapse)
	add	sp,4h	; 180c:4454  ADD SP,0x4
	xor	si,si	; 180c:4457  XOR SI,SI
L_04ec:
	lea	bx,[bp + 0f942h]	; 180c:4459  LEA BX,[BP + 0xf942]
	mov	ax,word ptr [bx + 2h]	; 180c:445d  MOV AX,word ptr [BX + 0x2]
	mov	word ptr [bp + 0f956h],ax	; 180c:4460  MOV word ptr [BP + 0xf956],AX
	mov	ax,word ptr [bx + 4h]	; 180c:4464  MOV AX,word ptr [BX + 0x4]
	mov	dx,word ptr [bx + 6h]	; 180c:4467  MOV DX,word ptr [BX + 0x6]
	add	word ptr [bx],ax	; 180c:446a  ADD word ptr [BX],AX
	adc	word ptr [bx + 2h],dx	; 180c:446c  ADC word ptr [BX + 0x2],DX
	lea	bx,[bp + 0f93ah]	; 180c:446f  LEA BX,[BP + 0xf93a]
	mov	ax,word ptr [bx + 2h]	; 180c:4473  MOV AX,word ptr [BX + 0x2]
	mov	word ptr [bp + 0f958h],ax	; 180c:4476  MOV word ptr [BP + 0xf958],AX
	mov	ax,word ptr [bx + 4h]	; 180c:447a  MOV AX,word ptr [BX + 0x4]
	mov	dx,word ptr [bx + 6h]	; 180c:447d  MOV DX,word ptr [BX + 0x6]
	add	word ptr [bx],ax	; 180c:4480  ADD word ptr [BX],AX
	adc	word ptr [bx + 2h],dx	; 180c:4482  ADC word ptr [BX + 0x2],DX
	mov	cx,word ptr [bp + 0f956h]	; 180c:4485  MOV CX,word ptr [BP + 0xf956]
	mov	ax,word ptr [bp + 0f94eh]	; 180c:4489  MOV AX,word ptr [BP + 0xf94e]
	sub	cx,ax	; 180c:448d  SUB CX,AX
	inc	cx	; 180c:448f  INC CX
	jle	L_0535	; 180c:4490  JLE 0x1000:c562
	add	word ptr [bp + 0f94eh],cx	; 180c:4492  ADD word ptr [BP + 0xf94e],CX
	lea	di,[bp + 0fafch]	; 180c:4496  LEA DI,[BP + 0xfafc]
	shl	ax,1h	; 180c:449a  SHL AX,0x1
	add	di,ax	; 180c:449c  ADD DI,AX
	mov	ax,si	; 180c:449e  MOV AX,SI
	rep	stosw	; 180c:44a0  STOSW.REP ES:DI
L_0535:
	mov	cx,word ptr [bp + 0f958h]	; 180c:44a2  MOV CX,word ptr [BP + 0xf958]
	mov	ax,word ptr [bp + 0f950h]	; 180c:44a6  MOV AX,word ptr [BP + 0xf950]
	sub	cx,ax	; 180c:44aa  SUB CX,AX
	inc	cx	; 180c:44ac  INC CX
	jl	L_0552	; 180c:44ad  JL 0x1000:c57f
	add	word ptr [bp + 0f950h],cx	; 180c:44af  ADD word ptr [BP + 0xf950],CX
	lea	di,[bp + 0fd7ch]	; 180c:44b3  LEA DI,[BP + 0xfd7c]
	shl	ax,1h	; 180c:44b7  SHL AX,0x1
	add	di,ax	; 180c:44b9  ADD DI,AX
	mov	ax,si	; 180c:44bb  MOV AX,SI
	rep	stosw	; 180c:44bd  STOSW.REP ES:DI
L_0552:
	lea	bx,[bp + 0f960h]	; 180c:44bf  LEA BX,[BP + 0xf960]
	jmp	word ptr [_g_pRotBlitStep2Fp]	; 180c:44c3  JMP word ptr [0x2f6e]
L_055a:
_rotblit_step2_oct0:				; 180c:44c7 -> g_apRotBlitStep2FpTable[0]
	mov	ax,word ptr [bp + 0f956h]	; 180c:44c7  MOV AX,word ptr [BP + 0xf956]
	shl	ax,1h	; 180c:44cb  SHL AX,0x1
	add	bx,ax	; 180c:44cd  ADD BX,AX
	mov	ax,word ptr [bp + 0f958h]	; 180c:44cf  MOV AX,word ptr [BP + 0xf958]
	sub	ax,word ptr [bx]	; 180c:44d3  SUB AX,word ptr [BX]
	jmp	short L_059c	; 180c:44d5  JMP 0x1000:c5c9
L_056a:
_rotblit_step2_oct1:				; 180c:44d7 -> g_apRotBlitStep2FpTable[1]
	mov	ax,word ptr [bp + 0f958h]	; 180c:44d7  MOV AX,word ptr [BP + 0xf958]
	shl	ax,1h	; 180c:44db  SHL AX,0x1
	add	bx,ax	; 180c:44dd  ADD BX,AX
	mov	ax,word ptr [bp + 0f956h]	; 180c:44df  MOV AX,word ptr [BP + 0xf956]
	neg	ax	; 180c:44e3  NEG AX
	sub	ax,word ptr [bx]	; 180c:44e5  SUB AX,word ptr [BX]
	jmp	short L_059c	; 180c:44e7  JMP 0x1000:c5c9
L_057c:
_rotblit_step2_oct2:				; 180c:44e9 -> g_apRotBlitStep2FpTable[2]
	mov	ax,word ptr [bp + 0f956h]	; 180c:44e9  MOV AX,word ptr [BP + 0xf956]
	shl	ax,1h	; 180c:44ed  SHL AX,0x1
	add	bx,ax	; 180c:44ef  ADD BX,AX
	mov	ax,word ptr [bp + 0f958h]	; 180c:44f1  MOV AX,word ptr [BP + 0xf958]
	neg	ax	; 180c:44f5  NEG AX
	add	ax,word ptr [bx]	; 180c:44f7  ADD AX,word ptr [BX]
	jmp	short L_059c	; 180c:44f9  JMP 0x1000:c5c9
L_058e:
_rotblit_step2_oct3:				; 180c:44fb -> g_apRotBlitStep2FpTable[3]
	mov	ax,word ptr [bp + 0f958h]	; 180c:44fb  MOV AX,word ptr [BP + 0xf958]
	shl	ax,1h	; 180c:44ff  SHL AX,0x1
	add	bx,ax	; 180c:4501  ADD BX,AX
	mov	ax,word ptr [bp + 0f956h]	; 180c:4503  MOV AX,word ptr [BP + 0xf956]
	add	ax,word ptr [bx]	; 180c:4507  ADD AX,word ptr [BX]
L_059c:
	mov	bx,si	; 180c:4509  MOV BX,SI
	shl	bx,1h	; 180c:450b  SHL BX,0x1
	mov	word ptr [bx + offset DGROUP:_g_aStretchXSrcTable],ax	; 180c:450d  MOV word ptr [BX + 0x5476],AX
	inc	si	; 180c:4511  INC SI
	cmp	si,word ptr [bp + 0faf2h]	; 180c:4512  CMP SI,word ptr [BP + 0xfaf2]
	jge	L_05ae	; 180c:4516  JGE 0x1000:c5db
	jmp	L_04ec	; 180c:4518  JMP 0x1000:c519
L_05ae:
	mov	cx,word ptr [bp + 0f936h]	; 180c:451b  MOV CX,word ptr [BP + 0xf936]
	inc	cx	; 180c:451f  INC CX
	mov	ax,word ptr [bp + 0f94eh]	; 180c:4520  MOV AX,word ptr [BP + 0xf94e]
	sub	cx,ax	; 180c:4524  SUB CX,AX
	jl	L_05c7	; 180c:4526  JL 0x1000:c5f4
	lea	di,[bp + 0fafch]	; 180c:4528  LEA DI,[BP + 0xfafc]
	shl	ax,1h	; 180c:452c  SHL AX,0x1
	add	di,ax	; 180c:452e  ADD DI,AX
	mov	ax,si	; 180c:4530  MOV AX,SI
	rep	stosw	; 180c:4532  STOSW.REP ES:DI
L_05c7:
	mov	cx,word ptr [bp + 0f938h]	; 180c:4534  MOV CX,word ptr [BP + 0xf938]
	inc	cx	; 180c:4538  INC CX
	mov	ax,word ptr [bp + 0f950h]	; 180c:4539  MOV AX,word ptr [BP + 0xf950]
	sub	cx,ax	; 180c:453d  SUB CX,AX
	jl	L_05e0	; 180c:453f  JL 0x1000:c60d
	lea	di,[bp + 0fd7ch]	; 180c:4541  LEA DI,[BP + 0xfd7c]
	shl	ax,1h	; 180c:4545  SHL AX,0x1
	add	di,ax	; 180c:4547  ADD DI,AX
	mov	ax,si	; 180c:4549  MOV AX,SI
	rep	stosw	; 180c:454b  STOSW.REP ES:DI
L_05e0:
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]	; 180c:454d  MOV BX,word ptr [0x2f62]
	mov	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:4551  MOV AX,word ptr [BX + 0x2f54]
	mov	bx,word ptr [_g_wRotBlitIdxTop]	; 180c:4555  MOV BX,word ptr [0x2f5c]
	sub	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:4559  SUB AX,word ptr [BX + 0x2f54]
	push	ax	; 180c:455d  PUSH AX
	xor	ax,ax	; 180c:455e  XOR AX,AX
	lea	bx,[bp + 0f942h]	; 180c:4560  LEA BX,[BP + 0xf942]
	mov	word ptr [bx + 2h],ax	; 180c:4564  MOV word ptr [BX + 0x2],AX
	mov	ax,word ptr [bp + 0f936h]	; 180c:4567  MOV AX,word ptr [BP + 0xf936]
	mov	word ptr [bx + 6h],ax	; 180c:456b  MOV word ptr [BX + 0x6],AX
	push	bx	; 180c:456e  PUSH BX
	call	_stretch_step_init	; 180c:456f  CALL 0x1000:9731 (90 0e e8 after backward collapse)
	add	sp,4h	; 180c:4574  ADD SP,0x4
	cmp	byte ptr [_g_graphics_context.bVideoAdapter],2h	; 180c:4577  CMP byte ptr [0x202d],0x2
	jz	L_0621	; 180c:457c  JZ 0x1000:c64e
	cmp	byte ptr [_g_graphics_context.bVideoAdapter],0ch	; 180c:457e  CMP byte ptr [0x202d],0xc
	jz	L_0621	; 180c:4583  JZ 0x1000:c64e
	cmp	byte ptr [_g_graphics_context.bVideoAdapter],0dh	; 180c:4585  CMP byte ptr [0x202d],0xd
	jz	L_0621	; 180c:458a  JZ 0x1000:c64e
	jnz	L_062f	; 180c:458c  JNZ 0x1000:c65c
	; Reset the VGA Graphics Controller to defaults and arm the Bit Mask
	; register for the renderer (see the VGA hardware primer at the top of
	; this file). Only reached on planar adapters (the bVideoAdapter gate
	; just above). Each OUT DX,AX writes index=AL, data=AH in one go.
L_0621:
	mov	dx,3ceh	; 3ceh VGA GC index port (DX->OUT dx,ax/al; adapter-gated)
	mov	ax,1h	; 180c:4591  GC reg 1 (Enable Set/Reset)
	out	dx,ax	; 180c:4594    = 0
	mov	ax,5h	; 180c:4595  GC reg 5 (Graphics Mode)
	out	dx,ax	; 180c:4598    = 0
	mov	al,8h	; 180c:4599  select GC reg 8 (Bit Mask)
	out	dx,al	; 180c:459b    index only; data filled by renderer
L_062f:
	mov	bx,word ptr [bp + 0f94ah]	; 180c:459c  MOV BX,word ptr [BP + 0xf94a]
	mov	ax,word ptr [bx]	; 180c:45a0  MOV AX,word ptr [BX]
	add	bx,2h	; 180c:45a2  ADD BX,0x2
	mov	word ptr [bp + 0f94ah],bx	; 180c:45a5  MOV word ptr [BP + 0xf94a],BX
	mov	word ptr [bp + 0f952h],ax	; 180c:45a9  MOV word ptr [BP + 0xf952],AX
	mov	ax,word ptr [_g_graphics_context.wGfxBlitDstPage]	; 180c:45ad  MOV AX,[0x2028]
	mov	es,ax	; 180c:45b0  MOV ES,AX
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]	; 180c:45b2  MOV BX,word ptr [0x2f62]
	mov	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:45b6  MOV AX,word ptr [BX + 0x2f54]
	mov	word ptr [bp + 0f94eh],ax	; 180c:45ba  MOV word ptr [BP + 0xf94e],AX
	mov	bx,word ptr [_g_wRotBlitIdxTop]	; 180c:45be  MOV BX,word ptr [0x2f5c]
	mov	si,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:45c2  MOV SI,word ptr [BX + 0x2f54]
	cmp	si,word ptr [bp + 0f94eh]	; 180c:45c6  CMP SI,word ptr [BP + 0xf94e]
	jl	L_0662	; 180c:45ca  JL 0x1000:c68f
	jmp	L_076b	; 180c:45cc  JMP 0x1000:c798
L_0662:
	mov	word ptr [bp + 0ah],si	; 180c:45cf  MOV word ptr [BP + 0xa],SI
	lea	bx,[bp + 0f942h]	; 180c:45d2  LEA BX,[BP + 0xf942]
	mov	ax,word ptr [bx + 2h]	; 180c:45d6  MOV AX,word ptr [BX + 0x2]
	mov	word ptr [bp + 0f954h],ax	; 180c:45d9  MOV word ptr [BP + 0xf954],AX
	mov	ax,word ptr [bx + 4h]	; 180c:45dd  MOV AX,word ptr [BX + 0x4]
	mov	dx,word ptr [bx + 6h]	; 180c:45e0  MOV DX,word ptr [BX + 0x6]
	add	word ptr [bx],ax	; 180c:45e3  ADD word ptr [BX],AX
	adc	word ptr [bx + 2h],dx	; 180c:45e5  ADC word ptr [BX + 0x2],DX
	mov	ax,word ptr [bp + 0ah]	; 180c:45e8  MOV AX,word ptr [BP + 0xa]
	cmp	ax,word ptr [bp + 0f952h]	; 180c:45eb  CMP AX,word ptr [BP + 0xf952]
	jge	L_0687	; 180c:45ef  JGE 0x1000:c6b4
	jmp	L_075e	; 180c:45f1  JMP 0x1000:c78b
L_0687:
	cmp	si,word ptr [_g_graphics_context.nClip_ymin]	; 180c:45f4  CMP SI,word ptr [0x2018]
	jge	L_0690	; 180c:45f8  JGE 0x1000:c6bd
	jmp	L_0759	; 180c:45fa  JMP 0x1000:c786
L_0690:
	cmp	si,word ptr [_g_graphics_context.nClip_ymax]	; 180c:45fd  CMP SI,word ptr [0x201a]
	jle	L_0699	; 180c:4601  JLE 0x1000:c6c6
	jmp	L_0759	; 180c:4603  JMP 0x1000:c786
L_0699:
	mov	bx,word ptr [bp + 0f94ah]	; 180c:4606  MOV BX,word ptr [BP + 0xf94a]
	mov	ax,word ptr [bx]	; 180c:460a  MOV AX,word ptr [BX]
	mov	dx,ax	; 180c:460c  MOV DX,AX
	mov	bx,word ptr [_g_wRotBlitIdxNextCW]	; 180c:460e  MOV BX,word ptr [0x2f60]
	mov	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:4612  MOV AX,word ptr [BX + 0x2f54]
	inc	ax	; 180c:4616  INC AX
	cmp	si,ax	; 180c:4617  CMP SI,AX
	jg	L_06be	; 180c:4619  JG 0x1000:c6eb
	mov	ax,word ptr [bp + 0f954h]	; 180c:461b  MOV AX,word ptr [BP + 0xf954]
	shl	ax,1h	; 180c:461f  SHL AX,0x1
	lea	bx,[bp + 0fafch]	; 180c:4621  LEA BX,[BP + 0xfafc]
	add	bx,ax	; 180c:4625  ADD BX,AX
	mov	ax,word ptr [bx]	; 180c:4627  MOV AX,word ptr [BX]
	jmp	short L_06cc	; 180c:4629  JMP 0x1000:c6f9
L_06be:
	mov	ax,word ptr [bp + 0f938h]	; 180c:462b  MOV AX,word ptr [BP + 0xf938]
	shl	ax,1h	; 180c:462f  SHL AX,0x1
	lea	bx,[bp + 0fd7ch]	; 180c:4631  LEA BX,[BP + 0xfd7c]
	add	bx,ax	; 180c:4635  ADD BX,AX
	mov	ax,word ptr [bx]	; 180c:4637  MOV AX,word ptr [BX]
L_06cc:
	mov	cx,ax	; 180c:4639  MOV CX,AX
	jmp	word ptr [_g_pRotBlitStep3Fp]	; 180c:463b  JMP word ptr [0x2f78]
L_06d2:
_rotblit_step3_oct0:				; 180c:463f -> g_apRotBlitStep3FpTable[0]
	mov	ax,word ptr [bp + 0f954h]	; 180c:463f  MOV AX,word ptr [BP + 0xf954]
	shl	ax,1h	; 180c:4643  SHL AX,0x1
	lea	bx,[bp + 0f960h]	; 180c:4645  LEA BX,[BP + 0xf960]
	add	bx,ax	; 180c:4649  ADD BX,AX
	mov	ax,word ptr [bx]	; 180c:464b  MOV AX,word ptr [BX]
	jmp	short L_0712	; 180c:464d  JMP 0x1000:c73f
L_06e2:
_rotblit_step3_oct1:				; 180c:464f -> g_apRotBlitStep3FpTable[1]
	mov	ax,word ptr [bp + 0faf0h]	; 180c:464f  MOV AX,word ptr [BP + 0xfaf0]
	mov	bx,word ptr [bp + 6h]	; 180c:4653  MOV BX,word ptr [BP + 0x6]
	sub	ax,word ptr [bx + 6h]	; 180c:4656  SUB AX,word ptr [BX + 0x6]
	add	ax,word ptr [bp + 0f954h]	; 180c:4659  ADD AX,word ptr [BP + 0xf954]
	jmp	short L_0712	; 180c:465d  JMP 0x1000:c73f
L_06f2:
_rotblit_step3_oct2:				; 180c:465f -> g_apRotBlitStep3FpTable[2]
	mov	ax,word ptr [bp + 0f954h]	; 180c:465f  MOV AX,word ptr [BP + 0xf954]
	shl	ax,1h	; 180c:4663  SHL AX,0x1
	lea	bx,[bp + 0f960h]	; 180c:4665  LEA BX,[BP + 0xf960]
	add	bx,ax	; 180c:4669  ADD BX,AX
	mov	ax,word ptr [bp + 0faf0h]	; 180c:466b  MOV AX,word ptr [BP + 0xfaf0]
	sub	ax,word ptr [bx]	; 180c:466f  SUB AX,word ptr [BX]
	dec	ax	; 180c:4671  DEC AX
	jmp	short L_0712	; 180c:4672  JMP 0x1000:c73f
L_0707:
_rotblit_step3_oct3:				; 180c:4674 -> g_apRotBlitStep3FpTable[3]
	mov	bx,word ptr [bp + 6h]	; 180c:4674  MOV BX,word ptr [BP + 0x6]
	mov	ax,word ptr [bx + 6h]	; 180c:4677  MOV AX,word ptr [BX + 0x6]
	sub	ax,word ptr [bp + 0f954h]	; 180c:467a  SUB AX,word ptr [BP + 0xf954]
	dec	ax	; 180c:467e  DEC AX
L_0712:
	mov	word ptr [bp + 0f95eh],ax	; 180c:467f  MOV word ptr [BP + 0xf95e],AX
	mov	ax,cx	; 180c:4683  MOV AX,CX
	add	ax,dx	; 180c:4685  ADD AX,DX
	cmp	ax,word ptr [_g_graphics_context.nClip_xmax]	; 180c:4687  CMP AX,word ptr [0x2016]
	jle	L_0728	; 180c:468b  JLE 0x1000:c755
	mov	ax,word ptr [_g_graphics_context.nClip_xmax]	; 180c:468d  MOV AX,[0x2016]
	sub	ax,dx	; 180c:4690  SUB AX,DX
	inc	ax	; 180c:4692  INC AX
	mov	cx,ax	; 180c:4693  MOV CX,AX
L_0728:
	xor	bx,bx	; 180c:4695  XOR BX,BX
	mov	ax,dx	; 180c:4697  MOV AX,DX
	sub	ax,word ptr [_g_graphics_context.nClip_xmin]	; 180c:4699  SUB AX,word ptr [0x2014]
	jge	L_073a	; 180c:469d  JGE 0x1000:c767
	neg	ax	; 180c:469f  NEG AX
	mov	bx,ax	; 180c:46a1  MOV BX,AX
	add	dx,bx	; 180c:46a3  ADD DX,BX
	sub	cx,bx	; 180c:46a5  SUB CX,BX
L_073a:
	; Emit one clipped horizontal span of this scanline through the active
	; renderer's blit slot (g_renderer_vtable+0x90, an indirect far call).
	; Args: ptr into the rotated X-source table, the per-row destination
	; offset from pRow_offset_lut[scanline], and the source image descriptor.
	or	cx,cx	; 180c:46a7  span width <= 0?
	jle	L_0759	; 180c:46a9  yes -> skip this scanline
	shl	bx,1h	; 180c:46ab  src-table index * 2
	add	bx,offset DGROUP:_g_aStretchXSrcTable	; 180c:46ad  -> &g_aStretchXSrcTable[i]
	push	bx	; 180c:46b1
	shl	si,1h	; 180c:46b2  scanline * 2
	mov	di,word ptr [si + offset DGROUP:_g_pRow_offset_lut]	; 180c:46b4  DI = row dst offset
	push	word ptr [bp + 0f95eh]	; 180c:46b8
	push	word ptr [bp + 6h]	; 180c:46bc  src image descriptor
	call	dword ptr [_g_renderer_vtable + 090h]	; 180c:46bf  CALLF renderer blit slot
	add	sp,6h	; 180c:46c3
L_0759:
	add	word ptr [bp + 0f94ah],2h	; 180c:46c6  ADD word ptr [BP + 0xf94a],0x2
L_075e:
	mov	si,word ptr [bp + 0ah]	; 180c:46cb  MOV SI,word ptr [BP + 0xa]
	inc	si	; 180c:46ce  INC SI
	cmp	si,word ptr [bp + 0f94eh]	; 180c:46cf  CMP SI,word ptr [BP + 0xf94e]
	jge	L_076b	; 180c:46d3  JGE 0x1000:c798
	jmp	L_0662	; 180c:46d5  JMP 0x1000:c68f
L_076b:
	mov	bx,word ptr [_g_wRotBlitIdxBottom]	; 180c:46d8  MOV BX,word ptr [0x2f5e]
	mov	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:46dc  MOV AX,word ptr [BX + 0x2f54]
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]	; 180c:46e0  MOV BX,word ptr [0x2f62]
	sub	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:46e4  SUB AX,word ptr [BX + 0x2f54]
	push	ax	; 180c:46e8  PUSH AX
	xor	ax,ax	; 180c:46e9  XOR AX,AX
	lea	bx,[bp + 0f942h]	; 180c:46eb  LEA BX,[BP + 0xf942]
	mov	word ptr [bx + 2h],ax	; 180c:46ef  MOV word ptr [BX + 0x2],AX
	mov	ax,word ptr [bp + 0f938h]	; 180c:46f2  MOV AX,word ptr [BP + 0xf938]
	mov	word ptr [bx + 6h],ax	; 180c:46f6  MOV word ptr [BX + 0x6],AX
	push	bx	; 180c:46f9  PUSH BX
	call	_stretch_step_init	; 180c:46fa  CALL 0x1000:9731 (90 0e e8 after backward collapse)
	add	sp,4h	; 180c:46ff  ADD SP,0x4
	mov	bx,word ptr [_g_wRotBlitIdxBottom]	; 180c:4702  MOV BX,word ptr [0x2f5e]
	mov	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:4706  MOV AX,word ptr [BX + 0x2f54]
	mov	word ptr [bp + 0f94eh],ax	; 180c:470a  MOV word ptr [BP + 0xf94e],AX
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]	; 180c:470e  MOV BX,word ptr [0x2f62]
	mov	si,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:4712  MOV SI,word ptr [BX + 0x2f54]
	cmp	si,word ptr [bp + 0f94eh]	; 180c:4716  CMP SI,word ptr [BP + 0xf94e]
	jl	L_07b2	; 180c:471a  JL 0x1000:c7df
	jmp	L_08bc	; 180c:471c  JMP 0x1000:c8e9
L_07b2:
	mov	word ptr [bp + 0ah],si	; 180c:471f  MOV word ptr [BP + 0xa],SI
	lea	bx,[bp + 0f942h]	; 180c:4722  LEA BX,[BP + 0xf942]
	mov	ax,word ptr [bx + 2h]	; 180c:4726  MOV AX,word ptr [BX + 0x2]
	mov	word ptr [bp + 0f954h],ax	; 180c:4729  MOV word ptr [BP + 0xf954],AX
	mov	ax,word ptr [bx + 4h]	; 180c:472d  MOV AX,word ptr [BX + 0x4]
	mov	dx,word ptr [bx + 6h]	; 180c:4730  MOV DX,word ptr [BX + 0x6]
	add	word ptr [bx],ax	; 180c:4733  ADD word ptr [BX],AX
	adc	word ptr [bx + 2h],dx	; 180c:4735  ADC word ptr [BX + 0x2],DX
	cmp	si,word ptr [bp + 0f952h]	; 180c:4738  CMP SI,word ptr [BP + 0xf952]
	jge	L_07d4	; 180c:473c  JGE 0x1000:c801
	jmp	L_08af	; 180c:473e  JMP 0x1000:c8dc
L_07d4:
	cmp	si,word ptr [_g_graphics_context.nClip_ymin]	; 180c:4741  CMP SI,word ptr [0x2018]
	jge	L_07dd	; 180c:4745  JGE 0x1000:c80a
	jmp	L_08aa	; 180c:4747  JMP 0x1000:c8d7
L_07dd:
	cmp	si,word ptr [_g_graphics_context.nClip_ymax]	; 180c:474a  CMP SI,word ptr [0x201a]
	jle	L_07e6	; 180c:474e  JLE 0x1000:c813
	jmp	L_08aa	; 180c:4750  JMP 0x1000:c8d7
L_07e6:
	mov	bx,word ptr [bp + 0f94ah]	; 180c:4753  MOV BX,word ptr [BP + 0xf94a]
	mov	ax,word ptr [bx]	; 180c:4757  MOV AX,word ptr [BX]
	mov	dx,ax	; 180c:4759  MOV DX,AX
	mov	bx,word ptr [_g_wRotBlitIdxNextCW]	; 180c:475b  MOV BX,word ptr [0x2f60]
	mov	ax,word ptr [bx + offset DGROUP:_g_anRotBlitVertY]	; 180c:475f  MOV AX,word ptr [BX + 0x2f54]
	dec	ax	; 180c:4763  DEC AX
	cmp	si,ax	; 180c:4764  CMP SI,AX
	jg	L_080b	; 180c:4766  JG 0x1000:c838
	mov	ax,word ptr [bp + 0f936h]	; 180c:4768  MOV AX,word ptr [BP + 0xf936]
	shl	ax,1h	; 180c:476c  SHL AX,0x1
	lea	bx,[bp + 0fafch]	; 180c:476e  LEA BX,[BP + 0xfafc]
	add	bx,ax	; 180c:4772  ADD BX,AX
	mov	ax,word ptr [bx]	; 180c:4774  MOV AX,word ptr [BX]
	jmp	short L_081d	; 180c:4776  JMP 0x1000:c84a
L_080b:
	mov	ax,word ptr [bp + 0f938h]	; 180c:4778  MOV AX,word ptr [BP + 0xf938]
	sub	ax,word ptr [bp + 0f954h]	; 180c:477c  SUB AX,word ptr [BP + 0xf954]
	shl	ax,1h	; 180c:4780  SHL AX,0x1
	lea	bx,[bp + 0fd7ch]	; 180c:4782  LEA BX,[BP + 0xfd7c]
	add	bx,ax	; 180c:4786  ADD BX,AX
	mov	ax,word ptr [bx]	; 180c:4788  MOV AX,word ptr [BX]
L_081d:
	mov	cx,ax	; 180c:478a  MOV CX,AX
	jmp	word ptr [_g_pRotBlitStep4Fp]	; 180c:478c  JMP word ptr [0x2f82]
L_0823:
_rotblit_step4_oct0:				; 180c:4790 -> g_apRotBlitStep4FpTable[0]
	mov	ax,word ptr [bp + 0faf0h]	; 180c:4790  MOV AX,word ptr [BP + 0xfaf0]
	mov	bx,word ptr [bp + 6h]	; 180c:4794  MOV BX,word ptr [BP + 0x6]
	sub	ax,word ptr [bx + 6h]	; 180c:4797  SUB AX,word ptr [BX + 0x6]
	add	ax,word ptr [bp + 0f954h]	; 180c:479a  ADD AX,word ptr [BP + 0xf954]
	jmp	short L_0863	; 180c:479e  JMP 0x1000:c890
L_0833:
_rotblit_step4_oct1:				; 180c:47a0 -> g_apRotBlitStep4FpTable[1]
	mov	ax,word ptr [bp + 0f954h]	; 180c:47a0  MOV AX,word ptr [BP + 0xf954]
	shl	ax,1h	; 180c:47a4  SHL AX,0x1
	lea	bx,[bp + 0f960h]	; 180c:47a6  LEA BX,[BP + 0xf960]
	add	bx,ax	; 180c:47aa  ADD BX,AX
	mov	ax,word ptr [bp + 0faf0h]	; 180c:47ac  MOV AX,word ptr [BP + 0xfaf0]
	sub	ax,word ptr [bx]	; 180c:47b0  SUB AX,word ptr [BX]
	dec	ax	; 180c:47b2  DEC AX
	jmp	short L_0863	; 180c:47b3  JMP 0x1000:c890
L_0848:
_rotblit_step4_oct2:				; 180c:47b5 -> g_apRotBlitStep4FpTable[2]
	mov	bx,word ptr [bp + 6h]	; 180c:47b5  MOV BX,word ptr [BP + 0x6]
	mov	ax,word ptr [bx + 6h]	; 180c:47b8  MOV AX,word ptr [BX + 0x6]
	sub	ax,word ptr [bp + 0f954h]	; 180c:47bb  SUB AX,word ptr [BP + 0xf954]
	dec	ax	; 180c:47bf  DEC AX
	jmp	short L_0863	; 180c:47c0  JMP 0x1000:c890
L_0855:
_rotblit_step4_oct3:				; 180c:47c2 -> g_apRotBlitStep4FpTable[3]
	mov	ax,word ptr [bp + 0f954h]	; 180c:47c2  MOV AX,word ptr [BP + 0xf954]
	shl	ax,1h	; 180c:47c6  SHL AX,0x1
	lea	bx,[bp + 0f960h]	; 180c:47c8  LEA BX,[BP + 0xf960]
	add	bx,ax	; 180c:47cc  ADD BX,AX
	mov	ax,word ptr [bx]	; 180c:47ce  MOV AX,word ptr [BX]
L_0863:
	mov	word ptr [bp + 0f95eh],ax	; 180c:47d0  MOV word ptr [BP + 0xf95e],AX
	mov	ax,cx	; 180c:47d4  MOV AX,CX
	add	ax,dx	; 180c:47d6  ADD AX,DX
	cmp	ax,word ptr [_g_graphics_context.nClip_xmax]	; 180c:47d8  CMP AX,word ptr [0x2016]
	jle	L_0879	; 180c:47dc  JLE 0x1000:c8a6
	mov	ax,word ptr [_g_graphics_context.nClip_xmax]	; 180c:47de  MOV AX,[0x2016]
	sub	ax,dx	; 180c:47e1  SUB AX,DX
	inc	ax	; 180c:47e3  INC AX
	mov	cx,ax	; 180c:47e4  MOV CX,AX
L_0879:
	xor	bx,bx	; 180c:47e6  XOR BX,BX
	mov	ax,dx	; 180c:47e8  MOV AX,DX
	sub	ax,word ptr [_g_graphics_context.nClip_xmin]	; 180c:47ea  SUB AX,word ptr [0x2014]
	jge	L_088b	; 180c:47ee  JGE 0x1000:c8b8
	neg	ax	; 180c:47f0  NEG AX
	mov	bx,ax	; 180c:47f2  MOV BX,AX
	add	dx,bx	; 180c:47f4  ADD DX,BX
	sub	cx,bx	; 180c:47f6  SUB CX,BX
L_088b:
	; Same clipped-span emit through the renderer blit slot as the upper
	; half (see L_073a above), for the lower half of the rotated quad.
	or	cx,cx	; 180c:47f8  span width <= 0?
	jle	L_08aa	; 180c:47fa  yes -> skip
	shl	bx,1h	; 180c:47fc  src-table index * 2
	add	bx,offset DGROUP:_g_aStretchXSrcTable	; 180c:47fe  -> &g_aStretchXSrcTable[i]
	push	bx	; 180c:4802
	shl	si,1h	; 180c:4803  scanline * 2
	mov	di,word ptr [si + offset DGROUP:_g_pRow_offset_lut]	; 180c:4805  DI = row dst offset
	push	word ptr [bp + 0f95eh]	; 180c:4809
	push	word ptr [bp + 6h]	; 180c:480d  src image descriptor
	call	dword ptr [_g_renderer_vtable + 090h]	; 180c:4810  CALLF renderer blit slot
	add	sp,6h	; 180c:4814
L_08aa:
	add	word ptr [bp + 0f94ah],2h	; 180c:4817  ADD word ptr [BP + 0xf94a],0x2
L_08af:
	mov	si,word ptr [bp + 0ah]	; 180c:481c  MOV SI,word ptr [BP + 0xa]
	inc	si	; 180c:481f  INC SI
	cmp	si,word ptr [bp + 0f94eh]	; 180c:4820  CMP SI,word ptr [BP + 0xf94e]
	jge	L_08bc	; 180c:4824  JGE 0x1000:c8e9
	jmp	L_07b2	; 180c:4826  JMP 0x1000:c7df
L_08bc:
	call	_vga_reset_gc_default	; 180c:4829  CALL 0x1000:8b02 (90 0e e8 after backward collapse)
	pop	si	; 180c:482e  POP SI
	pop	di	; 180c:482f  POP DI
	mov	sp,bp	; 180c:4830  MOV SP,BP
	pop	bp	; 180c:4832  POP BP
	retf	; 180c:4833  RETF
_jmp_via_2f48	endp

; ============================================================================
; read_4words_from_2tables (180c:4834, 0x1c8f4)  --  geometry read-back accessor
;
; The CONSUMER side of this module's producer/consumer pair: copies the four
; rotated corner coordinates the blitter last produced (from g_anRotBlitVert-
; {X,Y}, indexed by the four g_wRotBlitIdx* corner globals) out to four
; caller-supplied pointers. Reads each out-pointer from the stack via LODSW
; (SI walks [BP+6..BP+c]) and stores one vertex word through it.
;
; The blitter itself never calls this; the sole caller lives in segment 52d6
; (ttmscript_interpret_loop, TTM.C), hence the proc is far. Communication is purely through the
; shared private g_*RotBlit* DGROUP block.
;
; void read_4words_from_2tables(short *outX_opp, short *outY_top,
;                               short *outX_next, short *outY_bottom)
;   [BP+6]=a, [BP+8]=b, [BP+a]=c, [BP+c]=d
; ============================================================================
_read_4words_from_2tables	proc far
	push	bp
	mov	bp,sp
	push	si
	lea	si,[bp + 6]			; SI -> a on stack
	mov	bx,word ptr [_g_wRotBlitIdxOppCW]
	mov	dx,word ptr [bx + _g_anRotBlitVertX]
	lodsw					; AX = *a; SI += 2
	mov	bx,ax
	mov	word ptr [bx],dx		; *a = g_anRotBlitVertX[g_wRotBlitIdxOppCW]

	mov	bx,word ptr [_g_wRotBlitIdxTop]
	mov	dx,word ptr [bx + _g_anRotBlitVertY]
	lodsw					; AX = *b; SI += 2
	mov	bx,ax
	mov	word ptr [bx],dx		; *b = g_anRotBlitVertY[g_wRotBlitIdxTop]

	mov	bx,word ptr [_g_wRotBlitIdxNextCW]
	mov	dx,word ptr [bx + _g_anRotBlitVertX]
	lodsw					; AX = *c; SI += 2
	mov	bx,ax
	mov	word ptr [bx],dx		; *c = g_anRotBlitVertX[g_wRotBlitIdxNextCW]

	mov	bx,word ptr [_g_wRotBlitIdxBottom]
	mov	dx,word ptr [bx + _g_anRotBlitVertY]
	lodsw					; AX = *d; SI += 2
	mov	bx,ax
	mov	word ptr [bx],dx		; *d = g_anRotBlitVertY[g_wRotBlitIdxBottom]

	pop	si
	pop	bp
	retf
_read_4words_from_2tables	endp

S180C_TEXT	ends
	end
