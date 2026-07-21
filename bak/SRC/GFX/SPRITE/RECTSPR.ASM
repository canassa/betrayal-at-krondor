; ============================================================================
; RECTSPR.ASM -- KRONDOR.EXE filled-rect + flipped/clipped sprite blit module
; (segment 180c).
;
; Two routines, contiguous in the image (180c:0ebd..14ee, linear
; 0x18f7d..0x19545). draw_rect_filled (267 bytes) ends at 180c:0fc8;
; blit_sprite_flipped_clipped starts one byte later at 180c:0fc9 -- a single
; 0x90 (NOP) pad byte sits at 0fc8, emitted below as an explicit `nop` between
; the two PROCs.
;
;   _draw_rect_filled              (180c:0ebd / 0x18f7d, 267 bytes) draws a
;                          filled rectangle at (x,y) size (w,h). Builds an
;                          inline {y, h, x0, x1, x0, x1, ...} span table in
;                          the segment pointed to by wSpanTableBufSeg via
;                          STOSW + LOOP, dispatches to
;                          pfn_fill_spans_dithered_modey (vtable+0x6c) via
;                          register convention (ES = span-buf segment, SI =
;                          0), then draws the 4 border lines via draw_line if
;                          fill is disabled or fill/outline colours differ.
;                          Clips the fill path to the global clip rect; the
;                          border is always unclipped. Saves/restores the
;                          original x,y parameters via PUSH [BP+6]/[BP+8] and
;                          POP [BP+8]/[BP+6] around the (possibly clipped)
;                          fill.
;   _blit_sprite_flipped_clipped   (180c:0fc9 / 0x19089, 1212 bytes) blits a
;                          sprite with optional horizontal/vertical flip and
;                          clipping. Sprite stream format (packed
;                          nibble/RLE): byte & 0x80 == 0 is a low-opcode
;                          (end-of-row, x-skip, or end-of-sprite), byte &
;                          0xC0 == 0x80 is a nibble-pair pixel run, byte &
;                          0xC0 == 0xC0 is a solid-colour fill run. Draws
;                          each run via the renderer vtable's
;                          pfn_blit_sprite_chunky_flip (vtable+0x98) and
;                          pfn_fill_run_a (vtable+0x28) slots.
;
; WHY ASM (not C), per routine:
;   * draw_rect_filled's span-table fill uses STOSW + LOOP (string store word +
;     CX-counted loop). Its vtable dispatch passes ES:SI in registers (SI=0, ES
;     = span-buf segment still set from the STOSW setup) with no stack args. It
;     saves/restores x,y via PUSH [BP+6]/[BP+8] / POP [BP+8]/[BP+6].
;   * blit_sprite_flipped_clipped's two vtable slots use a register calling
;     convention (args in CL/AH/CH/SI/DI/BX/ES/DX + the carry flag as a boolean
;     argument via STC/CLC before the CALLF).
;
; Both drive the SAME renderer vtable (_g_renderer_vtable, DGROUP+0x2ac6) by
; register convention -- draw_rect_filled's fill path and
; blit_sprite_flipped_clipped's run drawing are the two ways the engine
; pushes pixels through the active video-mode renderer.
; ============================================================================

	.286

	include	gfxctx.inc		; extrn _g_graphics_context:byte + field aliases

	extrn	_g_renderer_vtable:byte		; DGROUP+0x2ac6 (RendererVtable)
	extrn	_draw_line:far

_g_renderer_pfn_blit_sprite_chunky_flip	equ	_g_renderer_vtable + 098h
_g_renderer_pfn_fill_run_a		equ	_g_renderer_vtable + 028h

	_DATA	segment word public 'DATA'
	_DATA	ends
	_BSS	segment word public 'BSS'
	_BSS	ends
	DGROUP	group	_DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_draw_rect_filled, _blit_sprite_flipped_clipped

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

	nop					; 180c:0fc8 (lin 0x19088): 1-byte pad between the two procs

