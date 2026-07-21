; ============================================================================
; VGABLIT.ASM -- KRONDOR.EXE segments 0x14b6 + 0x14c1: the VGA Mode-X planar
;                rectangle-fill + run/span blitter (the "vgablit" module)
;
; ONE module spanning TWO physically-contiguous FBOV code segments whose code
; crosses a paragraph boundary. It declares both S14B6_TEXT (segment 0x14b6) and
; S14C1_TEXT (segment 0x14c1) in address order:
;
;   S14B6_TEXT (0x14b6)  the rectangle-list solid fill:
;       _vga_planar_fill_rects  0x16  planar Mode-X solid fill of a (y0,y1,x0,x1)
;                                     rectangle list, with CS-resident plane-mask
;                                     LUTs + scratch cells in the segment head.
;   S14C1_TEXT (0x14c1)  the run/span blitter:
;       _vgablit_planar_runs         0x2c  copies RLE-style pixel runs into VRAM
;       _vgablit_span_emit_textured  0x135 1-run wrapper -> near-calls planar_runs
;       _vgablit_planar_runs_untiled 0x165 strided-source variant of planar_runs
;
; The two segments overlap by one paragraph: _vga_planar_fill_rects' last 9 bytes
; (14b6:0xb0..0xb8) physically alias the head of segment 0x14c1 (14c1:0x00..0x08).
; Both segments carry CS-resident data + hand-written idioms (non-standard
; far-call entry with no BP frame; LODSW/STOSB/REP string fills; CS-relative LUT +
; scratch reads/writes via a 2e override).
;
; CONVENTIONS:
;   1. `.386` (VGABLIT's Sequencer word-writes) governs the whole module; every
;      S14B6_TEXT instruction is a 16-bit form whose encoding is identical under
;      .286 and .386 in a use16 segment.
;   2. Each segment is `word public use16 'CODE'`, content-only (no org/pad): the
;      module starts at each segment's first content byte (14b6 FBOV min=0x06,
;      14c1 min=0x0a). The bytes below each min belong to the PREVIOUS segment's
;      tail; the link's canonic frame re-emerges the original frame-relative
;      displacements via same-segment OFFSET_16 fixups.
;   3. Functions are plain PUBLIC labels ending in explicit `retf`, entered by far
;      CALL from outside; an in-segment call keeps the explicit `push cs` + near
;      `call` (no `proc far` auto-PUSH-CS).
;   4. In-segment CS-resident data is referenced by NAMED LABEL with an explicit
;      `cs:` override (the bytes carry the 2e prefix).
;   5. DGROUP globals are `extrn` + the gfxctx interior-field `equ` idiom; they
;      relocate via FIXUPP.
; ============================================================================

	.386

