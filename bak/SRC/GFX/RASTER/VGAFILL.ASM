; ============================================================================
; VGAFILL.ASM -- KRONDOR.EXE segment 0x204a: the VGA Mode-X planar shaded
;                column/band fill primitives ("the vgaplanar fill segment")
;
; ONE module covering segment 0x204a: its CS-resident shade-gradient table
; (offsets 0x0c..0x2d) plus both of its functions:
;
;   _vgaplanar_clear_column_strip 0x002e  draws a vertical shaded column strip
;                                         into Mode-X planar VRAM; each row's
;                                         fill byte comes from the CS-resident
;                                         shade ramp (cs:[bx+_shade_table])
;   _vgaplanar_fill_band          0x009a  fills a horizontal band of scanlines
;                                         with a solid colour byte taken as a
;                                         parameter (no shade table)
;
; The shade-gradient table is CS-resident data embedded in the code segment at
; offset 0x0c, read by _vgaplanar_clear_column_strip via an explicit CS: override
; (`mov al, byte ptr cs:[bx+_shade_table]`); it lives before the first function
; in the segment head. Both functions load ES once from
; g_graphics_context.wGfxBlitDstPage and write the framebuffer through ES:DI with
; STOSB / REP STOSW, and program the Sequencer Map-Mask with inline `OUT DX,AX`
; keeping DX live across all three plane-mask passes.
;
; CONVENTIONS:
;   1. `segment para public` + `assume cs:S204A_TEXT`; the segment's own content
;      (lead byte + shade table) starts at offset 0x0b; 0x00..0x0a are the tail
;      of the prior segment (14b... epilogue) that overruns this paragraph and
;      are NOT emitted here.
;   2. `para public` (not byte): the module must be paragraph-aligned so the
;      in-segment data label (_shade_table, a CS-relative offset) lands at
;      offset 0x0c at runtime; a byte-aligned placement shifts it.
;   3. Functions are plain PUBLIC labels (not `proc far`) ending in explicit
;      `retf`; entered by far CALL from outside. They do not call each other.
;   4. In-segment CS-resident data is referenced by named label with an explicit
;      `cs:` override (the bytes carry the 2e prefix):
;      `mov al, byte ptr cs:[bx+_shade_table]`.
;   5. The DGROUP global g_graphics_context is `extrn`; its +0x18 field
;      (wGfxBlitDstPage, the active blit-page segment) relocates via FIXUPP.
;
; The VGA Mode-X plane select is programmed through the Sequencer Map-Mask
; (port 0x3c4, index 2); the three passes paint left edge (planes 1-3,
; mask 0x0e), the all-planes middle run (mask 0x0f, 0x24 words/row), and the
; right edge (planes 0-2, mask 0x07).  Row stride is 0x50 (320/4 = mode-X).
; ============================================================================

; ----------------------------------------------------------------------------
; Hardware primer: VGA Mode-X planar VRAM and the Sequencer Map-Mask
;
; "Mode-X" is the unofficial 320x240 256-colour VGA mode used by most DOS
; games of the era.  Unlike the simple "mode 13h" (where one byte in VRAM is
; one on-screen pixel), Mode-X splits the screen into FOUR interleaved memory
; "planes".  Pixel N on a row lives in plane (N & 3), at byte offset (N >> 2)
; within that plane.  All four planes share the same VRAM address space: a
; single write to ES:[DI] can land in any subset of the four planes, chosen by
; a hardware mask.  A whole scanline of 320 pixels is therefore 320/4 = 80 =
; 0x50 bytes wide PER PLANE -- that is the "row stride" 0x50 used throughout
; this file.  Stepping DI back by 0x50 moves up one scanline.
;
; The mask that decides which planes a write hits is the VGA "Sequencer
; Map-Mask" register.  The Sequencer is reached through two I/O ports:
;
;   port 0x3c4  (index port) -- write the number of the Sequencer register
;                               you want to change
;   port 0x3c5  (data port)  -- write the new value for that register
;
; The Map-Mask is Sequencer register index 2; its low nibble is a 4-bit
; "enable" mask (bit 0 = plane 0 ... bit 3 = plane 3).  A 1 bit lets writes
; reach that plane, a 0 bit protects it.  Selecting plane(s) is therefore a
; two-step write: send "2" to 0x3c4, then send the mask to 0x3c5.  This code
; does both in ONE instruction with a 16-bit `OUT DX, AX`: with DX = 0x3c4,
; AL (the low byte, going to 0x3c4) carries the register index 0x02 and AH
; (the high byte, going to 0x3c5) carries the mask.  So the recurring word
; constants decode as <mask><02>:
;
;   0x0e02 -> mask 0x0e = planes 1,2,3 (left-edge column at dst+3)
;   0x0f02 -> mask 0x0f = all four planes (the aligned middle run)
;   0x0702 -> mask 0x07 = planes 0,1,2 (right-edge column at dst+0x4c)
;
; See FreeVGA (osdever.net/FreeVGA/vga/seqreg.htm) for the full Sequencer
; register reference.
; ----------------------------------------------------------------------------

	.286

