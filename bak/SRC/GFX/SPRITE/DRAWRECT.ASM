; ============================================================================
; DRAWRECT.ASM -- KRONDOR.EXE filled-rectangle draw (segment 180c).
;
; draw_rect_filled (180c:0ebd / 0x18f7d, 267 bytes) draws a filled rectangle at
; (x,y) size (w,h). Builds an inline {y, h, x0, x1, x0, x1, ...} span table in
; the segment pointed to by wSpanTableBufSeg via STOSW + LOOP, dispatches to
; pfn_fill_spans_dithered_modey (vtable+0x6c) by register convention (ES =
; span-buf segment, SI = 0), then draws the 4 border lines via draw_line if fill
; is disabled or fill/outline colours differ. Clips the fill path to the global
; clip rect; the border is always unclipped. Saves/restores the original x,y
; params via PUSH [BP+6]/[BP+8] and POP [BP+8]/[BP+6] around the (clipped) fill.
;
; WHY ASM (not C): the span-table fill uses STOSW + LOOP (string store word +
; CX-counted loop), and its vtable dispatch passes ES:SI in registers (SI=0, ES =
; span-buf segment still set from the STOSW setup) with no stack args. Together
; with DI-first register saves this puts the routine in the non-Borland codegen
; family (shared with ROTBLIT's dispatch body) -- unroutable to C on a
; Borland-only toolchain.
;
; Split from RECTSPR.ASM: the sibling blitter blit_sprite_flipped_clipped
; (0x19089) proved to be bc2 inline-asm C and now lives in RECTSPR.C, linked
; immediately after this object. The single 0x90 (NOP) pad byte at 180c:0fc8
; that separated the two procs is emitted here as the trailing `nop`, so the C
; blitter starts at 180c:0fc9 / 0x19089.
; ============================================================================

	.286

	include	gfxctx.inc		; extrn _g_graphics_context:byte + field aliases

	extrn	_g_renderer_vtable:byte		; DGROUP+0x2ac6 (RendererVtable)
	extrn	_draw_line:far

	_DATA	segment word public 'DATA'
	_DATA	ends
	_BSS	segment word public 'BSS'
	_BSS	ends
	DGROUP	group	_DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_draw_rect_filled

; ----------------------------------------------------------------------------
; void draw_rect_filled(int x, int y, int w, int h)
; [BP+6]=x  [BP+8]=y  [BP+A]=w  [BP+C]=h
; ----------------------------------------------------------------------------
_draw_rect_filled	proc far
	push	bp
	mov	bp,sp
	sub	sp,6			; [BP-2]=iVar  [BP-4]=x2  [BP-6]=y2
	push	di
	push	si
	mov	ax,word ptr [bp+0ah]	; ax = w
	add	ax,word ptr [bp+6]	; ax = w + x
	dec	ax			; ax = x + w - 1
	mov	word ptr [bp-4],ax	; [BP-4] = x2
	mov	ax,word ptr [bp+0ch]	; ax = h
	add	ax,word ptr [bp+8]	; ax = h + y
	dec	ax			; ax = y + h - 1
	mov	word ptr [bp-6],ax	; [BP-6] = y2
	cmp	byte ptr _g_graphics_context.bGfx_fill_enabled,0
	jnz	L_drf_fill_enabled
	jmp	L_drf_border_check

L_drf_fill_enabled:
	push	word ptr [bp+6]		; save original x on stack
	push	word ptr [bp+8]		; save original y on stack
	cmp	byte ptr _g_graphics_context.bClip_enabled,0
	jz	L_drf_wh_check		; no clipping

	; clip x left: x = max(x, xmin); w adjusted
	mov	ax,word ptr [bp+6]
	sub	ax,word ptr _g_graphics_context.nClip_xmin
	mov	word ptr [bp-2],ax
	or	ax,ax
	jge	L_drf_clip_xmin_done
	sub	word ptr [bp+6],ax
	add	word ptr [bp+0ah],ax
L_drf_clip_xmin_done:
	; clip y top
	mov	ax,word ptr [bp+8]
	sub	ax,word ptr _g_graphics_context.nClip_ymin
	mov	word ptr [bp-2],ax
	or	ax,ax
	jge	L_drf_clip_ymin_done
	sub	word ptr [bp+8],ax
	add	word ptr [bp+0ch],ax
L_drf_clip_ymin_done:
	; clip x right: w = min(w, xmax - x + 1)
	mov	ax,word ptr _g_graphics_context.nClip_xmax
	sub	ax,word ptr [bp-4]
	mov	word ptr [bp-2],ax
	or	ax,ax
	jge	L_drf_clip_xmax_done
	add	word ptr [bp+0ah],ax
L_drf_clip_xmax_done:
	; clip y bottom
	mov	ax,word ptr _g_graphics_context.nClip_ymax
	sub	ax,word ptr [bp-6]
	mov	word ptr [bp-2],ax
	or	ax,ax
	jge	L_drf_wh_check
	add	word ptr [bp+0ch],ax

L_drf_wh_check:
	cmp	word ptr [bp+0ah],0
	jle	L_drf_restore_xy
	cmp	word ptr [bp+0ch],0
	jle	L_drf_restore_xy

	; build span table
	mov	es,word ptr _g_graphics_context_render.wSpanTableBufSeg
	xor	di,di
	mov	ax,word ptr [bp+8]	; y (possibly clipped)
	stosw				; ES:[0] = y, DI=2
	mov	ax,word ptr [bp+0ch]	; h
	mov	cx,ax
	stosw				; ES:[2] = h, DI=4
	mov	bx,word ptr [bp+6]	; BX = x
	mov	dx,bx
	add	dx,word ptr [bp+0ah]	; DX = x + w
	dec	dx			; DX = x + w - 1
L_drf_span_loop:
	mov	ax,bx
	stosw				; ES:[DI] = x, DI+=2
	mov	ax,dx
	stosw				; ES:[DI] = x+w-1, DI+=2
	loop	L_drf_span_loop		; --CX; jump if CX != 0

	; dispatch to fill renderer (ES:SI = span buf ptr, SI=0)
	xor	si,si
	push	bp
	call	dword ptr [_g_renderer_vtable + 06ch]	; pfn_fill_spans_dithered_modey
	pop	bp

L_drf_restore_xy:
	pop	word ptr [bp+8]		; restore original y
	pop	word ptr [bp+6]		; restore original x

L_drf_border_check:
	cmp	byte ptr _g_graphics_context.bGfx_fill_enabled,0
	jz	L_drf_draw_border
	mov	al,byte ptr _g_graphics_context.bGfx_outline_color
	cmp	byte ptr _g_graphics_context.bGfx_fill_color,al
	jz	L_drf_done

L_drf_draw_border:
	mov	si,word ptr [bp+6]	; SI = orig_x
	mov	di,word ptr [bp+8]	; DI = orig_y

	; draw right vertical: draw_line(x2, y, x2, y2)
	mov	ax,word ptr [bp-6]	; y2
	push	ax
	mov	ax,word ptr [bp-4]	; x2
	push	ax
	push	di			; y
	push	ax			; x2 (AX still = x2)
	call	far ptr _draw_line
	add	sp,4			; pop x2 and y; y2 and x2 remain

	; draw bottom horizontal: draw_line(x, y2, x2, y2)
	mov	ax,word ptr [bp-6]	; y2
	push	ax
	push	si			; x
	call	far ptr _draw_line
	add	sp,6			; pop x and y2 and x2; y2 remains

	; draw left vertical: draw_line(x, y, x, y2)
	push	si			; x
	push	di			; y
	push	si			; x
	call	far ptr _draw_line
	add	sp,8			; pop all 4: x, y, x, y2

	; draw top horizontal: draw_line(x, y, x2, y)
	push	di			; y
	mov	ax,word ptr [bp-4]	; x2
	push	ax
	push	di			; y
	push	si			; x
	call	far ptr _draw_line
	add	sp,8

L_drf_done:
	pop	si
	pop	di
	mov	sp,bp
	pop	bp
	retf

_draw_rect_filled	endp

	nop					; 180c:0fc8 (lin 0x19088): 1-byte pad before RECTSPR.C's blitter

S180C_TEXT	ends

	end