; ----------------------------------------------------------------------------
; void far blit_sprite_flipped_clipped(void *sprite, int x, int y, int flags)
;   [BP+6]=sprite  [BP+8]=x  [BP+A]=y  [BP+C]=flags
; ----------------------------------------------------------------------------
_blit_sprite_flipped_clipped	proc far
	push	bp			; 0fc9
	mov	bp,sp			; 0fca
	sub	sp,0158h		; 0fcc
	push	si			; 0fd0
	push	di			; 0fd1
	mov	ax,word ptr [_g_graphics_context.wGfxBlitDstPage]	; 0fd2
	mov	word ptr [bp - 016h],ax	; 0fd5
	mov	al,byte ptr [_g_graphics_context.bClip_enabled]	; 0fd8
	mov	byte ptr [bp - 012h],al	; 0fdb
	or	al,al			; 0fde
	jz	L_bsf_100d		; 0fe0
	mov	ax,word ptr [bp + 08h]	; 0fe2
	cmp	ax,word ptr [_g_graphics_context.nClip_xmin]	; 0fe5
	jl	L_bsf_100d		; 0fe9
	mov	bx,word ptr [bp + 06h]	; 0feb
	add	ax,word ptr [bx + 06h]	; 0fee
	cmp	ax,word ptr [_g_graphics_context.nClip_xmax]	; 0ff1
	jg	L_bsf_100d		; 0ff5
	mov	ax,word ptr [bp + 0ah]	; 0ff7
	cmp	ax,word ptr [_g_graphics_context.nClip_ymin]	; 0ffa
	jl	L_bsf_100d		; 0ffe
	add	ax,word ptr [bx + 08h]	; 1000
	cmp	ax,word ptr [_g_graphics_context.nClip_ymax]	; 1003
	jg	L_bsf_100d		; 1007
	mov	byte ptr [bp - 012h],00h	; 1009
L_bsf_100d:
	test	byte ptr [bp + 0ch],01h	; 100d
	jz	L_bsf_1024		; 1011
	mov	word ptr [bp - 0ah],0ffffh	; 1013
	mov	bx,word ptr [bp + 06h]	; 1018
	mov	ax,word ptr [bx + 08h]	; 101b
	dec	ax			; 101e
	add	word ptr [bp + 0ah],ax	; 101f
	jmp	short L_bsf_1029	; 1022
L_bsf_1024:
	mov	word ptr [bp - 0ah],00001h	; 1024
L_bsf_1029:
	test	byte ptr [bp + 0ch],02h	; 1029
	jz	L_bsf_1039		; 102d
	mov	bx,word ptr [bp + 06h]	; 102f
	mov	ax,word ptr [bx + 06h]	; 1032
	dec	ax			; 1035
	add	word ptr [bp + 08h],ax	; 1036
L_bsf_1039:
	mov	al,byte ptr [bp - 012h]	; 1039
	cbw				; 103c
	or	ax,ax			; 103d
	jz	L_bsf_105e		; 103f
	mov	ax,word ptr [bp + 0ah]	; 1041
	cmp	ax,word ptr [_g_graphics_context.nClip_ymax]	; 1044
	jg	L_bsf_1055		; 1048
	cmp	ax,word ptr [_g_graphics_context.nClip_ymin]	; 104a
	jl	L_bsf_1055		; 104e
	mov	ax,00001h		; 1050
	jmp	short L_bsf_1057	; 1053
L_bsf_1055:
	xor	ax,ax			; 1055
L_bsf_1057:
	mov	byte ptr [bp - 011h],al	; 1057
	or	al,al			; 105a
	jz	L_bsf_106a		; 105c
L_bsf_105e:
	mov	bx,word ptr [bp + 0ah]	; 105e
	shl	bx,01h			; 1061
	mov	ax,word ptr [bx + _g_pRow_offset_lut]	; 1063
	mov	word ptr [bp - 014h],ax	; 1067
