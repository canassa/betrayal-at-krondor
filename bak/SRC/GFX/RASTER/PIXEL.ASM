; ============================================================================
; PIXEL.ASM -- KRONDOR.EXE clipped pixel-access forwarders (segment 180c).
;
; Two routines, contiguous in the image (180c:29dc..2a3e, linear
; 0x1aa9c..0x1ab00, 50+50 bytes). Both clip (x,y) against the graphics-context
; viewport rect, then TAIL-DISPATCH through the renderer vtable to the active
; adapter driver:
;
;   _getpixel (180c:29dc / 0x1aa9c)  JMPF [g_renderer_vtable+0x54] (pfn_getpixel, slot 21)
;   _putpixel (180c:2a0e / 0x1aace)  JMPF [g_renderer_vtable+0x58] (pfn_putpixel, slot 22)
;
; WHY ASM (both) -- the bare `JMPF [g_renderer_vtable.pfn_*]` (FF 2E ...) tail-
; dispatch has no BCC 3.1 form: BCC 3.1 has NO tail-call optimization, so a C
; forwarder always compiles to push/re-push/CALLF/cleanup/RETF, never a JMPF
; tail-jump.
;
; Clip-rejected pixels return 0xffff (the "clipped" sentinel).
;
; The two bodies are given per-proc local labels (L_gp_*/L_pp_*) to avoid a TASM
; duplicate-symbol collision in the shared module.
; ============================================================================

	.286

	; g_clip_* are interior fields of the graphics-context (structs.md §36);
	; gfxctx.inc EQUs each to _g_graphics_context + its struct offset.
	include	gfxctx.inc
	extrn	_g_renderer_vtable:byte		; RendererVtable; slots 21/22 at +0x54/+0x58

	_DATA	segment word public 'DATA'
	_DATA	ends
	_BSS	segment word public 'BSS'
	_BSS	ends
	DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_getpixel, _putpixel

; ----------------------------------------------------------------------------
; unsigned huge getpixel(int x, int y) -- clip then tail-dispatch to
; g_renderer_vtable.pfn_getpixel (+0x54, slot 21). Clip-rejected -> 0xffff.
; ----------------------------------------------------------------------------
_getpixel	proc far
	push	bp				; +0x00
	mov	bp,sp				; +0x01
	cmp	byte ptr _g_graphics_context.bClip_enabled,0	; +0x03
	jz	L_gp_dispatch			; +0x08  clip disabled -> dispatch
	mov	ax,word ptr [bp+6h]		; +0x0a  x
	cmp	ax,word ptr _g_graphics_context.nClip_xmin	; +0x0d
	jl	L_gp_reject			; +0x11  x < xmin -> reject
	cmp	ax,word ptr _g_graphics_context.nClip_xmax	; +0x13
	jg	L_gp_reject			; +0x17  x > xmax -> reject
	mov	ax,word ptr [bp+8h]		; +0x19  y
	cmp	ax,word ptr _g_graphics_context.nClip_ymin	; +0x1c
	jl	L_gp_reject			; +0x20  y < ymin -> reject
	cmp	ax,word ptr _g_graphics_context.nClip_ymax	; +0x22
	jg	L_gp_reject			; +0x26  y > ymax -> reject
L_gp_dispatch:
	pop	bp				; +0x28
	jmp	dword ptr [_g_renderer_vtable+54h]	; +0x29  tail-dispatch (slot 21)
L_gp_reject:
	pop	bp				; +0x2d  clip-rejected
	mov	ax,0ffffh			; +0x2e
	retf					; +0x31
_getpixel	endp

; ----------------------------------------------------------------------------
; void huge putpixel(int x, int y, int color) -- clip then tail-dispatch to
; g_renderer_vtable.pfn_putpixel (+0x58, slot 22). Clip-rejected -> 0xffff.
; ----------------------------------------------------------------------------
_putpixel	proc far
	push	bp				; +0x00
	mov	bp,sp				; +0x01
	cmp	byte ptr _g_graphics_context.bClip_enabled,0	; +0x03
	jz	L_pp_dispatch			; +0x08  clip disabled -> dispatch
	mov	ax,word ptr [bp+6h]		; +0x0a  x
	cmp	ax,word ptr _g_graphics_context.nClip_xmin	; +0x0d
	jl	L_pp_reject			; +0x11  x < xmin -> reject
	cmp	ax,word ptr _g_graphics_context.nClip_xmax	; +0x13
	jg	L_pp_reject			; +0x17  x > xmax -> reject
	mov	ax,word ptr [bp+8h]		; +0x19  y
	cmp	ax,word ptr _g_graphics_context.nClip_ymin	; +0x1c
	jl	L_pp_reject			; +0x20  y < ymin -> reject
	cmp	ax,word ptr _g_graphics_context.nClip_ymax	; +0x22
	jg	L_pp_reject			; +0x26  y > ymax -> reject
L_pp_dispatch:
	pop	bp				; +0x28
	jmp	dword ptr [_g_renderer_vtable+58h]	; +0x29  tail-dispatch (slot 22)
L_pp_reject:
	pop	bp				; +0x2d  clip-rejected
	mov	ax,0ffffh			; +0x2e
	retf					; +0x31
_putpixel	endp

S180C_TEXT	ends
	end
