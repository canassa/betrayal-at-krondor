; ============================================================================
; DRAWLINE.ASM -- KRONDOR.EXE line clipper + renderer dispatch (segment 180c).
; Single member: draw_line (180c:2639, linear 0x1a6f9, 233 bytes).
;
; Clips a line segment (x1,y1)-(x2,y2) against the global clip rectangle,
; then dispatches to the installed line-renderer via g_renderer_vtable.pfn_draw_line.
; After clipping, ensures x1 <= x2 (unsigned), swapping endpoints if needed.
;
; WHY ASM: after the standard BP frame is set up and the four incoming
; parameters are loaded into BX/CX/SI/DI, BP is repurposed as a scratch
; register for the parametric-interpolation divisions (never touching
; [BP+N] again). The final dispatch, `CALLF [g_renderer_vtable+8]`, passes
; the clipped endpoints in BX/CX/DX/SI (register convention), not on the
; stack -- the callee's own calling convention, not a C prototype.
;
; All DGROUP data referenced by SYMBOL per RULE 0b.
; ============================================================================

	.286

	include	gfxctx.inc	; _g_graphics_context.bClip_enabled, _g_clip_{xmin,xmax,ymin,ymax}, _g_graphics_context.wGfxBlitDstPage

	extrn	_g_renderer_vtable:dword	; RendererVtable; pfn_draw_line at offset +8

	_DATA	segment word public 'DATA'
	_DATA	ends
	_BSS	segment word public 'BSS'
	_BSS	ends
	DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_draw_line

; void draw_line(int x1, int y1, int x2, int y2)
; [BP+6]=x1  [BP+8]=y1  [BP+0xa]=x2  [BP+0xc]=y2
_draw_line	proc far
	push	bp				; 2639 +0x00
	mov	bp,sp				; 263a +0x01
	push	si				; 263c +0x03
	push	di				; 263d +0x04
	push	es				; 263e +0x05
	mov	ax,word ptr _g_graphics_context.wGfxBlitDstPage	; 263f +0x06
	mov	es,ax				; 2642 +0x09
	mov	bx,word ptr [bp+6]		; 2644 +0x0b  bx = x1
	mov	cx,word ptr [bp+8]		; 2647 +0x0e  cx = y1
	mov	si,word ptr [bp+0ah]		; 264a +0x11  si = x2
	mov	di,word ptr [bp+0ch]		; 264d +0x14  di = y2
	mov	al,byte ptr _g_graphics_context.bClip_enabled	; 2650 +0x17
	or	al,al				; 2653 +0x1a
	jnz	L_265a				; 2655 +0x1c  clip enabled -> clip code
	jmp	L_270d				; 2657 +0x1e  clip off -> final sort

; ==========================================================================
; Y-minimum clipping
; ==========================================================================
L_265a:
	mov	ax,word ptr _g_graphics_context.nClip_ymin	; 265a +0x21
	cmp	cx,ax				; 265d +0x24  y1 < ymin?
	jl	L_266b				; 265f +0x26
	cmp	di,ax				; 2661 +0x28  y2 < ymin?
	jge	L_2686				; 2663 +0x2a  y2 >= ymin -> x-min
	xchg	bx,si				; 2665 +0x2c
	xchg	cx,di				; 2667 +0x2e
	jmp	short L_266f			; 2669 +0x30

L_266b:
	cmp	di,ax				; 266b +0x32  y2 < ymin too?
	jl	L_269b_trampoline		; 266d +0x34  both outside -> return

L_266f:
	mov	bp,di				; 266f +0x36
	sub	bp,cx				; 2671 +0x38
	sub	ax,cx				; 2673 +0x3a
	mov	cx,ax				; 2675 +0x3c
	mov	ax,si				; 2677 +0x3e
	sub	ax,bx				; 2679 +0x40
	imul	cx				; 267b +0x42
	idiv	bp				; 267d +0x44
	add	bx,ax				; 267f +0x46
	mov	ax,word ptr _g_graphics_context.nClip_ymin	; 2681 +0x48
	mov	cx,ax				; 2684 +0x4b

; ==========================================================================
; X-minimum clipping
; ==========================================================================
L_2686:
	mov	ax,word ptr _g_graphics_context.nClip_xmin	; 2686 +0x4d
	cmp	bx,ax				; 2689 +0x50  x1 < xmin?
	jl	L_2697				; 268b +0x52
	cmp	si,ax				; 268d +0x54  x2 < xmin?
	jge	L_26b5				; 268f +0x56  x2 >= xmin -> y-max
	xchg	bx,si				; 2691 +0x58
	xchg	cx,di				; 2693 +0x5a
	jmp	short L_269e			; 2695 +0x5c

L_2697:
	cmp	si,ax				; 2697 +0x5e  x2 < xmin too?
	jge	L_269e				; 2699 +0x60  x2 >= xmin -> clip

; Shared return trampoline used by y-min, y-max, and x-max "both outside" cases.
; Also the fallthrough from x-min "both outside" (x1,x2 both < xmin).
; Original: 269b: JMP 271d (near jump to epilogue)
L_269b_trampoline:
	jmp	L_271d_epilogue			; 269b +0x62  (near jmp, 3 bytes)