L_bsf_106a:
	mov	bx,word ptr [bp + 06h]	; 106a
	mov	ax,word ptr [bx]	; 106d
	cwd				; 106f
	mov	dx,word ptr [bx + 02h]	; 1070
	mov	word ptr [bp - 04h],ax	; 1073
	mov	word ptr [bp - 06h],dx	; 1076
	les	bx,[bp - 06h]		; 1079
	mov	al,byte ptr es:[bx]	; 107c
	mov	byte ptr [bp - 017h],al	; 107f
	inc	word ptr [bp - 06h]	; 1082
L_bsf_1085:
	les	bx,[bp - 06h]		; 1085
	mov	al,byte ptr es:[bx]	; 1088
	mov	byte ptr [bp - 01h],al	; 108b
	inc	word ptr [bp - 06h]	; 108e
	test	byte ptr [bp - 01h],080h	; 1091
	jnz	L_bsf_109a		; 1095
	jmp	L_bsf_13bc		; 1097
L_bsf_109a:
	test	byte ptr [bp - 01h],040h	; 109a
	jnz	L_bsf_10a3		; 109e
	jmp	L_bsf_125a		; 10a0
L_bsf_10a3:
	and	byte ptr [bp - 01h],03fh	; 10a3
	mov	al,byte ptr [bp - 01h]	; 10a7
	mov	byte ptr [bp - 02h],al	; 10aa
	lea	ax,[bp + 0fea8h]	; 10ad
	mov	word ptr [bp - 010h],ax	; 10b1
	jmp	short L_bsf_10ef	; 10b4
L_bsf_10b6:
	les	bx,[bp - 06h]		; 10b6
	mov	al,byte ptr es:[bx]	; 10b9
	mov	byte ptr [bp - 018h],al	; 10bc
	inc	word ptr [bp - 06h]	; 10bf
	mov	ah,00h			; 10c2
	mov	cl,04h			; 10c4
	sar	ax,cl			; 10c6
	add	al,byte ptr [bp - 017h]	; 10c8
	mov	bx,word ptr [bp - 010h]	; 10cb
	mov	byte ptr [bx],al	; 10ce
	inc	word ptr [bp - 010h]	; 10d0
	dec	byte ptr [bp - 01h]	; 10d3
	cmp	byte ptr [bp - 01h],00h	; 10d6
	jz	L_bsf_10ef		; 10da
	mov	al,byte ptr [bp - 018h]	; 10dc
	and	al,00fh			; 10df
	add	al,byte ptr [bp - 017h]	; 10e1
	mov	bx,word ptr [bp - 010h]	; 10e4
	mov	byte ptr [bx],al	; 10e7
	inc	word ptr [bp - 010h]	; 10e9
	dec	byte ptr [bp - 01h]	; 10ec
L_bsf_10ef:
	cmp	byte ptr [bp - 01h],00h	; 10ef
	jnz	L_bsf_10b6		; 10f3
L_bsf_10f5:
	lea	ax,[bp + 0fea8h]	; 10f5
	mov	word ptr [bp - 010h],ax	; 10f9
	test	byte ptr [bp + 0ch],02h	; 10fc
	jnz	L_bsf_1105		; 1100
	jmp	L_bsf_11b2		; 1102
L_bsf_1105:
	mov	al,byte ptr [bp - 02h]	; 1105
	cbw				; 1108
	mov	dx,word ptr [bp + 08h]	; 1109
	sub	dx,ax			; 110c
	mov	word ptr [bp - 0ch],dx	; 110e
	mov	al,byte ptr [bp - 012h]	; 1111
	cbw				; 1114
	or	ax,ax			; 1115
	jz	L_bsf_1134		; 1117
	cmp	byte ptr [bp - 011h],00h	; 1119
	jnz	L_bsf_1122		; 111d
	jmp	L_bsf_1251		; 111f
