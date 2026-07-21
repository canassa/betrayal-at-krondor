; ============================================================================
; POLYCLIP.ASM -- KRONDOR.EXE polygon-viewport clipper (segment 180c).
; Single member: polygon_clip_viewport (180c:1963, linear 0x19ae3, 1153 bytes).
;
; Sutherland-Hodgman polygon clipper against the active viewport.
; Reads input vertex arrays g_anPolygonX / g_anPolygonY (count in
; g_nPolygonClipVertexCount), clips each edge against
; g_clip_xmin/xmax/ymin/ymax with line-intersection interpolation, and
; ping-pongs the clipped polygon through g_anPolygonXClipped /
; g_anPolygonYClipped on each pass.  X-pass writes clipped -> working
; buffers; Y-pass reads working buffers and writes back into the input
; arrays.
;
; WHY ASM: frameless, register-convention Sutherland-Hodgman clipper -- no
; BP frame is set up (PUSH BP / MOV BP,SP), and the whole function threads
; its state through DI (output index), BX (previous vertex), SI (current
; vertex) and CX (packed clip-code pair for both endpoints) with no local
; variables spilled to a stack frame at all. Hand-written for the
; register-intensive Sutherland-Hodgman inner loop.
;
; No CS-resident data (this function has no data island).
; All DGROUP fields are interior aliases of g_graphics_context, accessed via
; gfxctx.inc EQUs.  No hardcoded offsets; all data referenced by symbol.
;
; Called as: void __cdecl16far polygon_clip_viewport(void)
; Ends with RETF -> proc far.
; ============================================================================

	.286

	include	gfxctx.inc	; _g_graphics_context.nClip_xmin/xmax/ymin/ymax, _g_graphics_context.pPolygonX/Y,
				; _g_graphics_context.pPolygonXClipped/YClipped,
				; _g_graphics_context.nPolygonClipVertexCount

	; medium-model group, so DGROUP / ASSUME DS:DGROUP resolve
_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_polygon_clip_viewport

; ----------------------------------------------------------------------------
; void polygon_clip_viewport(void)
; ----------------------------------------------------------------------------
_polygon_clip_viewport	proc far
; 180c:1a23
	xor	di,di
	mov	ax,word ptr [_g_graphics_context.nPolygonClipVertexCount]
	cmp	ax,1h
	jg	short L_9af0
	jmp	L_9f63
L_9af0:
; 180c:1a30
	dec	ax
	mov	bx,ax
	shl	bx,1h
	xor	cl,cl
	mov	ax,word ptr [bx + _g_graphics_context.pPolygonX]
	cmp	ax,word ptr [_g_graphics_context.nClip_xmin]
	jge	short L_9b04
	or	cl,1h
L_9b04:
; 180c:1a44
	cmp	ax,word ptr [_g_graphics_context.nClip_xmax]
	jle	short L_9b0d
	or	cl,2h
L_9b0d:
; 180c:1a4d
	xor	si,si
L_9b0f:
; 180c:1a4f  -- inner loop top: convert SI from index to byte offset, then classify
	shl	si,1h
	xor	ch,ch
	mov	ax,word ptr [si + _g_graphics_context.pPolygonX]
	cmp	ax,word ptr [_g_graphics_context.nClip_xmin]
	jge	short L_9b20
	or	ch,1h
L_9b20:
; 180c:1a60
	cmp	ax,word ptr [_g_graphics_context.nClip_xmax]
	jle	short L_9b29
	or	ch,2h
L_9b29:
; 180c:1a69
	mov	al,cl
	or	al,ch
	jnz	short L_9b45
	mov	ax,word ptr [si + _g_graphics_context.pPolygonX]
	mov	word ptr [di + _g_graphics_context.pPolygonXClipped],ax
	mov	ax,word ptr [si + _g_graphics_context.pPolygonY]
	mov	word ptr [di + _g_graphics_context.pPolygonYClipped],ax
	add	di,2h
	jmp	L_9d01
L_9b45:
; 180c:1a85
	mov	al,cl
	and	al,ch
	jz	short L_9b4e
	jmp	L_9d01