; --- DGROUP externals -------------------------------------------------------
	extrn	_g_graphics_context:byte	; DGROUP+0x2010; +0x18 = wGfxBlitDstPage

DGROUP	group	_DATA,_BSS
_DATA	segment word public use16 'DATA'
_DATA	ends
_BSS	segment word public use16 'BSS'
_BSS	ends

; WORD-aligned, content only: the module starts at the segment's first content
; byte (FBOV minoff = 0x0c).  Bytes 0x00..0x0a belong to the PREVIOUS segment's
; tail and byte 0x0b is TLINK's word-alignment pad (emitted as 0 by the linker
; itself) — neither is this module's to emit or reserve.  Label references carry
; segment-relative fixups resolved against the canonic frame, so the original
; frame offsets re-emerge at link time.
S204A_TEXT	segment word public use16 'CODE'
	assume	cs:S204A_TEXT, ds:DGROUP

	public	_vgaplanar_clear_column_strip
	public	_vgaplanar_fill_band

; ── segment lead byte + CS-resident shade gradient table ────────────────────
; The shade ramp (0x0c..0x2d, 34 bytes) supplies the planar fill byte for each
; row of _vgaplanar_clear_column_strip, indexed by the row counter (BX): row 0
; uses entry 0, row 1 entry 1, and so on.  Each entry is a PALETTE INDEX, not
; an intensity: the values run 0xd0..0xd7, a dark-to-light gradient that ramps
; up over the first ~16 rows then holds flat at 0xd7.  (The table is 34 entries;
; a strip taller than 34 rows would index past it -- the in-game callers are
; assumed to keep row_count within the table, but that bound is not checked
; here.)
; Read ONLY by clear_column_strip; _vgaplanar_fill_band takes its byte as a
; param.  Lives in CODE and is read with a `cs:` override.
_shade_table:					; frame 0x0c: shade ramp, palette idx 0xd0..0xd7
	db	0d0h,0d0h,0d0h,0d1h,0d2h,0d2h,0d3h,0d3h
	db	0d4h,0d5h,0d5h,0d6h,0d6h,0d6h,0d7h,0d7h
	db	0d7h,0d7h,0d7h,0d7h,0d7h,0d7h,0d7h,0d7h
	db	0d7h,0d7h,0d7h,0d7h,0d7h,0d7h,0d7h,0d7h
	db	0d7h,0d7h