L_bsf_1122:
	mov	ax,word ptr [bp - 0ch]	; 1122
	cmp	ax,word ptr [_g_graphics_context.nClip_xmin]	; 1125
	jl	L_bsf_1156		; 1129
	mov	ax,word ptr [bp + 08h]	; 112b
	cmp	ax,word ptr [_g_graphics_context.nClip_xmax]	; 112e
	jge	L_bsf_1156		; 1132
L_bsf_1134:
	push	si			; 1134
	push	di			; 1135
	mov	cl,byte ptr [bp - 02h]	; 1136
	db	030h, 0E4h		; 1139  xor ah,ah (store encoding)
	db	088h, 0E5h		; 113b  mov ch,ah (store encoding)
	mov	si,word ptr [bp - 010h]	; 113d
	mov	di,word ptr [bp - 014h]	; 1140
	mov	bx,word ptr [bp + 08h]	; 1143
	mov	es,word ptr [bp - 016h]	; 1146
	stc				; 1149
	mov	dx,word ptr [bp + 0ah]	; 114a
	call	dword ptr [_g_renderer_pfn_blit_sprite_chunky_flip]	; 114d
	pop	di			; 1151
	pop	si			; 1152
	jmp	L_bsf_1251		; 1153
L_bsf_1156:
	mov	ax,word ptr [bp - 0ch]	; 1156
	cmp	ax,word ptr [_g_graphics_context.nClip_xmin]	; 1159
	jge	L_bsf_1182		; 115d
	mov	ax,word ptr [_g_graphics_context.nClip_xmin]	; 115f
	sub	ax,word ptr [bp - 0ch]	; 1162
	mov	word ptr [bp - 0eh],ax	; 1165
	cmp	ax,03fh			; 1168
	jle	L_bsf_1170		; 116b
	jmp	L_bsf_1251		; 116d
L_bsf_1170:
	mov	al,byte ptr [bp - 02h]	; 1170
	sub	al,byte ptr [bp - 0eh]	; 1173
	mov	byte ptr [bp - 02h],al	; 1176
	or	al,al			; 1179
	jg	L_bsf_1180		; 117b
	jmp	L_bsf_1251		; 117d
L_bsf_1180:
	jmp	L_bsf_1134		; 1180
L_bsf_1182:
	mov	ax,word ptr [bp + 08h]	; 1182
	sub	ax,word ptr [_g_graphics_context.nClip_xmax]	; 1185
	mov	word ptr [bp - 0eh],ax	; 1189
	cmp	ax,03fh			; 118c
	jle	L_bsf_1194		; 118f
	jmp	L_bsf_1251		; 1191
L_bsf_1194:
	mov	al,byte ptr [bp - 02h]	; 1194
	sub	al,byte ptr [bp - 0eh]	; 1197
	mov	byte ptr [bp - 02h],al	; 119a
	or	al,al			; 119d
	jg	L_bsf_11a4		; 119f
	jmp	L_bsf_1251		; 11a1
L_bsf_11a4:
	mov	ax,word ptr [bp - 0eh]	; 11a4
	add	word ptr [bp - 010h],ax	; 11a7
	mov	ax,word ptr [_g_graphics_context.nClip_xmax]	; 11aa
	mov	word ptr [bp + 08h],ax	; 11ad
	jmp	L_bsf_1134		; 11b0
L_bsf_11b2:
	mov	al,byte ptr [bp - 02h]	; 11b2
	cbw				; 11b5
	mov	dx,word ptr [bp + 08h]	; 11b6
	add	dx,ax			; 11b9
	mov	word ptr [bp - 0ch],dx	; 11bb
	mov	al,byte ptr [bp - 012h]	; 11be
	cbw				; 11c1
	or	ax,ax			; 11c2
	jz	L_bsf_11e1		; 11c4
	cmp	byte ptr [bp - 011h],00h	; 11c6
	jnz	L_bsf_11cf		; 11ca
	jmp	L_bsf_1251		; 11cc