L_9b4e:
; 180c:1a8e
	or	cl,cl
	jnz	short L_9bb9
	test	ch,1h
	jz	short L_9b85
	mov	ax,word ptr [_g_graphics_context.nClip_xmin]
	mov	word ptr [di + _g_graphics_context.pPolygonXClipped],ax
	sub	ax,word ptr [si + _g_graphics_context.pPolygonX]
	mov	bp,ax
	mov	ax,word ptr [bx + _g_graphics_context.pPolygonY]
	sub	ax,word ptr [si + _g_graphics_context.pPolygonY]
	imul	bp
	mov	bp,word ptr [bx + _g_graphics_context.pPolygonX]
	sub	bp,word ptr [si + _g_graphics_context.pPolygonX]
	idiv	bp
	add	ax,word ptr [si + _g_graphics_context.pPolygonY]
	mov	word ptr [di + _g_graphics_context.pPolygonYClipped],ax
	add	di,2h
	jmp	short L_9bb6
L_9b85:
; 180c:1ac5
	test	ch,2h
	jz	short L_9bb6
	mov	ax,word ptr [_g_graphics_context.nClip_xmax]
	mov	word ptr [di + _g_graphics_context.pPolygonXClipped],ax
	sub	ax,word ptr [si + _g_graphics_context.pPolygonX]
	mov	bp,ax
	mov	ax,word ptr [bx + _g_graphics_context.pPolygonY]
	sub	ax,word ptr [si + _g_graphics_context.pPolygonY]
	imul	bp
	mov	bp,word ptr [bx + _g_graphics_context.pPolygonX]
	sub	bp,word ptr [si + _g_graphics_context.pPolygonX]
	idiv	bp
	add	ax,word ptr [si + _g_graphics_context.pPolygonY]
	mov	word ptr [di + _g_graphics_context.pPolygonYClipped],ax
	add	di,2h
L_9bb6:
; 180c:1af6
	jmp	L_9d01
L_9bb9:
; 180c:1af9
	or	ch,ch
	jz	short L_9bbf
	jmp	short L_9c39
L_9bbf:
; 180c:1aff
	test	cl,1h
	jz	short L_9bf2
	mov	ax,word ptr [_g_graphics_context.nClip_xmin]
	mov	word ptr [di + _g_graphics_context.pPolygonXClipped],ax
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonX]
	mov	bp,ax
	mov	ax,word ptr [si + _g_graphics_context.pPolygonY]
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonY]
	imul	bp
	mov	bp,word ptr [si + _g_graphics_context.pPolygonX]
	sub	bp,word ptr [bx + _g_graphics_context.pPolygonX]
	idiv	bp
	add	ax,word ptr [bx + _g_graphics_context.pPolygonY]
	mov	word ptr [di + _g_graphics_context.pPolygonYClipped],ax
	add	di,2h
	jmp	short L_9c23
L_9bf2:
; 180c:1b32
	test	cl,2h
	jz	short L_9c23
	mov	ax,word ptr [_g_graphics_context.nClip_xmax]
	mov	word ptr [di + _g_graphics_context.pPolygonXClipped],ax
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonX]
	mov	bp,ax
	mov	ax,word ptr [si + _g_graphics_context.pPolygonY]
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonY]
	imul	bp
	mov	bp,word ptr [si + _g_graphics_context.pPolygonX]
	sub	bp,word ptr [bx + _g_graphics_context.pPolygonX]
	idiv	bp
	add	ax,word ptr [bx + _g_graphics_context.pPolygonY]
	mov	word ptr [di + _g_graphics_context.pPolygonYClipped],ax
	add	di,2h
L_9c23:
; 180c:1b63
	mov	ax,word ptr [si + _g_graphics_context.pPolygonX]
	mov	word ptr [di + _g_graphics_context.pPolygonXClipped],ax
	mov	ax,word ptr [si + _g_graphics_context.pPolygonY]
	mov	word ptr [di + _g_graphics_context.pPolygonYClipped],ax
	add	di,2h
	jmp	L_9d01
L_9c39:
; 180c:1b79
	test	cl,1h
	jz	short L_9c6c
	mov	ax,word ptr [_g_graphics_context.nClip_xmin]
	mov	word ptr [di + _g_graphics_context.pPolygonXClipped],ax
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonX]
	mov	bp,ax
	mov	ax,word ptr [si + _g_graphics_context.pPolygonY]
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonY]
	imul	bp
	mov	bp,word ptr [si + _g_graphics_context.pPolygonX]
	sub	bp,word ptr [bx + _g_graphics_context.pPolygonX]
	idiv	bp
	add	ax,word ptr [bx + _g_graphics_context.pPolygonY]
	mov	word ptr [di + _g_graphics_context.pPolygonYClipped],ax
	add	di,2h
	jmp	short L_9c9d