; ----------------------------------------------------------------------------
; 0x002e  --  _vgaplanar_clear_column_strip
;
;   void vgaplanar_clear_column_strip(int vga_base_offset, int row_count)
;
;   Paints a vertical strip of `row_count` scanlines in Mode-X planar VRAM
;   with a vertical SHADE GRADIENT: row 0 gets shade-table[0], row 1 gets
;   shade-table[1], and so on (the table at _shade_table below is the ramp).
;   This is the "clear to a shaded backdrop" primitive -- e.g. the vertical
;   dimming band behind a UI panel.
;
;   The strip is exactly one full scanline wide (0x50 bytes per plane) and is
;   painted in three left-to-right passes, because a Mode-X scanline does not
;   start on a 4-pixel boundary: an unaligned left edge (planes 1,2,3 only),
;   an aligned middle run (all four planes, 0x24 words = 0x90 bytes), and an
;   unaligned right edge (planes 0,1,2 only).  Each pass walks bottom-to-top
;   (DI/SI decrease by one stride per row), re-reading the row's shade byte
;   from the CS-resident table.
;
;   Type:        Subroutine (Mode-X planar fill primitive)
;   Category:    VGA Mode-X VRAM fill
;   Callers:     far CALL from outside the segment (game UI code)
;   Callees:     none
;
;   Inputs:
;     [bp+6]  --  vga_base_offset: byte offset of the strip's TOP row within
;                 the destination page (a plane-relative VRAM offset)
;     [bp+8]  --  row_count: number of scanlines to paint
;     CS:_shade_table  --  per-row shade gradient (read, not an argument)
;     g_graphics_context.wGfxBlitDstPage (+0x18) -- active blit-page segment
;
;   Outputs:     none (RETF; void)
;
;   Touches:     AX BX CX DX clobbered.  BP/SI/DI saved and restored.
;                ES loaded with the blit page.
;
;   Side effects:
;     Writes the destination VGA page through ES:DI.
;     Reprograms the Sequencer Map-Mask (port 0x3c4 idx 2) three times.
;
;   Notes:
;     The shade byte is read via an explicit CS: override
;     (`mov al, byte ptr cs:[bx+_shade_table]`) -- a code-segment data load.
; ----------------------------------------------------------------------------
_vgaplanar_clear_column_strip:
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	es,word ptr [_g_graphics_context+18h]	; ES = active blit page segment
	cld					; STOSB/STOSW count upward (DI increases)

	; --- pass 1: left edge, planes 1-3, column dst+3, one byte per row ------
	; DX stays = 0x3c4 (Sequencer index port) for all three passes; only AH
	; (the Map-Mask value at 0x3c5) changes between them.
	mov	dx,3c4h				; 03c4h VGA Sequencer I/O port, out dx,ax
	mov	ax,0e02h			; 0e02h out dx,ax Map-Mask AL=2,AH=0e planes1-3
	out	dx,ax
	mov	di,word ptr [bp+6]
	add	di,3				; left-edge column is at dst+3
	mov	cx,word ptr [bp+8]		; row_count
	xor	bx,bx				; bx = row index into the shade table
L_ccs_pass1:
	mov	al,byte ptr cs:[bx+_shade_table]	; this row's shade byte (CS read)
	stosb					; ES:[DI++] = shade
	sub	di,51h				; up one scanline: undo STOSB's +1, then -0x50
	inc	bx
	loop	L_ccs_pass1

	; --- pass 2: middle run, all four planes, 0x24 words (0x90 bytes) -------
	mov	ax,0f02h			; 0f02h out dx,ax Map-Mask AL=2,AH=0f all planes
	out	dx,ax
	mov	si,word ptr [bp+6]
	add	si,4				; aligned middle starts at dst+4
	mov	cx,word ptr [bp+8]		; row_count
	xor	bx,bx
L_ccs_pass2:
	mov	al,byte ptr cs:[bx+_shade_table]
	mov	ah,al				; replicate shade into both bytes of AX for STOSW
	mov	di,si				; DI = this row's start (SI is the row cursor)
	push	cx				; save the outer row counter
	mov	cx,24h				; 0x24 words across the middle run
	rep	stosw
	pop	cx
	sub	si,50h				; up one scanline
	inc	bx
	loop	L_ccs_pass2

	; --- pass 3: right edge, planes 0-2, column dst+0x4c, one byte per row --
	mov	ax,0702h			; 0702h out dx,ax Map-Mask AL=2,AH=07 planes0-2
	out	dx,ax
	mov	di,word ptr [bp+6]
	add	di,4ch				; right-edge column is at dst+0x4c
	mov	cx,word ptr [bp+8]		; row_count
	xor	bx,bx
L_ccs_pass3:
	mov	al,byte ptr cs:[bx+_shade_table]
	stosb
	sub	di,51h				; up one scanline (STOSB +1, then -0x50)
	inc	bx
	loop	L_ccs_pass3

	pop	di
	pop	si
	pop	bp
	retf