L_bsf_11cf:
	mov	ax,word ptr [bp + 08h]	; 11cf
	cmp	ax,word ptr [_g_graphics_context.nClip_xmin]	; 11d2
	jl	L_bsf_1202		; 11d6
	mov	ax,word ptr [bp - 0ch]	; 11d8
	cmp	ax,word ptr [_g_graphics_context.nClip_xmax]	; 11db
	jg	L_bsf_1202		; 11df
L_bsf_11e1:
	push	si			; 11e1
	push	di			; 11e2
	mov	cl,byte ptr [bp - 02h]	; 11e3
	db	030h, 0E4h		; 11e6  xor ah,ah (store encoding)
	db	088h, 0E5h		; 11e8  mov ch,ah (store encoding)
	mov	si,word ptr [bp - 010h]	; 11ea
	mov	di,word ptr [bp - 014h]	; 11ed
	mov	bx,word ptr [bp + 08h]	; 11f0
	mov	es,word ptr [bp - 016h]	; 11f3
	clc				; 11f6
	mov	dx,word ptr [bp + 0ah]	; 11f7
	call	dword ptr [_g_renderer_pfn_blit_sprite_chunky_flip]	; 11fa
	pop	di			; 11fe
	pop	si			; 11ff
	jmp	short L_bsf_1251	; 1200
L_bsf_1202:
	mov	ax,word ptr [bp + 08h]	; 1202
	cmp	ax,word ptr [_g_graphics_context.nClip_xmin]	; 1205
	jge	L_bsf_1234		; 1209
	mov	ax,word ptr [_g_graphics_context.nClip_xmin]	; 120b
	sub	ax,word ptr [bp + 08h]	; 120e
	mov	word ptr [bp - 0eh],ax	; 1211
	cmp	ax,03fh			; 1214
	jg	L_bsf_1251		; 1217
	mov	al,byte ptr [bp - 02h]	; 1219
	sub	al,byte ptr [bp - 0eh]	; 121c
	mov	byte ptr [bp - 02h],al	; 121f
	or	al,al			; 1222
	jle	L_bsf_1251		; 1224
	mov	ax,word ptr [bp - 0eh]	; 1226
	add	word ptr [bp - 010h],ax	; 1229
	mov	ax,word ptr [_g_graphics_context.nClip_xmin]	; 122c
	mov	word ptr [bp + 08h],ax	; 122f
	jmp	L_bsf_11e1		; 1232
L_bsf_1234:
	mov	ax,word ptr [bp - 0ch]	; 1234
	sub	ax,word ptr [_g_graphics_context.nClip_xmax]	; 1237
	dec	ax			; 123b
	mov	word ptr [bp - 0eh],ax	; 123c
	cmp	ax,03fh			; 123f
	jg	L_bsf_1251		; 1242
	mov	al,byte ptr [bp - 02h]	; 1244
	sub	al,byte ptr [bp - 0eh]	; 1247
	mov	byte ptr [bp - 02h],al	; 124a
	or	al,al			; 124d
	jg	L_bsf_11e1		; 124f
L_bsf_1251:
	mov	ax,word ptr [bp - 0ch]	; 1251
	mov	word ptr [bp + 08h],ax	; 1254
	jmp	L_bsf_1085		; 1257
L_bsf_125a:
	and	byte ptr [bp - 01h],03fh	; 125a
	les	bx,[bp - 06h]		; 125e
	mov	al,byte ptr es:[bx]	; 1261
	mov	byte ptr [bp - 018h],al	; 1264
	inc	word ptr [bp - 06h]	; 1267
	test	byte ptr [bp + 0ch],02h	; 126a
	jnz	L_bsf_1273		; 126e
	jmp	L_bsf_131d		; 1270