L_9c6c:
; 180c:1bac
	test	cl,2h
	jz	short L_9c9d
	mov	ax,word ptr [_g_graphics_context.nClip_xmax]
	mov	word ptr [di + _g_graphics_context.pPolygonXClipped],ax
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonX]
	mov	bp,ax
	mov	ax,word ptr [si + _g_graphics_context.pPolygonY]
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonY]
	imul	bp
	mov	bp,word ptr [si + _g_graphics_context.pPolygonX]
	sub	bp,word ptr [bx + _g_graphics_context.pPolygonX]
	idiv	bp
	add	ax,word ptr [bx + _g_graphics_context.pPolygonY]
	mov	word ptr [di + _g_graphics_context.pPolygonYClipped],ax
	add	di,2h
L_9c9d:
; 180c:1bdd
	test	ch,1h
	jz	short L_9cd0
	mov	ax,word ptr [_g_graphics_context.nClip_xmin]
	mov	word ptr [di + _g_graphics_context.pPolygonXClipped],ax
	sub	ax,word ptr [si + _g_graphics_context.pPolygonX]
	mov	bp,ax
	mov	ax,word ptr [bx + _g_graphics_context.pPolygonY]
	sub	ax,word ptr [si + _g_graphics_context.pPolygonY]
	imul	bp
	mov	bp,word ptr [bx + _g_graphics_context.pPolygonX]
	sub	bp,word ptr [si + _g_graphics_context.pPolygonX]
	idiv	bp
	add	ax,word ptr [si + _g_graphics_context.pPolygonY]
	mov	word ptr [di + _g_graphics_context.pPolygonYClipped],ax
	add	di,2h
	jmp	short L_9d01
L_9cd0:
; 180c:1c10
	test	ch,2h
	jz	short L_9d01
	mov	ax,word ptr [_g_graphics_context.nClip_xmax]
	mov	word ptr [di + _g_graphics_context.pPolygonXClipped],ax
	sub	ax,word ptr [si + _g_graphics_context.pPolygonX]
	mov	bp,ax
	mov	ax,word ptr [bx + _g_graphics_context.pPolygonY]
	sub	ax,word ptr [si + _g_graphics_context.pPolygonY]
	imul	bp
	mov	bp,word ptr [bx + _g_graphics_context.pPolygonX]
	sub	bp,word ptr [si + _g_graphics_context.pPolygonX]
	idiv	bp
	add	ax,word ptr [si + _g_graphics_context.pPolygonY]
	mov	word ptr [di + _g_graphics_context.pPolygonYClipped],ax
	add	di,2h
L_9d01:
; 180c:1c41  -- loop advance: BX = SI (prev = curr), SI = (SI/2 + 1)*2, wrap check
	mov	bx,si
	mov	cl,ch
	shr	si,1h
	inc	si
	cmp	si,word ptr [_g_graphics_context.nPolygonClipVertexCount]
	jz	short L_9d11
	jmp	L_9b0f
L_9d11:
; 180c:1c51  -- end of X-clipping pass: compute output count, store, pivot
	shr	di,1h
	mov	ax,di
	mov	word ptr [_g_graphics_context.nPolygonClipVertexCount],ax
	cmp	ax,1h
	jg	short L_9d20
	jmp	L_9f4c
L_9d20:
; 180c:1c60  -- start Y-clipping pass
	dec	ax
	mov	bx,ax
	shl	bx,1h
	xor	cl,cl
	mov	ax,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	cmp	ax,word ptr [_g_graphics_context.nClip_ymax]
	jle	short L_9d34
	or	cl,4h
L_9d34:
; 180c:1c74
	cmp	ax,word ptr [_g_graphics_context.nClip_ymin]
	jge	short L_9d3d
	or	cl,8h
L_9d3d:
; 180c:1c7d
	xor	di,di
	mov	si,di
