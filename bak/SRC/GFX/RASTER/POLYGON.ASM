; ============================================================================
; POLYGON.ASM -- KRONDOR.EXE segment 0x180c polygon rasterizer state machine
; (180c:4ac9..5d80, linear 0x1cb89..0x1d32a, ten functions).
;
; The core 3D/2D polygon fill+outline pipeline: draw_polygon walks the clipped
; vertex chain and NEAR-calls draw_polygon_edges (outline) plus a Bresenham
; edge-walk state machine (state_machine_enter_state2_a/_b, rasterize_polygon_
; edge, rasterize_polygon_edge_steep/_steep_b) that fills the per-scanline
; edge-x table read by the Gouraud/dithered span fillers. The intra-segment
; calls are near calls (E8 xx xx).
;
;   4ac9  fill_spans_dispatch      (19 bytes)    far,  vtable slot 27 dispatcher
;   4adc  blit_rect_buf_dispatch   (19 bytes)    far,  vtable slot 23 dispatcher
;   4aef  draw_polygon                   (1074 bytes)    far,  the core rasterizer
;   4f21  draw_polygon_edges               (76 bytes)    near, outline walker
;   4f6d  state_machine_enter_state2_a     (27 bytes)    near, shallow-edge setup stub
;   4f89  rasterize_polygon_edge          (318 bytes)    near, Bresenham edge walk (6x/7x unrolled)
;   50c7  state_machine_enter_state2_b     (38 bytes)    near, diagonal-edge setup stub
;   50ee  rasterize_polygon_edge_steep    (187 bytes)    near, steep Bresenham walk (dec AX)
;   51a9  rasterize_polygon_edge_steep_b  (186 bytes)    near, steep Bresenham walk (inc AX)
;   526a  state_machine_disp_tbl_5d80    (2839 bytes)    near, 400x unrolled Gouraud span writer
;
; Register-convention architecture: every function below except draw_polygon's
; outer far entry runs on a REGISTER-IN calling convention with no stack frame
; -- BX/BP/CX/SI carry the edge endpoints, ES:DI the destination
; table/framebuffer pointer, and BP doubles as a loop counter in several of
; them. draw_polygon and draw_polygon_edges dispatch into the edge-walk state
; machine with plain NEAR CALLs; state_machine_enter_state2_a/_b are pure setup
; stubs that end in a tail JMP (no RET) straight into
; state_machine_disp_tbl_5d80's unrolled stub chain -- a computed-goto pattern.
; draw_polygon_edges and draw_polygon each reach out to draw_line via the
; intra-overlay NOP + PUSH CS + near CALL idiom (draw_line is `proc far`; PUSH
; CS supplies the return segment); draw_polygon additionally calls
; polygon_clip_viewport the same way. Both stay extrn'd below -- they are NOT
; members of this unit.
;
; LABEL COLLISIONS: state_machine_enter_state2_a, rasterize_polygon_edge,
; rasterize_polygon_edge_steep and rasterize_polygon_edge_steep_b each use the
; generic local label L_sorted (and the steep pair also share L_pos_dy/
; L_no_neg/L_carry/L_pre_main/L_main/L_done). TASM forbids duplicate labels
; within one module, so each is renamed with a proc-scoped prefix (L_enter2a_*,
; L_rpe_*, L_steep_*, L_steepb_*) at its point of use below.
;
; fill_spans_dispatch is the twin of blit_rect_buf_dispatch
; (same 19-byte frame/ES:SI-load/CALLF-through-slot shape, adjacent addresses).
; ============================================================================

	.286

	include	gfxctx.inc		; extrn _g_graphics_context:byte + field EQUs
					; (g_anPolygonX etc via GfxContext struc fields;
					; also nClip_ymin/nClip_ymax/bYResDoubled for
					; draw_polygon_edges' Y-doubled path)

	extrn	_g_renderer_vtable:byte		; RendererVtable in DGROUP (200B)
_g_pfn_fill_spans_dithered_modey equ _g_renderer_vtable + 06ch	; slot 27: fill_spans_dispatch + draw_polygon
; blit_rect_buf_dispatch calls slot 23 (blit_rect_buffer) directly at
; _g_renderer_vtable + 05ch -- see its CALLF below.

	; far callees NOT in this unit -- FAR calls; TLINK's backward far->near
	; collapse emits the 90 0e e8 (NOP + PUSH CS + near CALL) bytes
	extrn	_polygon_clip_viewport:far
	extrn	_draw_line:far

	; This module's own _DATA block (DG 0x3138..0x3152): the draw-polygon /
	; rasterizer edge-walk state words. Every symbol below is written+read ONLY
	; by this module's rasterizer body. All zero-init; even length (26B),
	; self-word-aligning. Ends at 0x3152 = DISSOLV.C's tap_table.
_DATA	segment word public 'DATA'

	public	_g_wDrawPolyTopVertexOff, _g_wDrawPolyBottomVertexOff
	public	_g_wDrawPolyChain1VertexCount, _g_wDrawPolyChain2VertexCount
	public	_g_wDrawPolyChainRemaining, _g_wDrawPolyEdgeWalkOff
	public	_g_wRasterEdgeColumnOff, _g_nDrawPolyLastVertexX, _g_nDrawPolyLastVertexY
	public	_g_wDrawPolySpanBufRetSeg, _g_wDrawPolyOutlineVertexCount
	public	_g_wDrawPolyClipReplayByteCount, _g_bRasterSpanDiStride
	public	_g_bDrawPolyReplayPending

_g_wDrawPolyTopVertexOff	dw	0	; DGROUP+0x3138 (2B) ushort
_g_wDrawPolyBottomVertexOff	dw	0	; DGROUP+0x313a (2B) ushort
_g_wDrawPolyChain1VertexCount	dw	0	; DGROUP+0x313c (2B) ushort
_g_wDrawPolyChain2VertexCount	dw	0	; DGROUP+0x313e (2B) ushort
_g_wDrawPolyChainRemaining	dw	0	; DGROUP+0x3140 (2B) ushort
_g_wDrawPolyEdgeWalkOff		dw	0	; DGROUP+0x3142 (2B) ushort
_g_wRasterEdgeColumnOff		dw	0	; DGROUP+0x3144 (2B) ushort
_g_nDrawPolyLastVertexX		dw	0	; DGROUP+0x3146 (2B) short
_g_nDrawPolyLastVertexY		dw	0	; DGROUP+0x3148 (2B) short
_g_wDrawPolySpanBufRetSeg	dw	0	; DGROUP+0x314a (2B) ushort
_g_wDrawPolyOutlineVertexCount	dw	0	; DGROUP+0x314c (2B) ushort
_g_wDrawPolyClipReplayByteCount	dw	0	; DGROUP+0x314e (2B) ushort
_g_bRasterSpanDiStride		db	0	; DGROUP+0x3150 (1B) byte
_g_bDrawPolyReplayPending	db	0	; DGROUP+0x3151 (1B) byte
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_fill_spans_dispatch
	public	_blit_rect_buf_dispatch
	public	_draw_polygon
	public	_draw_polygon_edges
	public	_state_machine_enter_state2_a
	public	_rasterize_polygon_edge
	public	_state_machine_enter_state2_b
	public	_rasterize_polygon_edge_steep
	public	_rasterize_polygon_edge_steep_b
	public	_state_machine_disp_tbl_5d80

; ----------------------------------------------------------------------------
; fill_spans_dispatch (180c:4ac9, linear 0x1cb89, 19 bytes)
;
; Resident host-side dispatcher for renderer-vtable slot 27 =
; fill_spans_dithered_modey. Takes a far pointer as two word args (off @ bp+6,
; seg @ bp+8), materializes it in the ES:SI register pair, and dispatches
; through g_renderer_vtable.pfn_fill_spans_dithered_modey (DGROUP+0x2b32 =
; vtable base 0x2ac6 + 0x6c) via an indirect far CALL. The slot callee reads
; its far-ptr operand from ES:SI, not from the stack. Twin of
; blit_rect_buf_dispatch below (slot 23).
;
; WHY ASM: the slot callee receives its argument in registers (ES:SI), NOT on
; the stack -- a register-IN protocol call with no C form. The DI push/pop is a
; callee-save pair even though only SI is used.
; ----------------------------------------------------------------------------

_fill_spans_dispatch	proc far
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	si,word ptr [bp+6]		; off  -> SI
	mov	es,word ptr [bp+8]		; seg  -> ES
	call	dword ptr [_g_pfn_fill_spans_dithered_modey]
	pop	di
	pop	si
	pop	bp
	retf
_fill_spans_dispatch	endp

; ----------------------------------------------------------------------------
; blit_rect_buf_dispatch (180c:4adc, linear 0x1cb9c, 19 bytes)
;
; Resident host-side dispatcher for renderer-vtable slot 23 = vga_blit_rect_buffer.
; Loads the single far-pointer arg into ES:SI and issues a far CALL through the
; g_renderer_vtable.pfn_blit_rect_buffer slot (DGROUP+0x2b22 = vtable base 0x2ac6 + 0x5c).
;
; WHY ASM: the slot callee receives its argument in registers (ES:SI), NOT on the
; stack, and the dispatch is a far CALL through a DGROUP function-pointer vector
; -- a register-IN calling convention with no C form.
; ----------------------------------------------------------------------------
_blit_rect_buf_dispatch PROC FAR
        push    bp
        mov     bp,sp
        push    si
        push    di
        mov     si,word ptr [bp+6]            ; far-ptr offset
        mov     es,word ptr [bp+8]            ; far-ptr segment
        call    dword ptr [_g_renderer_vtable + 05ch]
        pop     di
        pop     si
        pop     bp
        retf
_blit_rect_buf_dispatch ENDP

; ============================================================================
; draw_polygon (180c:4aef, linear 0x1cbaf, 1074 bytes)
;
; The core polygon rasterizer.  Copies the input vertex arrays (xs[], ys[],
; count) into the global scratch, calls polygon_clip_viewport to clip the
; polygon to the active clip rect, then walks active edges with the
; shallow/steep split to emit span entries, and dispatches each row through
; the installed scanline renderer at g_renderer_vtable.pfn_fill_spans_dithered_modey
; (or the textured one when draw_polygon_textured swapped it).  This is what
; every drawn polygon goes through.
;
; WHY ASM (not C): a register-intensive rasterizer with a complex edge-walk loop
; that keeps DX/BX/BP/CX for min/max tracking -- no C form matches its
; instruction schedule.
;
; Calling convention: proc far (ends with RETF).
; All near-call callees (draw_polygon_edges, state_machine_enter_state2_a/b,
; rasterize_polygon_edge, rasterize_polygon_edge_steep, rasterize_polygon_edge_steep_b)
; are intra-module near calls (E8 xx xx).
; Far callees (polygon_clip_viewport, draw_line) use the intra-overlay
; NOP + PUSH CS + near CALL idiom (PUSH CS supplies the return CS); both stay
; external singletons (see the module extrn block above).
; The vtable slot pfn_fill_spans_dithered_modey is called via
; CALLF dword ptr [_g_renderer_vtable + 06ch].
;
; DGROUP data: gfxctx interior fields (g_anPolygonX etc.) use the EQU aliases
; from gfxctx.inc so the fixup lands on _g_graphics_context.  Standalone
; polygon-rasterizer globals (g_wDrawPolyTopVertexOff etc.) use direct extrn
; references per the globals.h layout.
;
; int far draw_polygon(int count, int *xs, int *ys)
;   [BP+6] = count, [BP+8] = xs, [BP+0xA] = ys
; ============================================================================
_draw_polygon	proc far
	push	bp
	mov	bp,sp
	push	si
	push	di
	push	es
	sub	ax,ax
	mov	[_g_wDrawPolySpanBufRetSeg],ax
	mov	byte ptr [_g_bDrawPolyReplayPending],al
	mov	ax,ds
	mov	es,ax
	mov	ax,word ptr [bp+6h]
	or	ax,ax
	js	L_4b1f
	mov	word ptr [_g_graphics_context.nPolygonClipVertexCount],ax
	mov	cx,ax
	mov	si,word ptr [bp+8h]
	mov	di,offset DGROUP:_g_graphics_context.pPolygonX
	rep	movsw
	mov	cx,ax
	mov	si,word ptr [bp+0ah]
	mov	di,offset DGROUP:_g_graphics_context.pPolygonY
	rep	movsw
L_4b1f:
	cmp	ax,2h
	jg	L_4b35
	jl	L_4b32
L_4b26:
	mov	si,offset DGROUP:_g_graphics_context.pPolygonX
	mov	di,offset DGROUP:_g_graphics_context.pPolygonY
	mov	bp,1h
	call	_draw_polygon_edges
L_4b32:
	jmp	L_4ee8
L_4b35:
	mov	al,byte ptr [_g_graphics_context.bGfx_fill_enabled]
	or	al,al
	jnz	L_4b59
	mov	ax,word ptr [_g_graphics_context.nPolygonClipVertexCount]
	mov	bx,ax
	mov	bp,ax
	shl	bx,1h
	mov	si,offset DGROUP:_g_graphics_context.pPolygonX
	mov	di,offset DGROUP:_g_graphics_context.pPolygonY
	mov	ax,word ptr [si]
	mov	word ptr [bx+si],ax
	mov	ax,word ptr [di]
	mov	word ptr [bx+di],ax
	call	_draw_polygon_edges
	jmp	L_4ee8
L_4b59:
	mov	al,byte ptr [_g_graphics_context.bGfx_outline_color]
	cmp	al,byte ptr [_g_graphics_context.bGfx_fill_color]
	jz	L_4b85
	mov	ax,word ptr [_g_graphics_context.nPolygonClipVertexCount]
	mov	[_g_wDrawPolyOutlineVertexCount],ax
	mov	bx,ax
	dec	bx
	mov	si,offset DGROUP:_g_graphics_context.pPolygonX
	mov	di,offset DGROUP:_g_graphics_context.pPolygonXSaved
	lodsw
	stosw
	mov	cx,bx
	rep	movsw
	stosw
	mov	si,offset DGROUP:_g_graphics_context.pPolygonY
	mov	di,offset DGROUP:_g_graphics_context.pPolygonYSaved
	lodsw
	stosw
	mov	cx,bx
	rep	movsw
	stosw
L_4b85:
	mov	al,byte ptr [_g_graphics_context.bClip_enabled]
	or	al,al
	jz	L_4b91
	call	_polygon_clip_viewport		; 90 0e e8 after TLINK's backward far->near collapse
L_4b91:
	mov	ax,word ptr [_g_graphics_context.nPolygonClipVertexCount]
	cmp	ax,2h
	jz	L_4b26
	jl	L_4b32
	dec	ax
	shl	ax,1h
	mov	si,ax
	mov	ax,word ptr [_g_graphics_context.pPolygonY]
	mov	[_g_nDrawPolyLastVertexY],ax
	mov	dx,7fffh
	mov	bx,8001h
	mov	ax,word ptr [_g_graphics_context.pPolygonX]
	mov	[_g_nDrawPolyLastVertexX],ax
	mov	bp,dx
	mov	cx,bx
	sub	di,di
	sub	ax,ax
	mov	[_g_wDrawPolyTopVertexOff],ax
	mov	[_g_wDrawPolyBottomVertexOff],ax
L_4bc0:
	mov	ax,word ptr [si+_g_graphics_context.pPolygonY]
	cmp	ax,word ptr [_g_nDrawPolyLastVertexY]
	jnz	L_4bd8
	mov	ax,word ptr [si+_g_graphics_context.pPolygonX]
	cmp	ax,word ptr [_g_nDrawPolyLastVertexX]
	jz	L_4c19
	mov	ax,word ptr [si+_g_graphics_context.pPolygonY]
L_4bd8:
	mov	[_g_nDrawPolyLastVertexY],ax
	mov	word ptr [di+_g_graphics_context.pPolygonYClipped],ax
	cmp	ax,dx
	jg	L_4bf5
	jl	L_4beb
	cmp	word ptr [si+_g_graphics_context.pPolygonX],cx
	jle	L_4bf5
L_4beb:
	mov	word ptr [_g_wDrawPolyTopVertexOff],di
	mov	dx,ax
	mov	cx,word ptr [si+_g_graphics_context.pPolygonX]
L_4bf5:
	cmp	ax,bx
	jl	L_4c0b
	jg	L_4c01
	cmp	word ptr [si+_g_graphics_context.pPolygonX],bp
	jg	L_4c0b
L_4c01:
	mov	word ptr [_g_wDrawPolyBottomVertexOff],di
	mov	bx,ax
	mov	bp,word ptr [si+_g_graphics_context.pPolygonX]
L_4c0b:
	mov	ax,word ptr [si+_g_graphics_context.pPolygonX]
	mov	[_g_nDrawPolyLastVertexX],ax
	mov	word ptr [di+_g_graphics_context.pPolygonXClipped],ax
	add	di,2h
L_4c19:
	sub	si,2h
	jge	L_4bc0
	cmp	dx,bx
	jnz	L_4c61
L_4c22:
	mov	ax,word ptr [_g_graphics_context_render.wSpanTableBufSeg]
	mov	es,ax
	xor	di,di
	mov	si,di
	mov	al,byte ptr [_g_graphics_context.bGfx_fill_color]
	cmp	al,byte ptr [_g_graphics_context.bGfx_outline_color]
	jnz	L_4c52
	cmp	bx,dx
	jnz	L_4c52
	mov	ax,dx
	stosw
	mov	ax,1h
	stosw
	cmp	bp,cx
	jle	L_4c45
	xchg	bp,cx
L_4c45:
	mov	ax,bp
	stosw
	mov	ax,cx
	stosw
	call	dword ptr [_g_pfn_fill_spans_dithered_modey]
	jmp	L_4ee8
L_4c52:
	push	dx
	push	cx
	push	bx
	push	bp
	call	_draw_line			; 90 0e e8 after TLINK's backward far->near collapse
	add	sp,8h
L_4c5e:
	jmp	L_4ee8
L_4c61:
	mov	ax,di
	shr	ax,1h
	cmp	ax,2h
	jz	L_4c22
	jl	L_4c5e
	mov	cx,di
	mov	word ptr [_g_graphics_context.nPolygonClipVertexCount],ax
	mov	ax,ds
	mov	es,ax
	mov	ax,[_g_wDrawPolyTopVertexOff]
	mov	si,ax
	mov	di,si
	add	di,2h
	cmp	di,cx
	sbb	ax,ax
	and	di,ax
	mov	dx,word ptr [di+_g_graphics_context.pPolygonXClipped]
	sub	dx,word ptr [si+_g_graphics_context.pPolygonXClipped]
	mov	bp,word ptr [di+_g_graphics_context.pPolygonYClipped]
	sub	bp,word ptr [si+_g_graphics_context.pPolygonYClipped]
	jnz	L_4ca1
	inc	bp
	or	dx,dx
	mov	dx,7fffh
	jns	L_4ca1
	neg	dx
L_4ca1:
	mov	di,si
	sub	di,2h
	jge	L_4caa
	add	di,cx
L_4caa:
	mov	ax,word ptr [di+_g_graphics_context.pPolygonXClipped]
	sub	ax,word ptr [si+_g_graphics_context.pPolygonXClipped]
	mov	bx,word ptr [di+_g_graphics_context.pPolygonYClipped]
	sub	bx,word ptr [si+_g_graphics_context.pPolygonYClipped]
	jnz	L_4cc6
	inc	bx
	or	ax,ax
	mov	ax,8001h
	js	L_4cd0
	neg	ax
L_4cc6:
	or	ax,ax
	js	L_4cd0
	or	dx,dx
	jle	L_4d41
	jmp	short L_4cdb
L_4cd0:
	or	dx,dx
	jge	L_4d25
	neg	dx
	neg	ax
	xchg	ax,dx
	xchg	bp,bx
L_4cdb:
	mov	si,ax
	mov	di,dx
	sub	dx,dx
	div	bx
	xchg	ax,di
	mov	si,dx
	sub	dx,dx
	div	bp
	cmp	ax,di
	ja	L_4d25
	jc	L_4d41
	sub	ax,ax
	div	bp
	mov	di,ax
	sub	ax,ax
	mov	dx,si
	div	bx
	cmp	di,ax
	jc	L_4d41
	ja	L_4d25
	mov	byte ptr [_g_bDrawPolyReplayPending],1h
	mov	word ptr [_g_wDrawPolyClipReplayByteCount],cx
	mov	dx,cx
	mov	si,offset DGROUP:_g_graphics_context.pPolygonXClipped
	mov	di,offset DGROUP:_g_graphics_context.pPolygonXSaved
	shr	cx,1h
	rep	movsw
	mov	cx,dx
	mov	si,offset DGROUP:_g_graphics_context.pPolygonYClipped
	mov	di,offset DGROUP:_g_graphics_context.pPolygonYSaved
	shr	cx,1h
	rep	movsw
	mov	cx,dx
L_4d25:
	mov	si,offset DGROUP:_g_graphics_context.pPolygonXClipped
	mov	di,offset DGROUP:_g_graphics_context.pPolygonX
	mov	dx,cx
	shr	cx,1h
	rep	movsw
	mov	si,offset DGROUP:_g_graphics_context.pPolygonYClipped
	mov	di,offset DGROUP:_g_graphics_context.pPolygonY
	mov	cx,dx
	shr	cx,1h
	rep	movsw
	mov	cx,dx
	jmp	short L_4d7e
L_4d41:
	mov	dx,cx
	mov	si,offset DGROUP:_g_graphics_context.pPolygonXClipped
	mov	di,offset DGROUP:_g_graphics_context.pPolygonX
	add	di,dx
	shr	cx,1h
L_4d4d:
	lodsw
	dec	di
	dec	di
	mov	word ptr [di],ax
	loop	L_4d4d
	mov	si,offset DGROUP:_g_graphics_context.pPolygonYClipped
	mov	di,offset DGROUP:_g_graphics_context.pPolygonY
	add	di,dx
	mov	cx,dx
	shr	cx,1h
L_4d60:
	lodsw
	dec	di
	dec	di
	mov	word ptr [di],ax
	loop	L_4d60
	mov	cx,dx
	sub	dx,2h
	mov	ax,dx
	sub	ax,word ptr [_g_wDrawPolyTopVertexOff]
	mov	[_g_wDrawPolyTopVertexOff],ax
	mov	ax,dx
	sub	ax,word ptr [_g_wDrawPolyBottomVertexOff]
	mov	[_g_wDrawPolyBottomVertexOff],ax
L_4d7e:
	mov	ax,[_g_wDrawPolyBottomVertexOff]
	mov	bx,ax
	mov	dx,word ptr [bx+_g_graphics_context.pPolygonY]
	mov	ax,[_g_wDrawPolyTopVertexOff]
	mov	si,ax
	sub	di,di
	jmp	short L_4d99
L_4d90:
	add	si,2h
	cmp	si,cx
	sbb	ax,ax
	and	si,ax
L_4d99:
	mov	ax,word ptr [si+_g_graphics_context.pPolygonX]
	mov	word ptr [di+_g_graphics_context.pPolygonXClipped],ax
	mov	ax,word ptr [si+_g_graphics_context.pPolygonY]
	mov	word ptr [di+_g_graphics_context.pPolygonYClipped],ax
	add	di,2h
	cmp	ax,dx
	jl	L_4d90
	mov	ax,di
	shr	ax,1h
	mov	[_g_wDrawPolyChain1VertexCount],ax
	mov	ax,[_g_wDrawPolyTopVertexOff]
	mov	bx,ax
	mov	dx,word ptr [bx+_g_graphics_context.pPolygonY]
	mov	ax,[_g_wDrawPolyBottomVertexOff]
	mov	si,ax
	jmp	short L_4dd0
L_4dc7:
	add	si,2h
	cmp	si,cx
	sbb	ax,ax
	and	si,ax
L_4dd0:
	mov	ax,word ptr [si+_g_graphics_context.pPolygonX]
	mov	word ptr [di+_g_graphics_context.pPolygonXClipped],ax
	mov	ax,word ptr [si+_g_graphics_context.pPolygonY]
	mov	word ptr [di+_g_graphics_context.pPolygonYClipped],ax
	add	di,2h
	cmp	ax,dx
	jg	L_4dc7
	mov	ax,di
	shr	ax,1h
	sub	ax,word ptr [_g_wDrawPolyChain1VertexCount]
	mov	[_g_wDrawPolyChain2VertexCount],ax
	mov	ax,word ptr [_g_graphics_context_render.wSpanTableBufSeg]
	mov	es,ax
	mov	word ptr [_g_wRasterEdgeColumnOff],2h
	mov	word ptr [_g_wDrawPolyEdgeWalkOff],0h
	mov	ax,[_g_wDrawPolyChain1VertexCount]
	jmp	short L_4e0b
L_4e08:
	mov	ax,[_g_wDrawPolyChainRemaining]
L_4e0b:
	dec	ax
	jz	L_4e86
	mov	[_g_wDrawPolyChainRemaining],ax
	mov	ax,[_g_wDrawPolyEdgeWalkOff]
	mov	si,ax
	add	ax,2h
	mov	[_g_wDrawPolyEdgeWalkOff],ax
	mov	ax,word ptr [si+_g_graphics_context.pPolygonXClipped]
	mov	bx,ax
	mov	bp,word ptr [si+_g_graphics_context.pPolygonXClipped+2]
	mov	cx,word ptr [si+_g_graphics_context.pPolygonYClipped]
	mov	si,word ptr [si+_g_graphics_context.pPolygonYClipped+2]
	sub	ax,bp
	cwd
	xor	ax,dx
	sub	ax,dx
	jz	L_4e4f
	mov	di,ax
	mov	ax,cx
	sub	ax,si
	cwd
	xor	ax,dx
	sub	ax,dx
	jz	L_4e54
	cmp	di,ax
	jl	L_4e81
	jg	L_4e70
	call	_state_machine_enter_state2_b
	jmp	short L_4e08
L_4e4f:
	call	_state_machine_enter_state2_a
	jmp	short L_4e08
L_4e54:
	cmp	bx,bp
	jl	L_4e5a
	xchg	bx,bp
L_4e5a:
	mov	di,cx
	shl	di,1h
	shl	di,1h
	mov	ax,[_g_wRasterEdgeColumnOff]
	add	di,ax
	or	ax,ax
	mov	ax,bx
	jz	L_4e6d
	mov	ax,bp
L_4e6d:
	stosw
	jmp	short L_4e08
L_4e70:
	cmp	word ptr [_g_wRasterEdgeColumnOff],0h
	jnz	L_4e7c
	call	_rasterize_polygon_edge_steep_b
	jmp	short L_4e08
L_4e7c:
	call	_rasterize_polygon_edge_steep
	jmp	short L_4e08
L_4e81:
	call	_rasterize_polygon_edge
	jmp	short L_4e08
L_4e86:
	mov	ax,[_g_wRasterEdgeColumnOff]
	or	ax,ax
	jz	L_4e9d
	add	word ptr [_g_wDrawPolyEdgeWalkOff],2h
	sub	ax,ax
	mov	[_g_wRasterEdgeColumnOff],ax
	mov	ax,[_g_wDrawPolyChain2VertexCount]
	jmp	L_4e0b
L_4e9d:
	mov	ax,[_g_wDrawPolyTopVertexOff]
	mov	bx,ax
	mov	ax,word ptr [bx+_g_graphics_context.pPolygonY]
	mov	dx,ax
	shl	ax,1h
	shl	ax,1h
	mov	si,ax
	mov	word ptr [_g_wDrawPolySpanBufRetSeg],es
	mov	ax,[_g_wDrawPolyBottomVertexOff]
	mov	bx,ax
	mov	ax,word ptr [bx+_g_graphics_context.pPolygonY]
	sub	ax,dx
	inc	ax
	mov	cx,es
	dec	cx
	mov	es,cx
	add	si,0ch
	mov	word ptr es:[si],dx
	mov	word ptr es:[si+2h],ax
	call	dword ptr [_g_pfn_fill_spans_dithered_modey]
	mov	al,byte ptr [_g_graphics_context.bGfx_outline_color]
	cmp	al,byte ptr [_g_graphics_context.bGfx_fill_color]
	jz	L_4ee8
	mov	ax,[_g_wDrawPolyOutlineVertexCount]
	mov	bp,ax
	mov	si,offset DGROUP:_g_graphics_context.pPolygonXSaved
	mov	di,offset DGROUP:_g_graphics_context.pPolygonYSaved
	call	_draw_polygon_edges
L_4ee8:
	mov	al,byte ptr [_g_bDrawPolyReplayPending]
	or	al,al
	jz	L_4f19
	mov	byte ptr [_g_bDrawPolyReplayPending],0h
	mov	ax,ds
	mov	es,ax
	mov	cx,word ptr [_g_wDrawPolyClipReplayByteCount]
	mov	dx,cx
	mov	si,offset DGROUP:_g_graphics_context.pPolygonXSaved
	mov	di,offset DGROUP:_g_graphics_context.pPolygonXClipped
	shr	cx,1h
	rep	movsw
	mov	cx,dx
	mov	si,offset DGROUP:_g_graphics_context.pPolygonYSaved
	mov	di,offset DGROUP:_g_graphics_context.pPolygonYClipped
	shr	cx,1h
	rep	movsw
	mov	cx,dx
	jmp	L_4d41
L_4f19:
	mov	ax,[_g_wDrawPolySpanBufRetSeg]
	pop	es
	pop	di
	pop	si
	pop	bp
	retf
_draw_polygon	endp

; ----------------------------------------------------------------------------
; draw_polygon_edges @ 180c:4f21 (linear 0x1cfe1, 76 bytes)
;
; Draws the outline of the current polygon by calling draw_line for each
; adjacent vertex pair (N -> N+1).  When the vertical-resolution-doubled flag
; (g_bYResDoubled) is set, halves all Y coordinates and Y-clip bounds for the
; duration so an internal 2x-Y rendering looks correct on screen.
;
; WHY ASM: pure register-IN calling convention -- no prologue, no stack frame.
;   SI: pointer to X-coordinate array  (advances via LODSW)
;   DI: pointer to Y-coordinate array  (advances manually)
;   BP: loop count (edge count)
; None of these map to C parameter slots; the entire function is inexpressible
; as Borland C++ (any frame would clobber BP immediately).
; draw_line is called via the intra-overlay NOP; PUSH CS; CALL near idiom
; (draw_line is `proc far`; PUSH CS supplies the return segment); it stays an
; external singleton (see the module extrn block above).
; ----------------------------------------------------------------------------
_draw_polygon_edges	proc near
	cmp	byte ptr [_g_graphics_context.bYResDoubled],0h		; +0x00  if bYResDoubled == 0 ...
	jnz	L_doubled				; +0x05  ... else halve Y coords

; ------ non-doubled path: draw each edge at full resolution ------
L_loop_normal:
	push	word ptr [di]				; +0x07  y2 = Y[i]
	lodsw						; +0x09  AX = X[i], SI += 2
	push	ax					; +0x0a  x2 = X[i]
	add	di,2h					; +0x0b  DI -> Y[i+1]
	push	word ptr [di]				; +0x0e  y1 = Y[i+1]
	push	word ptr [si]				; +0x10  x1 = X[i+1]
	call	_draw_line				; +0x12  draw_line(x1,y1,x2,y2); 90 0e e8 after collapse
	add	sp,8h					; +0x17  clean 4 args
	dec	bp					; +0x1a  --count
	jnz	L_loop_normal				; +0x1b  loop
	ret						; +0x1d

; ------ doubled path: halve Y coords and clip bounds ------
L_doubled:
	shr	word ptr [_g_graphics_context.nClip_ymin],1h		; +0x1e  ymin >>= 1
	shr	word ptr [_g_graphics_context.nClip_ymax],1h		; +0x22  ymax >>= 1
L_loop_doubled:
	mov	ax,word ptr [di]			; +0x26  AX = Y[i]
	add	di,2h					; +0x28  DI -> Y[i+1]
	sar	ax,1h					; +0x2b  y2 = Y[i] / 2 (signed)
	push	ax					; +0x2d
	lodsw						; +0x2e  AX = X[i], SI += 2
	push	ax					; +0x2f  x2 = X[i]
	mov	ax,word ptr [di]			; +0x30  AX = Y[i+1]
	sar	ax,1h					; +0x32  y1 = Y[i+1] / 2 (signed)
	push	ax					; +0x34
	mov	ax,word ptr [si]			; +0x35  x1 = X[i+1]
	push	ax					; +0x37
	call	_draw_line				; +0x38  draw_line(x1,y1,x2,y2); 90 0e e8 after collapse
	add	sp,8h					; +0x3d
	dec	bp					; +0x40
	jnz	L_loop_doubled				; +0x41  loop
	shl	word ptr [_g_graphics_context.nClip_ymin],1h		; +0x43  restore ymin
	shl	word ptr [_g_graphics_context.nClip_ymax],1h		; +0x47  restore ymax
	ret						; +0x4b
_draw_polygon_edges	endp

; ----------------------------------------------------------------------------
; state_machine_enter_state2_a (180c:4f6d, linear 0x1d02d, 27 bytes)
;
; void state_machine_enter_state2_a(void)
;
; Register-convention NEAR function (no stack args, no frame, ends in JMP).
; Inputs (all via registers):
;   CX, SI = two scanline y-coordinates (sorted so SI <= CX after entry)
;   BP     = fractional accumulator initial value (passed through as AX to callee)
;   BX     = zeroed before tail-call
;
; This is a pre-dispatch setup stub for the Gouraud rasterizer:
;   1. Sort SI,CX so SI <= CX (XCHG if CX > SI)
;   2. Compute DI = min(SI,CX); CX = (max - min) + 1 (pixel span count)
;   3. Set g_bRasterSpanDiStride = 2 (stride = 2: normal horizontal step)
;   4. Save incoming BP into AX; zero BX, SI, BP
;   5. Tail-call state_machine_disp_tbl_5d80 (near JMP, intra-module, E9 xx xx)
;
; WHY ASM (not C): register-IN calling convention; CX/SI/BP are live inputs with
; no stack parameters, and the function ends in a near JMP tail-call, not a
; RET/RETF. The caller sets up registers directly before jumping here.
;
; LABEL RENAME: the generic label L_sorted collides with the same name in
; rasterize_polygon_edge/rasterize_polygon_edge_steep/_steep_b in this module,
; so it is renamed L_enter2a_sorted here.
; ----------------------------------------------------------------------------
_state_machine_enter_state2_a proc near
; 180c:4f6d  CMP CX,SI
        cmp     cx,si
; 180c:4f6f  JG L_enter2a_sorted (skip XCHG)
        jg      L_enter2a_sorted
; 180c:4f71  XCHG SI,CX  (encoding: 87 CE = rm=SI,reg=CX; swap so SI <= CX)
        xchg    cx,si
; 180c:4f73  MOV DI,SI   (DI = min value)
L_enter2a_sorted:
        mov     di,si
; 180c:4f75  SUB CX,SI
        sub     cx,si
; 180c:4f77  INC CX      (span count = max-min+1)
        inc     cx
; 180c:4f78  MOV byte ptr [g_bRasterSpanDiStride],2
        mov     byte ptr [_g_bRasterSpanDiStride],2
; 180c:4f7d  MOV AX,BP   (save BP in AX for callee)
        mov     ax,bp
; 180c:4f7f  SUB BX,BX
        sub     bx,bx
; 180c:4f81  MOV SI,BX
        mov     si,bx
; 180c:4f83  MOV BP,BX
        mov     bp,bx
; 180c:4f85  JMP state_machine_disp_tbl_5d80
        jmp     _state_machine_disp_tbl_5d80

_state_machine_enter_state2_a endp

	ret

; ----------------------------------------------------------------------------
; rasterize_polygon_edge  (180c:4f89, linear 0x1d049, 318 bytes)
;
; Bresenham polygon-edge rasterizer. Steps from y_min to y_max and writes the
; current x value into the per-row edge-x table via ES:DI. Uses g_wRasterEdgeColumnOff
; as the table base offset. The main loop body is unrolled: 6x for the negative
; x-delta path (STOSW+INC+INC, DI advances +4/row) and 7x for the non-negative
; x-delta path (STOSW+ADD -6, DI advances -4/row).
;
; WHY ASM: register-IN/OUT convention; no stack args:
;   BX=y_bot, BP=y_top, CX=x1, SI=x2, ES:DI=edge-table base
;   Terminates with near RET.
;
; LABEL RENAME: L_sorted -> L_rpe_sorted (collides with the same generic name in
; state_machine_enter_state2_a and the two steep-edge rasterizers below).
; ----------------------------------------------------------------------------
_rasterize_polygon_edge	proc near
	; 180c:4f89  CMP BX,BP
	; 180c:4f8b  JL L_rpe_sorted
	; 180c:4f8d  XCHG BP,BX
	; 180c:4f8f  XCHG SI,CX
	cmp	bx,bp
	jl	L_rpe_sorted
	xchg	bx,bp
	xchg	cx,si
L_rpe_sorted:
	; 180c:4f91  MOV DI,CX
	; 180c:4f93  SHL DI,1
	; 180c:4f95  SHL DI,1
	; 180c:4f97  MOV AX,[0x3144]
	; 180c:4f9a  ADD DI,AX
	mov	di,cx
	shl	di,1
	shl	di,1
	mov	ax,[_g_wRasterEdgeColumnOff]
	add	di,ax
	; 180c:4f9c  MOV AX,CX
	; 180c:4f9e  SUB AX,SI
	; 180c:4fa0  CWD
	; 180c:4fa1  XOR AX,DX
	; 180c:4fa3  SUB AX,DX
	; 180c:4fa5  MOV CX,AX
	mov	ax,cx
	sub	ax,si
	cwd
	xor	ax,dx
	sub	ax,dx
	mov	cx,ax
	; 180c:4fa7  MOV AX,BP
	; 180c:4fa9  SUB AX,BX
	; 180c:4fab  MOV SI,AX
	; 180c:4fad  SHL SI,1
	; 180c:4faf  MOV BP,AX
	; 180c:4fb1  MOV AX,BX
	; 180c:4fb3  MOV BX,SI
	; 180c:4fb5  SUB BX,CX
	; 180c:4fb7  SUB BP,CX
	; 180c:4fb9  SHL BP,1
	; 180c:4fbb  XOR BP,SI
	; 180c:4fbd  INC CX
	; 180c:4fbe  OR DX,DX
	; 180c:4fc0  JZ L_nonneg
	mov	ax,bp
	sub	ax,bx
	mov	si,ax
	shl	si,1
	mov	bp,ax
	mov	ax,bx
	mov	bx,si
	sub	bx,cx
	sub	bp,cx
	shl	bp,1
	xor	bp,si
	inc	cx
	or	dx,dx
	jz	L_nonneg

	; -----------------------------------------------------------------------
	; Negative x-delta path (DX != 0): DI advances +4 per row
	; (STOSW increments DI by 2, then INC DI x2 adds 2 more = +4 total)
	; 6 iterations unrolled, then JMP back to loop top.
	; -----------------------------------------------------------------------
L_neg_loop:
	; iteration 1
	stosw
	inc	di
	inc	di
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_neg_ret
	; iteration 2
	stosw
	inc	di
	inc	di
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_neg_ret
	; iteration 3
	stosw
	inc	di
	inc	di
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_neg_ret
	; iteration 4
	stosw
	inc	di
	inc	di
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_neg_ret
	; iteration 5
	stosw
	inc	di
	inc	di
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_neg_ret
	; iteration 6
	stosw
	inc	di
	inc	di
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_neg_ret
	jmp	short L_neg_loop
L_neg_ret:
	ret

	; -----------------------------------------------------------------------
	; Non-negative x-delta path (DX == 0): DI advances -4 per row
	; (STOSW increments DI by 2, then ADD DI,-6 subtracts 6 = net -4)
	; 7 iterations unrolled, then JMP back to loop top.
	; -----------------------------------------------------------------------
L_nonneg:
	; iteration 1
	stosw
	add	di,-6
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_nonneg_ret
	; iteration 2
	stosw
	add	di,-6
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_nonneg_ret
	; iteration 3
	stosw
	add	di,-6
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_nonneg_ret
	; iteration 4
	stosw
	add	di,-6
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_nonneg_ret
	; iteration 5
	stosw
	add	di,-6
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_nonneg_ret
	; iteration 6
	stosw
	add	di,-6
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_nonneg_ret
	; iteration 7
	stosw
	add	di,-6
	cmp	bh,80h
	sbb	dx,dx
	sub	ax,dx
	and	dx,bp
	xor	dx,si
	add	bx,dx
	dec	cx
	jz	L_nonneg_ret
	jmp	L_nonneg
L_nonneg_ret:
	ret
_rasterize_polygon_edge	endp

; ----------------------------------------------------------------------------
; state_machine_enter_state2_b  (180c:50c7, linear 0x1d187, 38 bytes)
;
; State machine line-drawing setup for a diagonal raster span.
; Computes step count and direction from register inputs (CX/SI = x-coords,
; BX/BP = y-coords), then sets g_bRasterSpanDiStride = 2 and tail-dispatches
; to state_machine_disp_tbl_5d80.
;
; WHY ASM: register-convention function -- no stack frame, takes inputs in
; CX/SI (x1/x2) and BX/BP (y1/y2), tail-jumps to the dispatch table.
; No RET instruction: ends with a near JMP within S180C_TEXT (intra-module,
; E9 xx xx).
; ----------------------------------------------------------------------------
_state_machine_enter_state2_b	proc near
	cmp	cx, si
	jl	LAB_50cf
	xchg	bx, bp
	xchg	cx, si
LAB_50cf:
	mov	di, cx
	sub	cx, si
	neg	cx
	inc	cx
	mov	si, 1
	cmp	bx, bp
	jl	LAB_50df
	neg	si
LAB_50df:
	mov	ax, bx
	sub	bx, bx
	mov	bp, bx
	mov	byte ptr [_g_bRasterSpanDiStride], 2
	jmp	_state_machine_disp_tbl_5d80
_state_machine_enter_state2_b	endp

	ret

; ----------------------------------------------------------------------------
; rasterize_polygon_edge_steep (180c:50ee, linear 0x1d1ae, 187 bytes)
;
; void rasterize_polygon_edge_steep(void)
;
; Register-convention NEAR function (no stack args, no frame, ends in RET).
; Inputs (all via registers):
;   BX = x1, BP = x0 (x endpoints)
;   CX = y1, SI = y0 (corresponding y values)
;   ES:DI = edge table (written via STOSW)
;
; Bresenham steep-edge rasterizer: sorts endpoints so BX<=BP, then walks
; the y axis with Bresenham, storing the current x value into ES:[DI] via
; STOSW for each step.  DX holds the stride adjustment (+2 or -6) for the
; reverse direction.
;
; WHY ASM (not C): register-IN/OUT calling convention; all arguments arrive
; in BX/BP/CX/SI/ES:DI.  No C prototype can express register-in parameters,
; and STOSW writes through ES:DI implicitly.  The caller passes values in
; registers, not on the stack.
;
; LABEL RENAMES (collide with the same generic names in
; state_machine_enter_state2_a, rasterize_polygon_edge, and
; rasterize_polygon_edge_steep_b below):
;   L_sorted -> L_steep_sorted     L_no_neg   -> L_steep_no_neg
;   L_pos_dy -> L_steep_pos_dy     L_pre_main -> L_steep_pre_main
;   L_carry  -> L_steep_carry      L_main     -> L_steep_main
;   L_done   -> L_steep_done
; ----------------------------------------------------------------------------
_rasterize_polygon_edge_steep PROC NEAR
; 180c:50ee  CMP BX,BP
        cmp     bx,bp
; 180c:50f0  JG L_steep_sorted (d1b6)
        jg      L_steep_sorted
; 180c:50f2  XCHG BP,BX  (encoding: 87 DD = rm=BP,reg=BX)
        xchg    bx,bp
; 180c:50f4  XCHG SI,CX  (encoding: 87 CE = rm=SI,reg=CX)
        xchg    cx,si
; 180c:50f6  MOV DI,CX   (label d1b6 = offset +8 from entry)
L_steep_sorted:
        mov     di,cx
; 180c:50f8  SHL DI,1
        shl     di,1
; 180c:50fa  INC DI
        inc     di
; 180c:50fb  SHL DI,1
        shl     di,1
; 180c:50fd  MOV DX,2
        mov     dx,2
; 180c:5100  SUB SI,CX
        sub     si,cx
; 180c:5102  JGE L_steep_pos_dy (d1c9)
        jge     L_steep_pos_dy
; 180c:5104  NEG SI
        neg     si
; 180c:5106  MOV DX,0xfffa  (-6)
        mov     dx,0fffah
; 180c:5109  MOV CX,SI  (label d1c9 = offset +0x1b from entry)
L_steep_pos_dy:
        mov     cx,si
; 180c:510b  SUB BP,BX
        sub     bp,bx
; 180c:510d  JLE L_steep_no_neg (d1d1)
        jle     L_steep_no_neg
; 180c:510f  NEG BP
        neg     bp
; 180c:5111  MOV AX,BP   (label d1d1 = offset +0x23 from entry)
L_steep_no_neg:
        mov     ax,bp
; 180c:5113  ADD BP,SI
        add     bp,si
; 180c:5115  SHL BP,1
        shl     bp,1
; 180c:5117  SHL SI,1
        shl     si,1
; 180c:5119  ADD AX,SI
        add     ax,si
; 180c:511b  XCHG AX,BX
        xchg    ax,bx
; 180c:511c  STOSW ES:DI   (AX -> ES:[DI]; DI += 2)
        stosw
; 180c:511d  ADD DI,DX
        add     di,dx
; 180c:511f  DEC AX
        dec     ax
; 180c:5120  OR BX,BX
        or      bx,bx
; 180c:5122  JL L_steep_carry (d1e6)
        jl      L_steep_carry
; 180c:5124  JMP L_steep_main (d214)  -- forward local jump, "short" required:
; TASM's default multi-pass sizing of an unqualified forward jmp inside this
; large module locks in the near (E9) form from an early pass and NOP-pads a
; short-range result down to 3 bytes on convergence instead of re-shrinking to
; 2; the target is EB 2E (short). Explicit "short" forces the 2-byte encoding.
        jmp     short L_steep_main

; Carry path: BX < 0, decrement AX multiple times until BX >= 0
; (label d1e6 = offset +0x38 from entry)
L_steep_carry:
; 180c:5126  DEC AX
        dec     ax
; 180c:5127  ADD BX,SI
        add     bx,si
; 180c:5129  JGE L_steep_main (d214)
        jge     L_steep_main
; 180c:512b  DEC AX
        dec     ax
; 180c:512c  ADD BX,SI
        add     bx,si
; 180c:512e  JGE L_steep_main (d214)
        jge     L_steep_main
; 180c:5130  DEC AX
        dec     ax
; 180c:5131  ADD BX,SI
        add     bx,si
; 180c:5133  JGE L_steep_main (d214)
        jge     L_steep_main
; 180c:5135  DEC AX
        dec     ax
; 180c:5136  ADD BX,SI
        add     bx,si
; 180c:5138  JGE L_steep_main (d214)
        jge     L_steep_main
; 180c:513a  DEC AX
        dec     ax
; 180c:513b  ADD BX,SI
        add     bx,si
; 180c:513d  JGE L_steep_main (d214)
        jge     L_steep_main
; 180c:513f  DEC AX
        dec     ax
; 180c:5140  ADD BX,SI
        add     bx,si
; 180c:5142  JGE L_steep_main (d214)
        jge     L_steep_main
; 180c:5144  DEC AX
        dec     ax
; 180c:5145  ADD BX,SI
        add     bx,si
; 180c:5147  JGE L_steep_main (d214)
        jge     L_steep_main
; 180c:5149  DEC AX
        dec     ax
; 180c:514a  ADD BX,SI
        add     bx,si
; 180c:514c  JGE L_steep_main (d214)
        jge     L_steep_main
; 180c:514e  JMP L_steep_carry (d1e6)
        jmp     L_steep_carry

; Pre-main: test accumulator before the main store loop
; (label d210 = offset +0x62 from entry)
L_steep_pre_main:
; 180c:5150  ADD BX,BP
        add     bx,bp
; 180c:5152  JL L_steep_carry (d1e6)
        jl      L_steep_carry

; Main store loop body
; (label d214 = offset +0x66 from entry)
L_steep_main:
; 180c:5154  STOSW ES:DI
        stosw
; 180c:5155  ADD DI,DX
        add     di,dx
; 180c:5157  DEC AX
        dec     ax
; 180c:5158  DEC CX
        dec     cx
; 180c:5159  JZ L_steep_done (d268)
        jz      L_steep_done
; 180c:515b  ADD BX,BP
        add     bx,bp
; 180c:515d  JL L_steep_carry (d1e6)
        jl      L_steep_carry
; 180c:515f  STOSW ES:DI
        stosw
; 180c:5160  ADD DI,DX
        add     di,dx
; 180c:5162  DEC AX
        dec     ax
; 180c:5163  DEC CX
        dec     cx
; 180c:5164  JZ L_steep_done (d268)
        jz      L_steep_done
; 180c:5166  ADD BX,BP
        add     bx,bp
; 180c:5168  JL L_steep_carry (d1e6)
        jl      L_steep_carry
; 180c:516a  STOSW ES:DI
        stosw
; 180c:516b  ADD DI,DX
        add     di,dx
; 180c:516d  DEC AX
        dec     ax
; 180c:516e  DEC CX
        dec     cx
; 180c:516f  JZ L_steep_done (d268)
        jz      L_steep_done
; 180c:5171  ADD BX,BP
        add     bx,bp
; 180c:5173  JL L_steep_carry (d1e6)
        jl      L_steep_carry
; 180c:5175  STOSW ES:DI
        stosw
; 180c:5176  ADD DI,DX
        add     di,dx
; 180c:5178  DEC AX
        dec     ax
; 180c:5179  DEC CX
        dec     cx
; 180c:517a  JZ L_steep_done (d268)
        jz      L_steep_done
; 180c:517c  ADD BX,BP
        add     bx,bp
; 180c:517e  JL L_steep_carry (d1e6)
        jl      L_steep_carry
; 180c:5180  STOSW ES:DI
        stosw
; 180c:5181  ADD DI,DX
        add     di,dx
; 180c:5183  DEC AX
        dec     ax
; 180c:5184  DEC CX
        dec     cx
; 180c:5185  JZ L_steep_done (d268)
        jz      L_steep_done
; 180c:5187  ADD BX,BP
        add     bx,bp
; 180c:5189  JL L_steep_carry (d1e6)
        jl      L_steep_carry
; 180c:518b  STOSW ES:DI
        stosw
; 180c:518c  ADD DI,DX
        add     di,dx
; 180c:518e  DEC AX
        dec     ax
; 180c:518f  DEC CX
        dec     cx
; 180c:5190  JZ L_steep_done (d268)
        jz      L_steep_done
; 180c:5192  ADD BX,BP
        add     bx,bp
; 180c:5194  JL L_steep_carry (d1e6)
        jl      L_steep_carry
; 180c:5196  STOSW ES:DI
        stosw
; 180c:5197  ADD DI,DX
        add     di,dx
; 180c:5199  DEC AX
        dec     ax
; 180c:519a  DEC CX
        dec     cx
; 180c:519b  JZ L_steep_done (d268)
        jz      L_steep_done
; 180c:519d  ADD BX,BP
        add     bx,bp
; 180c:519f  JL L_steep_carry (d1e6)
        jl      L_steep_carry
; 180c:51a1  STOSW ES:DI
        stosw
; 180c:51a2  ADD DI,DX
        add     di,dx
; 180c:51a4  DEC AX
        dec     ax
; 180c:51a5  DEC CX
        dec     cx
; 180c:51a6  JNZ L_steep_pre_main (d210)
        jnz     L_steep_pre_main
; 180c:51a8  RET
L_steep_done:
        ret

_rasterize_polygon_edge_steep ENDP

; ----------------------------------------------------------------------------
; rasterize_polygon_edge_steep_b (180c:51a9, linear 0x1d269, 186 bytes)
;
; void rasterize_polygon_edge_steep_b(void)
;
; Register-convention NEAR function (no stack args, no frame, ends in RET).
; Inputs (all via registers):
;   BX = x0, BP = x1 (x endpoints)
;   CX = y0, SI = y1 (corresponding y values)
;   ES:DI = edge table (written via STOSW)
;
; Companion to rasterize_polygon_edge_steep (steep_a, 0x1d1ae).
; Bresenham steep-edge rasterizer that increments x (INC AX) instead of
; decrementing (DEC AX) in the inner loop, for the opposite edge direction.
; Sorts endpoints so BX<=BP (JL: skip swap when already in order), walks
; the y axis with Bresenham, storing the current x into ES:[DI] via STOSW.
;
; WHY ASM (not C): register-IN/OUT calling convention; all arguments arrive
; in BX/BP/CX/SI/ES:DI.  No C prototype can express register-in parameters,
; and STOSW writes through ES:DI implicitly.  The caller passes values in
; registers, not on the stack.
;
; LABEL RENAMES (collide with the same generic names in
; state_machine_enter_state2_a, rasterize_polygon_edge, and
; rasterize_polygon_edge_steep above):
;   L_sorted -> L_steepb_sorted     L_no_neg   -> L_steepb_no_neg
;   L_pos_dy -> L_steepb_pos_dy     L_pre_main -> L_steepb_pre_main
;   L_carry  -> L_steepb_carry      L_main     -> L_steepb_main
;   L_done   -> L_steepb_done
; ----------------------------------------------------------------------------
_rasterize_polygon_edge_steep_b PROC NEAR
; 180c:51a9  CMP BX,BP
        cmp     bx,bp
; 180c:51ab  JL L_steepb_sorted (d271)
        jl      L_steepb_sorted
; 180c:51ad  XCHG BP,BX
        xchg    bx,bp
; 180c:51af  XCHG SI,CX
        xchg    cx,si
; 180c:51b1  MOV DI,CX   (label d271 = offset +8 from entry)
L_steepb_sorted:
        mov     di,cx
; 180c:51b3  SHL DI,1
        shl     di,1
; 180c:51b5  SHL DI,1
        shl     di,1
; 180c:51b7  MOV DX,2
        mov     dx,2
; 180c:51ba  SUB SI,CX
        sub     si,cx
; 180c:51bc  JGE L_steepb_pos_dy (d283)
        jge     L_steepb_pos_dy
; 180c:51be  NEG SI
        neg     si
; 180c:51c0  MOV DX,0xfffa  (-6)
        mov     dx,0fffah
; 180c:51c3  MOV CX,SI  (label d283 = offset +0x1a from entry)
L_steepb_pos_dy:
        mov     cx,si
; 180c:51c5  SUB BP,BX
        sub     bp,bx
; 180c:51c7  JLE L_steepb_no_neg (d28b)
        jle     L_steepb_no_neg
; 180c:51c9  NEG BP
        neg     bp
; 180c:51cb  MOV AX,BP  (label d28b = offset +0x22 from entry)
L_steepb_no_neg:
        mov     ax,bp
; 180c:51cd  ADD BP,SI
        add     bp,si
; 180c:51cf  SHL BP,1
        shl     bp,1
; 180c:51d1  SHL SI,1
        shl     si,1
; 180c:51d3  ADD AX,SI
        add     ax,si
; 180c:51d5  XCHG AX,BX
        xchg    ax,bx
; 180c:51d6  STOSW ES:DI   (AX -> ES:[DI]; DI += 2)
        stosw
; 180c:51d7  ADD DI,DX
        add     di,dx
; 180c:51d9  INC AX
        inc     ax
; 180c:51da  OR BX,BX
        or      bx,bx
; 180c:51dc  JL L_steepb_carry (d2a0)
        jl      L_steepb_carry
; 180c:51de  JMP L_steepb_main (d2ce)  -- forward local jump, "short" required
; (same TASM multi-pass sizing note as rasterize_polygon_edge_steep's
; equivalent jump above).
        jmp     short L_steepb_main

; Carry path: BX < 0, increment AX multiple times until BX >= 0
; (label d2a0 = offset +0x37 from entry = 180c:51e0)
L_steepb_carry:
; 180c:51e0  INC AX
        inc     ax
; 180c:51e1  ADD BX,SI
        add     bx,si
; 180c:51e3  JGE L_steepb_main (d2ce)
        jge     L_steepb_main
; 180c:51e5  INC AX
        inc     ax
; 180c:51e6  ADD BX,SI
        add     bx,si
; 180c:51e8  JGE L_steepb_main (d2ce)
        jge     L_steepb_main
; 180c:51ea  INC AX
        inc     ax
; 180c:51eb  ADD BX,SI
        add     bx,si
; 180c:51ed  JGE L_steepb_main (d2ce)
        jge     L_steepb_main
; 180c:51ef  INC AX
        inc     ax
; 180c:51f0  ADD BX,SI
        add     bx,si
; 180c:51f2  JGE L_steepb_main (d2ce)
        jge     L_steepb_main
; 180c:51f4  INC AX
        inc     ax
; 180c:51f5  ADD BX,SI
        add     bx,si
; 180c:51f7  JGE L_steepb_main (d2ce)
        jge     L_steepb_main
; 180c:51f9  INC AX
        inc     ax
; 180c:51fa  ADD BX,SI
        add     bx,si
; 180c:51fc  JGE L_steepb_main (d2ce)
        jge     L_steepb_main
; 180c:51fe  INC AX
        inc     ax
; 180c:51ff  ADD BX,SI
        add     bx,si
; 180c:5201  JGE L_steepb_main (d2ce)
        jge     L_steepb_main
; 180c:5203  INC AX
        inc     ax
; 180c:5204  ADD BX,SI
        add     bx,si
; 180c:5206  JGE L_steepb_main (d2ce)
        jge     L_steepb_main
; 180c:5208  JMP L_steepb_carry (d2a0)
        jmp     L_steepb_carry

; Pre-main: test accumulator before the main store loop
; (label d2ca = offset +0x61 from entry = 180c:520a)
L_steepb_pre_main:
; 180c:520a  ADD BX,BP
        add     bx,bp
; 180c:520c  JL L_steepb_carry (d2a0)
        jl      L_steepb_carry

; Main store loop body
; (label d2ce = offset +0x65 from entry = 180c:520e)
L_steepb_main:
; 180c:520e  STOSW ES:DI
        stosw
; 180c:520f  ADD DI,DX
        add     di,dx
; 180c:5211  INC AX
        inc     ax
; 180c:5212  DEC CX
        dec     cx
; 180c:5213  JZ L_steepb_done (d322)
        jz      L_steepb_done
; 180c:5215  ADD BX,BP
        add     bx,bp
; 180c:5217  JL L_steepb_carry (d2a0)
        jl      L_steepb_carry
; 180c:5219  STOSW ES:DI
        stosw
; 180c:521a  ADD DI,DX
        add     di,dx
; 180c:521c  INC AX
        inc     ax
; 180c:521d  DEC CX
        dec     cx
; 180c:521e  JZ L_steepb_done (d322)
        jz      L_steepb_done
; 180c:5220  ADD BX,BP
        add     bx,bp
; 180c:5222  JL L_steepb_carry (d2a0)
        jl      L_steepb_carry
; 180c:5224  STOSW ES:DI
        stosw
; 180c:5225  ADD DI,DX
        add     di,dx
; 180c:5227  INC AX
        inc     ax
; 180c:5228  DEC CX
        dec     cx
; 180c:5229  JZ L_steepb_done (d322)
        jz      L_steepb_done
; 180c:522b  ADD BX,BP
        add     bx,bp
; 180c:522d  JL L_steepb_carry (d2a0)
        jl      L_steepb_carry
; 180c:522f  STOSW ES:DI
        stosw
; 180c:5230  ADD DI,DX
        add     di,dx
; 180c:5232  INC AX
        inc     ax
; 180c:5233  DEC CX
        dec     cx
; 180c:5234  JZ L_steepb_done (d322)
        jz      L_steepb_done
; 180c:5236  ADD BX,BP
        add     bx,bp
; 180c:5238  JL L_steepb_carry (d2a0)
        jl      L_steepb_carry
; 180c:523a  STOSW ES:DI
        stosw
; 180c:523b  ADD DI,DX
        add     di,dx
; 180c:523d  INC AX
        inc     ax
; 180c:523e  DEC CX
        dec     cx
; 180c:523f  JZ L_steepb_done (d322)
        jz      L_steepb_done
; 180c:5241  ADD BX,BP
        add     bx,bp
; 180c:5243  JL L_steepb_carry (d2a0)
        jl      L_steepb_carry
; 180c:5245  STOSW ES:DI
        stosw
; 180c:5246  ADD DI,DX
        add     di,dx
; 180c:5248  INC AX
        inc     ax
; 180c:5249  DEC CX
        dec     cx
; 180c:524a  JZ L_steepb_done (d322)
        jz      L_steepb_done
; 180c:524c  ADD BX,BP
        add     bx,bp
; 180c:524e  JL L_steepb_carry (d2a0)
        jl      L_steepb_carry
; 180c:5250  STOSW ES:DI
        stosw
; 180c:5251  ADD DI,DX
        add     di,dx
; 180c:5253  INC AX
        inc     ax
; 180c:5254  DEC CX
        dec     cx
; 180c:5255  JZ L_steepb_done (d322)
        jz      L_steepb_done
; 180c:5257  ADD BX,BP
        add     bx,bp
; 180c:5259  JL L_steepb_carry (d2a0)
        jl      L_steepb_carry
; 180c:525b  STOSW ES:DI
        stosw
; 180c:525c  ADD DI,DX
        add     di,dx
; 180c:525e  INC AX
        inc     ax
; 180c:525f  DEC CX
        dec     cx
; 180c:5260  JNZ L_steepb_pre_main (d2ca)
        jnz     L_steepb_pre_main
; 180c:5262  RET
L_steepb_done:
        ret

_rasterize_polygon_edge_steep_b ENDP

; One extra leading copy of the 7-byte Gouraud stub pattern (STOSW; ADD DI,CX;
; ADD BP,BX; ADC AX,SI) that the dispatcher below uses 400x. The dispatcher
; computes its minimum entry point as gradient_line_chain_tail - 7*400, which
; lands 38 bytes past its own start (past the dispatcher prologue), so this
; extra leading copy can never be jumped to (401 stub copies, only 400
; reachable).
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si

; ============================================================================
; state_machine_disp_tbl_5d80 -- Gouraud-shaded scanline rasterizer (Mode-X
; plane writer).  180c:526a..5d80, linear 0x1d32a, 2839 bytes.
;
; Unrolled computed-goto rasterizer: dispatcher (38 bytes) + 400 x 7-byte
; stubs + 1-byte RET. This is the tail-jump target of state_machine_enter_
; state2_a/_b above (both intra-module near JMPs).
;
; WHY ASM (not C): register-IN calling convention (all inputs in registers:
;   AX=initial color, BX=dColor_frac, CX=pixel_count, DI=pixel_index,
;   SI=dColor_int, BP=frac_accumulator, ES=video_segment);
; uses STOSW and ADD DI,CX to advance ES:DI; computed JMP via DX into an
; unrolled stub chain. No C compiler emits any of this.
;
; The dispatch uses MOV DX,offset gradient_line_chain_tail (a symbol, not a
; hardcoded CS tail offset) so it works at any link-time segment offset. The
; 7-byte-per-stub spacing is invariant.
; ============================================================================
_state_machine_disp_tbl_5d80	proc near
	push	ax				; save initial color
	shl	di,1				; DI = DI*2
	shl	di,1				; DI = DI*4
	mov	ax,[_g_wRasterEdgeColumnOff]		; AX = framebuffer base
	add	di,ax				; DI = 4*pixel_index + base
	mov	dx,cx				; DX = CX
	xor	ax,ax
	add	ax,dx				; AX = CX
	shl	dx,1				; DX = CX*2
	add	ax,dx				; AX = CX*3
	shl	dx,1				; DX = CX*4
	add	ax,dx				; AX = CX*7
	mov	dx,offset gradient_line_chain_tail	; DX = tail offset
	sub	dx,ax				; DX = tail - 7*CX (dispatch entry)
	mov	al,[_g_bRasterSpanDiStride]		; AL = inner DI stride byte
	cbw					; AX = sign-extend byte to word
	mov	cx,ax				; CX = inner DI stride
	pop	ax				; restore initial color
	jmp	dx				; dispatch into stub chain

; --- 400 x 7-byte Gouraud steps (180c:5290..5d79) ---
; Each stub: STOSW ES:DI ; ADD DI,CX ; ADD BP,BX ; ADC AX,SI
; Execution falls through from the chosen entry stub down to RET.
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si
	stosw
	add	di,cx
	add	bp,bx
	adc	ax,si

; --- chain tail: single-byte RET (180c:5d80) ---
gradient_line_chain_tail:
	ret
_state_machine_disp_tbl_5d80	endp

S180C_TEXT	ends
	end