L_bsf_1273:
	mov	al,byte ptr [bp - 01h]	; 1273
	cbw				; 1276
	mov	dx,word ptr [bp + 08h]	; 1277
	sub	dx,ax			; 127a
	mov	word ptr [bp - 0ch],dx	; 127c
	mov	al,byte ptr [bp - 012h]	; 127f
	cbw				; 1282
	or	ax,ax			; 1283
	jz	L_bsf_12a2		; 1285
	cmp	byte ptr [bp - 011h],00h	; 1287
	jnz	L_bsf_1290		; 128b
	jmp	L_bsf_13b3		; 128d
L_bsf_1290:
	mov	ax,word ptr [bp - 0ch]	; 1290
	cmp	ax,word ptr [_g_graphics_context.nClip_xmin]	; 1293
	jl	L_bsf_12c7		; 1297
	mov	ax,word ptr [bp + 08h]	; 1299
	cmp	ax,word ptr [_g_graphics_context.nClip_xmax]	; 129c
	jge	L_bsf_12c7		; 12a0
L_bsf_12a2:
	push	di			; 12a2
	mov	al,byte ptr [bp - 017h]	; 12a3
	add	al,byte ptr [bp - 018h]	; 12a6
	db	030h, 0E4h		; 12a9  xor ah,ah (store encoding)
	db	088h, 0E5h		; 12ab  mov ch,ah (store encoding)
	mov	bx,word ptr [bp + 08h]	; 12ad
	mov	cl,byte ptr [bp - 01h]	; 12b0
	db	029h, 0CBh		; 12b3  sub bx,cx (store encoding)
	inc	bx			; 12b5
	mov	di,word ptr [bp - 014h]	; 12b6
	mov	es,word ptr [bp - 016h]	; 12b9
	mov	dx,word ptr [bp + 0ah]	; 12bc
	call	dword ptr [_g_renderer_pfn_fill_run_a]	; 12bf
	pop	di			; 12c3
	jmp	L_bsf_13b3		; 12c4
L_bsf_12c7:
	mov	ax,word ptr [bp - 0ch]	; 12c7
	cmp	ax,word ptr [_g_graphics_context.nClip_xmin]	; 12ca
	jge	L_bsf_12f3		; 12ce
	mov	ax,word ptr [_g_graphics_context.nClip_xmin]	; 12d0
	sub	ax,word ptr [bp - 0ch]	; 12d3
	mov	word ptr [bp - 0eh],ax	; 12d6
	cmp	ax,03fh			; 12d9
	jle	L_bsf_12e1		; 12dc
	jmp	L_bsf_13b3		; 12de
L_bsf_12e1:
	mov	al,byte ptr [bp - 01h]	; 12e1
	sub	al,byte ptr [bp - 0eh]	; 12e4
	mov	byte ptr [bp - 01h],al	; 12e7
	or	al,al			; 12ea
	jg	L_bsf_12f1		; 12ec
	jmp	L_bsf_13b3		; 12ee
L_bsf_12f1:
	jmp	L_bsf_12a2		; 12f1
L_bsf_12f3:
	mov	ax,word ptr [bp + 08h]	; 12f3
	sub	ax,word ptr [_g_graphics_context.nClip_xmax]	; 12f6
	mov	word ptr [bp - 0eh],ax	; 12fa
	cmp	ax,03fh			; 12fd
	jle	L_bsf_1305		; 1300
	jmp	L_bsf_13b3		; 1302
L_bsf_1305:
	mov	al,byte ptr [bp - 01h]	; 1305
	sub	al,byte ptr [bp - 0eh]	; 1308
	mov	byte ptr [bp - 01h],al	; 130b
	or	al,al			; 130e
	jg	L_bsf_1315		; 1310
	jmp	L_bsf_13b3		; 1312
L_bsf_1315:
	mov	ax,word ptr [_g_graphics_context.nClip_xmax]	; 1315
	mov	word ptr [bp + 08h],ax	; 1318
	jmp	L_bsf_12a2		; 131b