L_9d41:
; 180c:1c81
	shl	si,1h
	xor	ch,ch
	mov	ax,word ptr [si + _g_graphics_context.pPolygonYClipped]
	cmp	ax,word ptr [_g_graphics_context.nClip_ymax]
	jle	short L_9d52
	or	ch,4h
L_9d52:
; 180c:1c92
	cmp	ax,word ptr [_g_graphics_context.nClip_ymin]
	jge	short L_9d5b
	or	ch,8h
L_9d5b:
; 180c:1c9b
	mov	al,cl
	or	al,ch
	jnz	short L_9d77
	mov	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	mov	word ptr [di + _g_graphics_context.pPolygonX],ax
	mov	ax,word ptr [si + _g_graphics_context.pPolygonYClipped]
	mov	word ptr [di + _g_graphics_context.pPolygonY],ax
	add	di,2h
	jmp	L_9f33
L_9d77:
; 180c:1cb7
	mov	al,cl
	and	al,ch
	jz	short L_9d80
	jmp	L_9f33
L_9d80:
; 180c:1cc0
	or	cl,cl
	jnz	short L_9deb
	test	ch,8h
	jz	short L_9db7
	mov	ax,word ptr [_g_graphics_context.nClip_ymin]
	mov	word ptr [di + _g_graphics_context.pPolygonY],ax
	sub	ax,word ptr [si + _g_graphics_context.pPolygonYClipped]
	mov	bp,ax
	mov	ax,word ptr [bx + _g_graphics_context.pPolygonXClipped]
	sub	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	imul	bp
	mov	bp,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	sub	bp,word ptr [si + _g_graphics_context.pPolygonYClipped]
	idiv	bp
	add	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	mov	word ptr [di + _g_graphics_context.pPolygonX],ax
	add	di,2h
	jmp	short L_9de8
L_9db7:
; 180c:1cf7
	test	ch,4h
	jz	short L_9de8
	mov	ax,word ptr [_g_graphics_context.nClip_ymax]
	mov	word ptr [di + _g_graphics_context.pPolygonY],ax
	sub	ax,word ptr [si + _g_graphics_context.pPolygonYClipped]
	mov	bp,ax
	mov	ax,word ptr [bx + _g_graphics_context.pPolygonXClipped]
	sub	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	imul	bp
	mov	bp,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	sub	bp,word ptr [si + _g_graphics_context.pPolygonYClipped]
	idiv	bp
	add	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	mov	word ptr [di + _g_graphics_context.pPolygonX],ax
	add	di,2h
L_9de8:
; 180c:1d28
	jmp	L_9f33
L_9deb:
; 180c:1d2b
	or	ch,ch
	jz	short L_9df1
	jmp	short L_9e6b
L_9df1:
; 180c:1d31
	test	cl,8h
	jz	short L_9e24
	mov	ax,word ptr [_g_graphics_context.nClip_ymin]
	mov	word ptr [di + _g_graphics_context.pPolygonY],ax
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	mov	bp,ax
	mov	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonXClipped]
	imul	bp
	mov	bp,word ptr [si + _g_graphics_context.pPolygonYClipped]
	sub	bp,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	idiv	bp
	add	ax,word ptr [bx + _g_graphics_context.pPolygonXClipped]
	mov	word ptr [di + _g_graphics_context.pPolygonX],ax
	add	di,2h
	jmp	short L_9e55
L_9e24:
; 180c:1d64
	test	cl,4h
	jz	short L_9e55
	mov	ax,word ptr [_g_graphics_context.nClip_ymax]
	mov	word ptr [di + _g_graphics_context.pPolygonY],ax
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	mov	bp,ax
	mov	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonXClipped]
	imul	bp
	mov	bp,word ptr [si + _g_graphics_context.pPolygonYClipped]
	sub	bp,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	idiv	bp
	add	ax,word ptr [bx + _g_graphics_context.pPolygonXClipped]
	mov	word ptr [di + _g_graphics_context.pPolygonX],ax
	add	di,2h
L_9e55:
; 180c:1d95
	mov	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	mov	word ptr [di + _g_graphics_context.pPolygonX],ax
	mov	ax,word ptr [si + _g_graphics_context.pPolygonYClipped]
	mov	word ptr [di + _g_graphics_context.pPolygonY],ax
	add	di,2h
	jmp	L_9f33