; ----------------------------------------------------------------------------
; 0x009a  --  _vgaplanar_fill_band
;
;   void vgaplanar_fill_band(int start_row, int row_count, int color)
;
;   Fills a horizontal band of `row_count` scanlines (rows start_row ..
;   start_row+row_count-1) with the SOLID colour byte `color`.  Same shape as
;   _vgaplanar_clear_column_strip -- one scanline wide, three Map-Mask passes,
;   bottom-to-top -- but the fill byte is the `color` argument rather than a
;   per-row shade-table lookup.
;
;   Unlike clear_column_strip (whose caller passes an already-computed VRAM
;   offset), this entry takes a row NUMBER and converts it to a byte offset
;   itself: it computes the offset of the band's BOTTOM row as
;   (start_row + row_count - 1) * 0x50 and walks upward from there.
;
;   Type:        Subroutine (Mode-X planar fill primitive)
;   Category:    VGA Mode-X VRAM fill
;   Callers:     far CALL from outside the segment (game UI code)
;   Callees:     none
;
;   Inputs:
;     [bp+6]   --  start_row: row number of the top of the band
;     [bp+8]   --  row_count: number of scanlines in the band
;     [bp+0ah] --  color: the byte written into every plane of every pixel
;     g_graphics_context.wGfxBlitDstPage (+0x18) -- active blit-page segment
;
;   Outputs:     none (RETF; void)
;
;   Touches:     AX BX CX DX clobbered.  BP/SI/DI saved and restored.
;                ES loaded with the blit page.
;
;   Side effects:
;     Writes the destination VGA page through ES:DI.
;     Reprograms the Sequencer Map-Mask (port 0x3c4 idx 2) three times.
;     Overwrites the caller's [bp+6] argument slot with the computed band base
;     (a scratch reuse; the caller's start_row value is dead after the call).
; ----------------------------------------------------------------------------
_vgaplanar_fill_band:
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	es,word ptr [_g_graphics_context+18h]	; ES = active blit page segment
	cld					; STOSB/STOSW count upward (DI increases)

	; Compute the VRAM byte offset of the band's BOTTOM row:
	;   base = (start_row + row_count - 1) * 0x50
	; There is no multiply-by-0x50 instruction, so it is done as
	;   0x50 = 0x10 + 0x40  ->  n*0x50 = (n<<4) + (n<<4<<2)
	mov	ax,word ptr [bp+6]		; start_row
	add	ax,word ptr [bp+8]		; + row_count
	dec	ax				; - 1  -> last row index
	shl	ax,4				; ax = row * 0x10
	mov	dx,ax
	shl	ax,2				; ax = row * 0x40  (= (row*0x10) << 2)
	add	dx,ax				; dx = row*0x10 + row*0x40 = row*0x50
	mov	word ptr [bp+6],dx		; reuse the start_row slot to hold the base

	; --- pass 1: left edge, planes 1-3, column dst+3, one byte per row ------
	; DX stays = 0x3c4 (Sequencer index port) across all three passes; only
	; AH (the Map-Mask value written to 0x3c5) changes between them.
	mov	dx,3c4h				; 03c4h VGA Sequencer I/O port, out dx,ax
	mov	ax,0e02h			; 0e02h out dx,ax Map-Mask AL=2,AH=0e planes1-3
	out	dx,ax
	mov	di,word ptr [bp+6]		; band base (computed above)
	add	di,3				; left-edge column is at dst+3
	mov	cx,word ptr [bp+8]		; row_count
	mov	ax,word ptr [bp+0ah]		; AL = fill colour
L_fb_left:
	stosb					; ES:[DI++] = colour
	sub	di,51h				; up one scanline: undo STOSB's +1, then -0x50
	loop	L_fb_left

	; --- pass 2: middle run, all four planes, 0x24 words (0x90 bytes) -------
	mov	ax,0f02h			; 0f02h out dx,ax Map-Mask AL=2,AH=0f all planes
	out	dx,ax
	mov	si,word ptr [bp+6]
	add	si,4				; aligned middle starts at dst+4
	mov	cx,word ptr [bp+8]		; row_count
	mov	ax,word ptr [bp+0ah]		; colour
	mov	ah,al				; replicate colour into both bytes of AX for STOSW
L_fb_mid:
	mov	di,si				; DI = this row's start (SI is the row cursor)
	push	cx				; save the outer row counter
	mov	cx,24h				; 0x24 words across the middle run
	rep	stosw
	pop	cx
	sub	si,50h				; up one scanline
	loop	L_fb_mid

	; --- pass 3: right edge, planes 0-2, column dst+0x4c, one byte per row --
	mov	ax,702h				; 0702h out dx,ax Map-Mask AL=2,AH=07 planes0-2
	out	dx,ax
	mov	di,word ptr [bp+6]
	add	di,4ch				; right-edge column is at dst+0x4c
	mov	cx,word ptr [bp+8]		; row_count
	mov	ax,word ptr [bp+0ah]		; AL = fill colour
L_fb_right:
	stosb
	sub	di,51h				; up one scanline (STOSB +1, then -0x50)
	loop	L_fb_right

	pop	di
	pop	si
	pop	bp
	retf

S204A_TEXT	ends
	end