L_bsf_131d:
	mov	al,byte ptr [bp - 01h]	; 131d
	cbw				; 1320
	mov	dx,word ptr [bp + 08h]	; 1321
	add	dx,ax			; 1324
	mov	word ptr [bp - 0ch],dx	; 1326
	mov	al,byte ptr [bp - 012h]	; 1329
	cbw				; 132c
	or	ax,ax			; 132d
	jz	L_bsf_1349		; 132f
	cmp	byte ptr [bp - 011h],00h	; 1331
	jz	L_bsf_13b3		; 1335
	mov	ax,word ptr [bp + 08h]	; 1337
	cmp	ax,word ptr [_g_graphics_context.nClip_xmin]	; 133a
	jl	L_bsf_136a		; 133e
	mov	ax,word ptr [bp - 0ch]	; 1340
	cmp	ax,word ptr [_g_graphics_context.nClip_xmax]	; 1343
	jg	L_bsf_136a		; 1347
L_bsf_1349:
	push	di			; 1349
	mov	al,byte ptr [bp - 018h]	; 134a
	add	al,byte ptr [bp - 017h]	; 134d
	db	030h, 0E4h		; 1350  xor ah,ah (store encoding)
	db	088h, 0E5h		; 1352  mov ch,ah (store encoding)
	mov	bx,word ptr [bp + 08h]	; 1354
	mov	cl,byte ptr [bp - 01h]	; 1357
	mov	di,word ptr [bp - 014h]	; 135a
	mov	es,word ptr [bp - 016h]	; 135d
	mov	dx,word ptr [bp + 0ah]	; 1360
	call	dword ptr [_g_renderer_pfn_fill_run_a]	; 1363
	pop	di			; 1367
	jmp	short L_bsf_13b3	; 1368
L_bsf_136a:
	mov	ax,word ptr [bp + 08h]	; 136a
	cmp	ax,word ptr [_g_graphics_context.nClip_xmin]	; 136d
	jge	L_bsf_1396		; 1371
	mov	ax,word ptr [_g_graphics_context.nClip_xmin]	; 1373
	sub	ax,word ptr [bp + 08h]	; 1376
	mov	word ptr [bp - 0eh],ax	; 1379
	cmp	ax,03fh			; 137c
	jg	L_bsf_13b3		; 137f
	mov	al,byte ptr [bp - 01h]	; 1381
	sub	al,byte ptr [bp - 0eh]	; 1384
	mov	byte ptr [bp - 01h],al	; 1387
	or	al,al			; 138a
	jle	L_bsf_13b3		; 138c
	mov	ax,word ptr [bp - 0eh]	; 138e
	add	word ptr [bp + 08h],ax	; 1391
	jmp	L_bsf_1349		; 1394
L_bsf_1396:
	mov	ax,word ptr [bp - 0ch]	; 1396
	sub	ax,word ptr [_g_graphics_context.nClip_xmax]	; 1399
	dec	ax			; 139d
	mov	word ptr [bp - 0eh],ax	; 139e
	cmp	ax,03fh			; 13a1
	jg	L_bsf_13b3		; 13a4
	mov	al,byte ptr [bp - 01h]	; 13a6
	sub	al,byte ptr [bp - 0eh]	; 13a9
	mov	byte ptr [bp - 01h],al	; 13ac
	or	al,al			; 13af
	jg	L_bsf_1349		; 13b1
L_bsf_13b3:
	mov	ax,word ptr [bp - 0ch]	; 13b3
	mov	word ptr [bp + 08h],ax	; 13b6
	jmp	L_bsf_1085		; 13b9
L_bsf_13bc:
	test	byte ptr [bp - 01h],040h	; 13bc
	jz	L_bsf_13e5		; 13c0
	and	byte ptr [bp - 01h],03fh	; 13c2
	jnz	L_bsf_13cb		; 13c6
	jmp	L_bsf_147f		; 13c8
L_bsf_13cb:
	test	byte ptr [bp + 0ch],02h	; 13cb
	jz	L_bsf_13db		; 13cf
	mov	al,byte ptr [bp - 01h]	; 13d1
	cbw				; 13d4
	sub	word ptr [bp + 08h],ax	; 13d5
	jmp	L_bsf_1085		; 13d8