; ==========================================================================
; X-minimum interpolation
; ==========================================================================
L_269e:
	mov	bp,si				; 269e +0x65
	sub	bp,bx				; 26a0 +0x67
	sub	ax,bx				; 26a2 +0x69
	mov	bx,ax				; 26a4 +0x6b
	mov	ax,di				; 26a6 +0x6d
	sub	ax,cx				; 26a8 +0x6f
	imul	bx				; 26aa +0x71
	idiv	bp				; 26ac +0x73
	add	cx,ax				; 26ae +0x75
	mov	ax,word ptr _g_graphics_context.nClip_xmin	; 26b0 +0x77
	mov	bx,ax				; 26b3 +0x7a

; ==========================================================================
; Y-maximum clipping (unsigned compare)
; ==========================================================================
L_26b5:
	mov	ax,word ptr _g_graphics_context.nClip_ymax	; 26b5 +0x7c
	cmp	cx,ax				; 26b8 +0x7f  y1 > ymax? (unsigned)
	ja	L_26c6				; 26ba +0x81
	cmp	di,ax				; 26bc +0x83  y2 > ymax? (unsigned)
	jbe	L_26e1				; 26be +0x85  y2 <= ymax -> x-max
	xchg	bx,si				; 26c0 +0x87
	xchg	cx,di				; 26c2 +0x89
	jmp	short L_26ca			; 26c4 +0x8b

L_26c6:
	cmp	di,ax				; 26c6 +0x8d  y2 > ymax too? (unsigned)
	ja	L_269b_trampoline		; 26c8 +0x8f  both outside -> return

L_26ca:
	mov	bp,di				; 26ca +0x91
	sub	bp,cx				; 26cc +0x93
	sub	ax,cx				; 26ce +0x95
	mov	cx,ax				; 26d0 +0x97
	mov	ax,si				; 26d2 +0x99
	sub	ax,bx				; 26d4 +0x9b
	imul	cx				; 26d6 +0x9d
	idiv	bp				; 26d8 +0x9f
	add	bx,ax				; 26da +0xa1

; After y-max interpolation: set y1 = ymax
; (also the fall-through from y2<=ymax case arrives at L_26e1, skipping this)
L_26dc:
	mov	ax,word ptr _g_graphics_context.nClip_ymax	; 26dc +0xa3
	mov	cx,ax				; 26df +0xa6

; ==========================================================================
; X-maximum clipping (unsigned compare)
; JBE from y-max test (26be) jumps directly here, skipping L_26dc
; ==========================================================================
L_26e1:
	mov	ax,word ptr _g_graphics_context.nClip_xmax	; 26e1 +0xa8
	cmp	bx,ax				; 26e4 +0xab  x1 > xmax? (unsigned)
	ja	L_26f2				; 26e6 +0xad
	cmp	si,ax				; 26e8 +0xaf  x2 > xmax? (unsigned)
	jbe	L_270d				; 26ea +0xb1  x2 <= xmax -> final sort
	xchg	bx,si				; 26ec +0xb3
	xchg	cx,di				; 26ee +0xb5
	jmp	short L_26f6			; 26f0 +0xb7

L_26f2:
	cmp	si,ax				; 26f2 +0xb9  x2 > xmax too? (unsigned)
	ja	L_269b_trampoline		; 26f4 +0xbb  both outside -> return

; ==========================================================================
; X-maximum interpolation
; ==========================================================================
L_26f6:
	mov	bp,si				; 26f6 +0xbd
	sub	bp,bx				; 26f8 +0xbf
	sub	ax,bx				; 26fa +0xc1
	mov	bx,ax				; 26fc +0xc3
	mov	ax,di				; 26fe +0xc5
	sub	ax,cx				; 2700 +0xc7
	imul	bx				; 2702 +0xc9
	idiv	bp				; 2704 +0xcb
	add	cx,ax				; 2706 +0xcd
	mov	ax,word ptr _g_graphics_context.nClip_xmax	; 2708 +0xcf
	mov	bx,ax				; 270b +0xd2

; ==========================================================================
; Final sort: ensure x1 <= x2 (unsigned)
; On entry: BX=x1, CX=y1, SI=x2, DI=y2
; ==========================================================================
L_270d:
	mov	dx,si				; 270d +0xd4  dx = x2
	mov	si,di				; 270f +0xd6  si = y2
	cmp	bx,dx				; 2711 +0xd8  x1 <= x2? (unsigned)
	jbe	L_2719				; 2713 +0xda
	xchg	bx,dx				; 2715 +0xdc
	xchg	cx,si				; 2717 +0xde

; ==========================================================================
; Dispatch to installed line renderer
; Registers: BX=x1, CX=y1, DX=x2, SI=y2, ES=wGfxBlitDstPage
; ==========================================================================
L_2719:
	call	dword ptr [_g_renderer_vtable+8]	; 2719 +0xe0

; ==========================================================================
; Epilogue (shared by normal return and early-return trampoline)
; ==========================================================================
L_271d_epilogue:
	pop	es				; 271d +0xe4
	pop	di				; 271e +0xe5
	pop	si				; 271f +0xe6
	pop	bp				; 2720 +0xe7
	retf					; 2721 +0xe8
_draw_line	endp

S180C_TEXT	ends
	end