L_9e6b:
; 180c:1dab
	test	cl,8h
	jz	short L_9e9e
	mov	ax,word ptr [_g_graphics_context.nClip_ymin]
	mov	word ptr [di + _g_graphics_context.pPolygonY],ax
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	mov	bp,ax
	mov	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonXClipped]
	imul	bp
	mov	bp,word ptr [si + _g_graphics_context.pPolygonYClipped]
	sub	bp,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	idiv	bp
	add	ax,word ptr [bx + _g_graphics_context.pPolygonXClipped]
	mov	word ptr [di + _g_graphics_context.pPolygonX],ax
	add	di,2h
	jmp	short L_9ecf
L_9e9e:
; 180c:1dde
	test	cl,4h
	jz	short L_9ecf
	mov	ax,word ptr [_g_graphics_context.nClip_ymax]
	mov	word ptr [di + _g_graphics_context.pPolygonY],ax
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	mov	bp,ax
	mov	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	sub	ax,word ptr [bx + _g_graphics_context.pPolygonXClipped]
	imul	bp
	mov	bp,word ptr [si + _g_graphics_context.pPolygonYClipped]
	sub	bp,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	idiv	bp
	add	ax,word ptr [bx + _g_graphics_context.pPolygonXClipped]
	mov	word ptr [di + _g_graphics_context.pPolygonX],ax
	add	di,2h
L_9ecf:
; 180c:1e0f
	test	ch,8h
	jz	short L_9f02
	mov	ax,word ptr [_g_graphics_context.nClip_ymin]
	mov	word ptr [di + _g_graphics_context.pPolygonY],ax
	sub	ax,word ptr [si + _g_graphics_context.pPolygonYClipped]
	mov	bp,ax
	mov	ax,word ptr [bx + _g_graphics_context.pPolygonXClipped]
	sub	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	imul	bp
	mov	bp,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	sub	bp,word ptr [si + _g_graphics_context.pPolygonYClipped]
	idiv	bp
	add	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	mov	word ptr [di + _g_graphics_context.pPolygonX],ax
	add	di,2h
	jmp	short L_9f33
L_9f02:
; 180c:1e42
	test	ch,4h
	jz	short L_9f33
	mov	ax,word ptr [_g_graphics_context.nClip_ymax]
	mov	word ptr [di + _g_graphics_context.pPolygonY],ax
	sub	ax,word ptr [si + _g_graphics_context.pPolygonYClipped]
	mov	bp,ax
	mov	ax,word ptr [bx + _g_graphics_context.pPolygonXClipped]
	sub	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	imul	bp
	mov	bp,word ptr [bx + _g_graphics_context.pPolygonYClipped]
	sub	bp,word ptr [si + _g_graphics_context.pPolygonYClipped]
	idiv	bp
	add	ax,word ptr [si + _g_graphics_context.pPolygonXClipped]
	mov	word ptr [di + _g_graphics_context.pPolygonX],ax
	add	di,2h
L_9f33:
; 180c:1e73  -- Y-pass loop advance
	mov	bx,si
	mov	cl,ch
	shr	si,1h
	inc	si
	cmp	si,word ptr [_g_graphics_context.nPolygonClipVertexCount]
	jz	short L_9f43
	jmp	L_9d41
L_9f43:
; 180c:1e83  -- end of Y-clipping pass: store final count
	shr	di,1h
	mov	ax,di
	mov	word ptr [_g_graphics_context.nPolygonClipVertexCount],ax
	jmp	short L_9f63
L_9f4c:
; 180c:1e8c  -- fallback: count < 2 after X-pass, copy clipped -> input arrays via REP MOVSW
	mov	ax,word ptr [_g_graphics_context.nPolygonClipVertexCount]
	mov	cx,ax
	mov	si,offset DGROUP:_g_graphics_context.pPolygonXClipped
	mov	di,offset DGROUP:_g_graphics_context.pPolygonX
	rep	movsw
	mov	cx,ax
	mov	si,offset DGROUP:_g_graphics_context.pPolygonYClipped
	mov	di,offset DGROUP:_g_graphics_context.pPolygonY
	rep	movsw
L_9f63:
; 180c:1ea3
	retf
_polygon_clip_viewport	endp

S180C_TEXT	ends
	end