L_bsf_13db:
	mov	al,byte ptr [bp - 01h]	; 13db
	cbw				; 13de
	add	word ptr [bp + 08h],ax	; 13df
	jmp	L_bsf_1085		; 13e2
L_bsf_13e5:
	and	byte ptr [bp - 01h],03fh	; 13e5
	mov	ax,word ptr [bp - 0ah]	; 13e9
	add	word ptr [bp + 0ah],ax	; 13ec
	mov	al,byte ptr [bp - 012h]	; 13ef
	cbw				; 13f2
	or	ax,ax			; 13f3
	jz	L_bsf_1414		; 13f5
	mov	ax,word ptr [bp + 0ah]	; 13f7
	cmp	ax,word ptr [_g_graphics_context.nClip_ymax]	; 13fa
	jg	L_bsf_140b		; 13fe
	cmp	ax,word ptr [_g_graphics_context.nClip_ymin]	; 1400
	jl	L_bsf_140b		; 1404
	mov	ax,00001h		; 1406
	jmp	short L_bsf_140d	; 1409
L_bsf_140b:
	xor	ax,ax			; 140b
L_bsf_140d:
	mov	byte ptr [bp - 011h],al	; 140d
	or	al,al			; 1410
	jz	L_bsf_1420		; 1412
L_bsf_1414:
	mov	bx,word ptr [bp + 0ah]	; 1414
	shl	bx,01h			; 1417
	mov	ax,word ptr [bx + _g_pRow_offset_lut]	; 1419
	mov	word ptr [bp - 014h],ax	; 141d
L_bsf_1420:
	test	byte ptr [bp + 0ch],02h	; 1420
	jz	L_bsf_142f		; 1424
	mov	al,byte ptr [bp - 01h]	; 1426
	cbw				; 1429
	add	word ptr [bp + 08h],ax	; 142a
	jmp	short L_bsf_1436	; 142d
L_bsf_142f:
	mov	al,byte ptr [bp - 01h]	; 142f
	cbw				; 1432
	sub	word ptr [bp + 08h],ax	; 1433
L_bsf_1436:
	les	bx,[bp - 06h]		; 1436
	mov	al,byte ptr es:[bx]	; 1439
	mov	byte ptr [bp - 01h],al	; 143c
	cbw				; 143f
	test	ax,0c0h			; 1440
	jz	L_bsf_1448		; 1443
	jmp	L_bsf_1085		; 1445
L_bsf_1448:
	mov	al,byte ptr [bp - 01h]	; 1448
	cbw				; 144b
	and	ax,03fh			; 144c
	mov	word ptr [bp - 08h],ax	; 144f
	or	ax,ax			; 1452
	jnz	L_bsf_1459		; 1454
	jmp	L_bsf_1085		; 1456
L_bsf_1459:
	inc	word ptr [bp - 06h]	; 1459
	mov	cl,06h			; 145c
	shl	word ptr [bp - 08h],cl	; 145e
	test	byte ptr [bp + 0ch],02h	; 1461
	jz	L_bsf_1473		; 1465
	mov	ax,word ptr [bp + 08h]	; 1467
	add	ax,word ptr [bp - 08h]	; 146a
	mov	word ptr [bp + 08h],ax	; 146d
	jmp	L_bsf_1085		; 1470
L_bsf_1473:
	mov	ax,word ptr [bp + 08h]	; 1473
	sub	ax,word ptr [bp - 08h]	; 1476
	mov	word ptr [bp + 08h],ax	; 1479
	jmp	L_bsf_1085		; 147c
L_bsf_147f:
	pop	di			; 147f
	pop	si			; 1480
	mov	sp,bp			; 1481
	pop	bp			; 1483
	retf				; 1484
_blit_sprite_flipped_clipped	endp

S180C_TEXT	ends

	end