; --- DGROUP externals (hoisted union of both segments' uses) -----------------
	extrn	_g_graphics_context:byte
_g_bGfx_fill_color	equ	_g_graphics_context + 00dh	; gfxctx +0x0d
_g_wGfxBlitDstPage	equ	_g_graphics_context + 018h	; gfxctx +0x18
_g_pRow_offset_lut	equ	_g_graphics_context + 6f2h	; gfxctx +0x6f2 (dw[200])

; --- segment declarations ----------------------------------------------------
DGROUP	group	_DATA,_BSS
_DATA	segment word public use16 'DATA'
_DATA	ends
_BSS	segment word public use16 'BSS'
_BSS	ends

; ============================================================================
; S14B6_TEXT (segment 0x14b6) — the rectangle-list solid fill.
;
; WORD-aligned, content only: the module starts at the segment's first content
; byte (FBOV min=0x06). The 6 bytes below that belong to the PREVIOUS segment's
; tail — the paragraph frame rounds down, so minoff re-emerges from the link
; packing; hardcoding it here (pad bytes or org) would inflate the linked
; footprint and shift every later segment. Same-segment label references carry
; self-ref OFFSET_16 fixups that TLINK resolves against the canonic frame, so the
; original frame-relative displacements (0x06, 0x0a, …) re-emerge.
; ============================================================================
S14B6_TEXT	segment word public use16 'CODE'
	assume	cs:S14B6_TEXT, ds:DGROUP

	public	_vga_planar_fill_rects

; ── 0x06..0x09: same-cell right-edge plane-mask LUT ──────────────────────────
; Indexed by (x1 + 1) & 3 = (right_col + 1) & 3; value = low-nibble column mask:
;   idx 0 (x1 at col 3, right edge fills all 4 cols): 0x0f
;   idx 1 (x1 at col 0, 1 col):                       0x01
;   idx 2 (x1 at col 1, 2 cols):                      0x03
;   idx 3 (x1 at col 2, 3 cols):                      0x07
; (idx 0 is 0x0f, not 0xff: the Sequencer Map-Mask ignores the high nibble, but
;  the original table stores the 4-plane low-nibble form.)
_lut_left_edge:
	db	00fh, 001h, 003h, 007h

; ── 0x0a..0x0d: leading (left-edge) plane-mask LUT ───────────────────────────
; Indexed by left_col (x0 & 3):
;   col 0: 0x0f (all 4 planes)
;   col 1: 0x0e (planes 1+2+3)
;   col 2: 0x0c (planes 2+3)
;   col 3: 0x08 (plane 3 only)
_lut_leading:
	db	00fh, 00eh, 00ch, 008h

; ── 0x0e..0x11: trailing (right-edge) plane-mask LUT ────────────────────────
; Indexed by (width + left_col) & 3 = (right_col + 1) & 3; value = 2^idx - 1:
;   idx 0 (right_col 3, trailing byte already fully drawn by the run): 0x00 (no-op)
;   idx 1 (right_col 0, 1 col):  0x01 (plane 0)
;   idx 2 (right_col 1, 2 cols): 0x03 (planes 0+1)
;   idx 3 (right_col 2, 3 cols): 0x07 (planes 0+1+2)
_lut_trailing:
	db	000h, 001h, 003h, 007h

; ── 0x12..0x13: row counter (scratch, written during function init) ───────────
_row_counter:
	dw	0

; ── 0x14..0x15: replicated fill byte AH:AL (scratch, written during init) ────
_fill_word:
	dw	0

; ── 0x16: function entry ─────────────────────────────────────────────────────
_vga_planar_fill_rects:
	push	ds				; 0016: 1e — save caller's DS
	mov	cx,es				; 0017: 8c c1 — save caller's ES in CX
	mov	es,word ptr [_g_wGfxBlitDstPage]	; 0019: 8e 06 ..  — ES = VRAM page
	mov	al,byte ptr [_g_bGfx_fill_color]	; 001d: a0 ..    — fill colour
	mov	ah,al				; 0020: 8a e0
	mov	word ptr cs:[_fill_word],ax	; 0022: 2e a3 14 00
	mov	ds,cx				; 0026: 8e d9 — DS = caller's ES
	lodsw					; 0028: ad — AX = y0
	shl	ax,4				; 0029: c1 e0 04 — AX = y0 * 16
	mov	bp,ax				; 002c: 89 c5
	shl	ax,2				; 002e: c1 e0 02 — AX = y0 * 64
	add	bp,ax				; 0031: 01 c5 — BP = y0 * 80 = y0 * 0x50
	lodsw					; 0033: ad — AX = row count (y1)
	mov	word ptr cs:[_row_counter],ax	; 0034: 2e a3 12 00
	mov	dx,3c4h				; 3c4h VGA Sequencer I/O port (out dx,al)
	mov	al,2				; 003b: b0 02 — Map-Mask register index
	out	dx,al				; 003d: ee
	inc	dx				; 003e: 42 — DX = 3c5h (data port)
	jmp	short L_inner_start		; 003f: eb 0c — jump to 004d

L_loop_exit:
	pop	ds				; 0041: 1f
	retf					; 0042: cb

L_loop_top:
	dec	word ptr cs:[_row_counter]	; 0043: 2e ff 0e 12 00
	jle	short L_loop_exit		; 0048: 7e f7
	add	bp,50h				; 004a: 83 c5 50

L_inner_start:
	lodsw					; 004d: ad — AX = x0
	mov	bx,ax				; 004e: 89 c3
	lodsw					; 0050: ad — AX = x1
	sub	ax,bx				; 0051: 29 d8 — AX = x1 - x0
	jl	short L_loop_top		; 0053: 7c ee — skip if x1 < x0
	inc	ax				; 0055: 40 — AX = width = x1 - x0 + 1
	mov	cx,ax				; 0056: 89 c1
	mov	di,bx				; 0058: 89 df — DI = x0
	shr	di,2				; 005a: d1 ef — DI = x0 / 4 (byte offset in row)
	add	di,bp				; 005d: 01 ef — DI += row base
	mov	ax,bx				; 005f: 89 d8
	add	ax,cx				; 0061: 01 c8 — AX = x0 + width = x1 + 1
	dec	ax				; 0063: 48 — AX = x1
	xor	ax,bx				; 0064: 31 d8 — AX = x1 ^ x0
	and	ax,0ffch			; 0066: 25 fc 0f — AX & 0xffc
	jz	short L_same_cell		; 0069: 74 32 — if zero: start/end in same cell

	; multi-cell case
	and	bx,3				; 006b: 83 e3 03 — BX = x0 & 3 (left col)
	sub	cx,4				; 006e: 83 e9 04
	add	cx,bx				; 0071: 01 d9 — CX = width - 4 + left_col
	mov	al,byte ptr cs:[bx+_lut_leading]	; 0073: 2e 8a 47 0a — left-edge mask
	out	dx,al				; 0078: ee
	mov	ax,word ptr cs:[_fill_word]	; 0079: 2e a1 14 00
	stosb					; 007d: aa — write left byte
	mov	al,0fh				; 007e: b0 0f — all-planes mask
	out	dx,al				; 0080: ee
	mov	bx,cx				; 0081: 89 cb — BX = word count source
	shr	cx,2				; 0083: d1 e9
	shr	cx,1				; 0086: d1 e9 — CX = word pairs
	mov	al,ah				; 0088: 8a c4 — AL = fill byte (from AH)
	rep	stosw				; 008a: f3 ab
	jnc	short L_no_odd			; 008c: 73 01 — skip if even
	stosb					; 008e: aa — odd trailing byte
L_no_odd:
	and	bx,3				; 008f: 83 e3 03 — BX = right col
	mov	al,byte ptr cs:[bx+_lut_trailing]	; 0092: 2e 8a 47 0e
	out	dx,al				; 0097: ee
	mov	al,ah				; 0098: 8a c4
	stosb					; 009a: aa
	jmp	short L_loop_top		; 009b: eb a6

L_same_cell:
	; both x0 and x1+1 land in the same VGA byte cell
	mov	al,bl				; 009d: 8a c3 — AL = BX (x0 & 3) at this point?
	add	bx,cx				; 009f: 01 cb — BX = x0 + width = x1+1
	and	al,3				; 00a1: 24 03 — AL = x0 & 3 (left col)
	and	bx,3				; 00a3: 83 e3 03 — BX = (x1+1) & 3
	mov	cl,al				; 00a6: 88 c1
	mov	al,0ffh				; 00a8: b0 ff
	shl	al,cl				; 00aa: d2 e0 — left mask = 0xff << left_col
	and	al,byte ptr cs:[bx+_lut_left_edge]	; 00ac: 2e 22 47 06
	; last 9 bytes straddle into segment 14c1 (14c1:0000..0008 = 14b6:00b0..00b8)
	out	dx,al				; (14c1:0001) ee
	mov	al,byte ptr cs:[_fill_word]	; (14c1:0002) 2e a0 14 00
	stosb					; (14c1:0006) aa
	jmp	short L_loop_top		; (14c1:0007) eb 8a — back to L_loop_top (14b6:0043)

S14B6_TEXT	ends

; ============================================================================
; S14C1_TEXT (segment 0x14c1) — the run/span blitter.
;
; Its head (0x0a..0x2b) is a CS-resident parameter/scratch block shared by all
; three functions AND written by EXTERNAL callers via a baked absolute
; `mov es,0x14c1` (sky_draw_ground_band / sky_polygon_draw_dispatch set
; 14c1:0x0c..0x12). The block lives before the first function.
;
; WORD-aligned, content only: the module starts at the segment's first content
; byte (FBOV minoff = 0x0a). Bytes 0x00..0x08 belong to the PREVIOUS segment
; (S14B6_TEXT's function tail crosses into this paragraph) and byte 0x09 is
; TLINK's word-alignment pad (emitted as 0 by the linker itself) — neither is
; this module's to emit or reserve. Label references carry segment-relative
; fixups resolved against the canonic frame, so the original frame offsets
; re-emerge.
; ============================================================================
S14C1_TEXT	segment word public use16 'CODE'
	assume	cs:S14C1_TEXT

	public	_vgablit_planar_runs
	public	_vgablit_span_emit_textured
	public	_vgablit_planar_runs_untiled

	; CS-resident param-block fields written by external callers (e.g.
	; dialog_frame_draw) as far globals via vgablit.h.  Public aliases only —
	; `label word` emits no bytes.
	public	_g_vgablit_si_base
	public	_g_vgablit_si_stride
	public	_g_vgablit_row_count
	public	_g_vgablit_row_sub
	public	_g_vgablit_si_mask

; ── CS-resident parameter / scratch block (frame 0x0a..0x2b) ─────────────────
; Caller-written run parameters + self-modified loop scratch.  Initial image
; bytes shown; patched at runtime.
_src_seg	dw	0ac00h			; frame 0x0a: source pixel-data segment -> DS
_g_vgablit_si_base	label	word
_si_base	dw	0			; 0x0c: source offset base
_g_vgablit_si_stride	label	word
_si_stride	dw	0			; 0x0e: source row stride
_g_vgablit_row_count	label	word
_row_count	dw	0			; 0x10: tiled row count (0 => use si_base)
_g_vgablit_row_sub	label	word
_row_sub	dw	0			; 0x12: tiled row subtract
_g_vgablit_si_mask	label	word
_si_mask	dw	0			; 0x14: untiled source-offset wrap mask
_plane_mask	db	00fh,001h,003h,007h	; 0x16: leading-pixel plane mask LUT[bx&3]
_inner_cnt	dw	0			; 0x1a: inner (per-run) loop counter
_dst_seg	dw	0			; 0x1c: destination VRAM segment
		dw	0			; 0x1e: (unused)
_outer_cnt	dw	0			; 0x20: outer (row) loop counter
_desc_off	dw	0			; 0x22: span_emit descriptor: src offset
_desc_cnt	dw	0			; 0x24:   run count (=1)
_desc_seg	dw	0			; 0x26:   src segment
_desc_dx	dw	0			; 0x28:   colour / dx
		dw	0			; 0x2a: (unused)

; ── _vgablit_planar_runs  (0x002c) ──────────────────────────────────────────
; ES:SI (caller) -> run descriptor list; copies the pixel runs into Mode-X VRAM.
_vgablit_planar_runs:
	push	bp			; 002c: 55
	push	di			; 002d: 57
	push	ds			; 002e: 1e
	mov	bp,si			; 002f: 8bee
	mov	ax,word ptr [_g_wGfxBlitDstPage]	; 0031: a12820
	mov	cs:[_dst_seg],ax	; 0034: 2ea31c00
	mov	bx,es:[bp+0]		; 0038: 268b5e00
	mov	cx,bx			; 003c: 8bcb
	shl	bx,1			; 003e: d1e3
	mov	di,word ptr [bx+_g_pRow_offset_lut] ; 0040: 8bbf0227
	mov	ax,cs:[_row_count]	; 0044: 2ea11000
	mov	cs:[_outer_cnt],ax	; 0048: 2ea32000
	cmp	ax,0			; 004c: 3d0000
	jnz	short L_065		; 004f: 7514
	sub	cx,cs:[_row_sub]	; 0051: 2e2b0e1200
	mov	ax,cs:[_si_stride]	; 0056: 2ea10e00
	mul	cx			; 005a: f7e1
	add	ax,cs:[_si_base]	; 005c: 2e03060c00
	mov	si,ax			; 0061: 8bf0
	jmp	short L_06a		; 0063: eb05
L_065:
	mov	si,cs:[_si_base]	; 0065: 2e8b360c00
L_06a:
	mov	ax,cs:[_src_seg]	; 006a: 2ea10a00
	mov	ds,ax			; 006e: 8ed8
	mov	dx,3ceh			; 0070: bace03 ; 3ceh VGA GC index I/O port (out dx,ax)
	mov	ax,4105h		; 0073: b80541 ; 4105h GC Mode reg word write 05<-41
	out	dx,ax			; 0076: ef
	mov	dx,3c4h			; 0077: bac403 ; 3c4h VGA Sequencer index I/O port (out)
	mov	al,2			; 007a: b002
	out	dx,al			; 007c: ee
	inc	dx			; 007d: 42
	mov	ax,es:[bp+2]		; 007e: 268b4602
	mov	cs:[_inner_cnt],ax	; 0082: 2ea31a00
	add	bp,4			; 0086: 83c504
L_089:
	mov	ax,es:[bp+0]		; 0089: 268b4600
	mov	bx,es:[bp+2]		; 008d: 268b5e02
	mov	cx,ax			; 0091: 8bc8
	add	bp,4			; 0093: 83c504
	xor	ax,bx			; 0096: 33c3
	and	ax,0ffch		; 0098: 25fc0f
	mov	ax,cx			; 009b: 8bc1
	jnz	short L_0c5		; 009d: 7526
	push	es			; 009f: 06
	push	di			; 00a0: 57
	push	si			; 00a1: 56
	mov	es,cs:[_dst_seg]	; 00a2: 2e8e061c00
	mov	cx,ax			; 00a7: 8bc8
	shr	ax,1			; 00a9: d1e8
	shr	ax,1			; 00ab: d1e8
	add	si,ax			; 00ad: 03f0
	add	di,ax			; 00af: 03f8
	and	cx,3			; 00b1: 83e103
	mov	al,0fh			; 00b4: b00f
	shl	al,cl			; 00b6: d2e0
	inc	bx			; 00b8: 43
	and	bx,3			; 00b9: 83e303
	and	al,cs:[bx+_plane_mask]	; 00bc: 2e22871600
	out	dx,al			; 00c1: ee
	movsb				; 00c2: a4
	jmp	short L_101		; 00c3: eb3c
L_0c5:
	push	es			; 00c5: 06
	push	di			; 00c6: 57
	push	si			; 00c7: 56
	mov	es,cs:[_dst_seg]	; 00c8: 2e8e061c00
	mov	cx,ax			; 00cd: 8bc8
	and	cx,3			; 00cf: 83e103
	sub	bx,ax			; 00d2: 2bd8
	jle	short L_101		; 00d4: 7e2b
	shr	ax,1			; 00d6: d1e8
	shr	ax,1			; 00d8: d1e8
	add	si,ax			; 00da: 03f0
	add	di,ax			; 00dc: 03f8
	mov	al,0fh			; 00de: b00f
	shl	al,cl			; 00e0: d2e0
	sub	cx,3			; 00e2: 83e903
	add	bx,cx			; 00e5: 03d9
	out	dx,al			; 00e7: ee
	movsb				; 00e8: a4
	mov	cx,bx			; 00e9: 8bcb
	shr	cx,1			; 00eb: d1e9
	shr	cx,1			; 00ed: d1e9
	mov	al,0fh			; 00ef: b00f
	out	dx,al			; 00f1: ee
	rep	movsb			; 00f2: f3a4
	mov	cx,bx			; 00f4: 8bcb
	and	cx,3			; 00f6: 83e103
	jz	short L_101		; 00f9: 7406
	mov	al,0f0h			; 00fb: b0f0
	rol	al,cl			; 00fd: d2c0
	out	dx,al			; 00ff: ee
	movsb				; 0100: a4
L_101:
	pop	si			; 0101: 5e
	pop	di			; 0102: 5f
	add	di,50h			; 0103: 83c750
	add	si,cs:[_si_stride]	; 0106: 2e03360e00
	dec	word ptr cs:[_outer_cnt]; 010b: 2eff0e2000
	jnz	short L_11f		; 0110: 750d
	mov	si,cs:[_si_base]	; 0112: 2e8b360c00
	mov	ax,cs:[_row_count]	; 0117: 2ea11000
	mov	cs:[_outer_cnt],ax	; 011b: 2ea32000
L_11f:
	pop	es			; 011f: 07
	dec	word ptr cs:[_inner_cnt]; 0120: 2eff0e1a00
	jz	short L_12a		; 0125: 7403
	jmp	L_089			; 0127: e95fff
L_12a:
	mov	dx,3ceh			; 012a: bace03 ; 3ceh VGA GC index I/O port (out dx,ax)
	mov	ax,4005h		; 012d: b80540 ; 4005h GC Mode reg word write 05<-40
	out	dx,ax			; 0130: ef
	pop	ds			; 0131: 1f
	pop	di			; 0132: 5f
	pop	bp			; 0133: 5d
	retf				; 0134: cb

; ── _vgablit_span_emit_textured  (0x0135) ───────────────────────────────────
; if (CX != SI) build a 1-run descriptor {CX, 1, CS, DX} at CS:0x22 and
; near-call _vgablit_planar_runs with ES:SI -> that descriptor.
_vgablit_span_emit_textured:
	push	bp			; 0135: 55
	mov	bp,sp			; 0136: 8bec
	cmp	cx,si			; 0138: 3bce
	jnz	short L_163		; 013a: 7527
	pusha				; 013c: 60
	push	es			; 013d: 06
	push	ds			; 013e: 1e
	mov	cs:[_desc_off],cx	; 013f: 2e890e2200
	mov	word ptr cs:[_desc_cnt],1 ; 0144: 2ec70624000100
	mov	cs:[_desc_seg],bx	; 014b: 2e891e2600
	mov	cs:[_desc_dx],dx	; 0150: 2e89162800
	mov	si,22h			; 0155: be2200
	mov	bx,cs			; 0158: 8ccb
	mov	es,bx			; 015a: 8ec3
	push	cs			; 015c: 0e
	call	_vgablit_planar_runs	; 015d: e8ccfe
	pop	ds			; 0160: 1f
	pop	es			; 0161: 07
	popa				; 0162: 61
L_163:
	pop	bp			; 0163: 5d
	retf				; 0164: cb

; ── _vgablit_planar_runs_untiled  (0x0165) ──────────────────────────────────
; Like _vgablit_planar_runs but advances the source by (si += stride) & si_mask
; each row (untiled / wrapped source) instead of the tiled recompute.
_vgablit_planar_runs_untiled:
	push	bp			; 0165: 55
	push	di			; 0166: 57
	push	ds			; 0167: 1e
	mov	bp,si			; 0168: 8bee
	mov	ax,word ptr [_g_wGfxBlitDstPage]	; 016a: a12820
	mov	cs:[_dst_seg],ax	; 016d: 2ea31c00
	mov	bx,es:[bp+0]		; 0171: 268b5e00
	mov	cx,bx			; 0175: 8bcb
	shl	bx,1			; 0177: d1e3
	mov	di,word ptr [bx+_g_pRow_offset_lut] ; 0179: 8bbf0227
	mov	si,cs:[_si_base]	; 017d: 2e8b360c00
	mov	ax,cs:[_src_seg]	; 0182: 2ea10a00
	mov	ds,ax			; 0186: 8ed8
	mov	dx,3ceh			; 0188: bace03 ; 3ceh VGA GC index I/O port (out dx,ax)
	mov	ax,4105h		; 018b: b80541 ; 4105h GC Mode reg word write 05<-41
	out	dx,ax			; 018e: ef
	mov	dx,3c4h			; 018f: bac403 ; 3c4h VGA Sequencer index I/O port (out)
	mov	al,2			; 0192: b002
	out	dx,al			; 0194: ee
	inc	dx			; 0195: 42
	mov	ax,es:[bp+2]		; 0196: 268b4602
	mov	cs:[_inner_cnt],ax	; 019a: 2ea31a00
	add	bp,4			; 019e: 83c504
L_1a1:
	mov	ax,es:[bp+0]		; 01a1: 268b4600
	mov	bx,es:[bp+2]		; 01a5: 268b5e02
	mov	cx,ax			; 01a9: 8bc8
	add	bp,4			; 01ab: 83c504
	xor	ax,bx			; 01ae: 33c3
	and	ax,0ffch		; 01b0: 25fc0f
	mov	ax,cx			; 01b3: 8bc1
	jnz	short L_1dd		; 01b5: 7526
	push	es			; 01b7: 06
	push	di			; 01b8: 57
	push	si			; 01b9: 56
	mov	es,cs:[_dst_seg]	; 01ba: 2e8e061c00
	mov	cx,ax			; 01bf: 8bc8
	shr	ax,1			; 01c1: d1e8
	shr	ax,1			; 01c3: d1e8
	add	si,ax			; 01c5: 03f0
	add	di,ax			; 01c7: 03f8
	and	cx,3			; 01c9: 83e103
	mov	al,0fh			; 01cc: b00f
	shl	al,cl			; 01ce: d2e0
	inc	bx			; 01d0: 43
	and	bx,3			; 01d1: 83e303
	and	al,cs:[bx+_plane_mask]	; 01d4: 2e22871600
	out	dx,al			; 01d9: ee
	movsb				; 01da: a4
	jmp	short L_219		; 01db: eb3c
L_1dd:
	push	es			; 01dd: 06
	push	di			; 01de: 57
	push	si			; 01df: 56
	mov	es,cs:[_dst_seg]	; 01e0: 2e8e061c00
	mov	cx,ax			; 01e5: 8bc8
	and	cx,3			; 01e7: 83e103
	sub	bx,ax			; 01ea: 2bd8
	jle	short L_219		; 01ec: 7e2b
	shr	ax,1			; 01ee: d1e8
	shr	ax,1			; 01f0: d1e8
	add	si,ax			; 01f2: 03f0
	add	di,ax			; 01f4: 03f8
	mov	al,0fh			; 01f6: b00f
	shl	al,cl			; 01f8: d2e0
	sub	cx,3			; 01fa: 83e903
	add	bx,cx			; 01fd: 03d9
	out	dx,al			; 01ff: ee
	movsb				; 0200: a4
	mov	cx,bx			; 0201: 8bcb
	shr	cx,1			; 0203: d1e9
	shr	cx,1			; 0205: d1e9
	mov	al,0fh			; 0207: b00f
	out	dx,al			; 0209: ee
	rep	movsb			; 020a: f3a4
	mov	cx,bx			; 020c: 8bcb
	and	cx,3			; 020e: 83e103
	jz	short L_219		; 0211: 7406
	mov	al,0f0h			; 0213: b0f0
	rol	al,cl			; 0215: d2c0
	out	dx,al			; 0217: ee
	movsb				; 0218: a4
L_219:
	pop	si			; 0219: 5e
	pop	di			; 021a: 5f
	add	di,50h			; 021b: 83c750
	add	si,cs:[_si_stride]	; 021e: 2e03360e00
	and	si,cs:[_si_mask]	; 0223: 2e23361400
	pop	es			; 0228: 07
	dec	word ptr cs:[_inner_cnt]; 0229: 2eff0e1a00
	jz	short L_233		; 022e: 7403
	jmp	L_1a1			; 0230: e96eff
L_233:
	mov	dx,3ceh			; 0233: bace03 ; 3ceh VGA GC index I/O port (out dx,ax)
	mov	ax,4005h		; 0236: b80540 ; 4005h GC Mode reg word write 05<-40
	out	dx,ax			; 0239: ef
	pop	ds			; 023a: 1f
	pop	di			; 023b: 5f
	pop	bp			; 023c: 5d
	retf				; 023d: cb

S14C1_TEXT	ends
	end
