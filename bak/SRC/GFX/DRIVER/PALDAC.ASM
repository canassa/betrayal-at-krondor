; ============================================================================
; PALETTE.ASM -- BIOS + VGA-DAC palette helpers @ 1000:0460 (150 bytes)
;
; Three procs, contiguous at 0460/047e/04bb (no padding between them):
;   bios_palette_read @ 0460 (30 bytes) -- read one EGA/VGA palette register
;                                          via BIOS INT 10h, repack to IRGB
;   vga_read_palette  @ 047e (61 bytes) -- read N DAC entries out the DAC ports
;   vga_write_palette @ 04bb (59 bytes) -- write N DAC entries into the DAC ports
;
; The two VGA procs use inline port I/O (IN AL,DX / OUT DX,AL), STOSB/LODSB +
; LOOP DAC-stream loops, and CLI/STI critical sections.
;
; SEG 1000 is the resident _TEXT segment shared with the CM.LIB CRT, so the
; module names the segment plain `_TEXT` (not S1000_TEXT).
;
; Convention (all three): far (RETF).
; ============================================================================

	.286

_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

_TEXT	segment byte public use16 'CODE'
	assume	cs:_TEXT, ds:DGROUP

	public	_bios_palette_read
	public	_vga_read_palette
	public	_vga_write_palette

; ----------------------------------------------------------------------------
; uchar bios_palette_read(int reg_index)
;
; Reads an EGA/VGA palette register via BIOS INT 10h AX=1007h (BL = register
; index 0-15; BIOS returns the stored value in BH).  Repacks bits 0-2 (RGB)
; plus bit 4 (intensity) into the IRGB nibble (0-15).
; ----------------------------------------------------------------------------
_bios_palette_read	proc far
	push	bp
	mov	bp,sp
	push	si
	push	ds
	pop	es				; ES = DS
	mov	bx,word ptr [bp+6]		; reg_index
	mov	ax,1007h
	int	10h				; BIOS: value returned in BH
	mov	al,bh				; result = v
	xor	ah,ah				; zero-extend into AX
	and	bh,10h				; intensity bit (in place on BH)
	shr	bh,1
	and	al,7				; RGB bits
	or	al,bh				; combine -> IRGB nibble
	pop	si
	pop	bp
	retf
_bios_palette_read	endp

; ----------------------------------------------------------------------------
; void vga_read_palette(uchar *buf, int start, int count)
;
; Reads `count` VGA DAC palette entries (3 bytes each: R,G,B) starting at DAC
; index `start`, into the near buffer `buf` (ES:DI = DS:buf).  Waits for the
; vertical-retrace status bit, primes/aligns the DAC read state, sets the DAC
; read index, then streams 3*count bytes out of the DAC data port (0x3c9)
; inside a CLI/STI critical section.
; ----------------------------------------------------------------------------
_vga_read_palette	proc far
	push	bp
	mov	bp,sp
	push	di
	push	ds
	pop	es				; ES = DS
	mov	di,word ptr [bp+6]		; buf
	mov	cx,word ptr [bp+0ah]		; count
	mov	ax,cx
	shl	cx,1
	add	cx,ax				; CX = count*3
	mov	bx,word ptr [bp+8]		; start
	mov	dx,3DAh				; input status 1
vrwait:
	in	al,dx
	and	al,8				; vertical retrace bit
	jz	vrwait
	mov	dx,3C7h				; DAC read-index / state port
	in	al,dx
	and	al,3
	or	al,al
	jz	skip
	mov	dx,3C9h				; DAC data - drain pending byte
	in	al,dx
	mov	dx,3C7h	; 03c7h VGA DAC read-index port
skip:
	mov	ax,bx
	out	dx,al				; set DAC read index = start
	mov	dx,3C9h	; 03c9h VGA DAC data port
	cli
rdloop:
	in	al,dx
	stosb
	loop	rdloop
	sti
	pop	di
	pop	bp
	retf
_vga_read_palette	endp

; ----------------------------------------------------------------------------
; void vga_write_palette(uchar *src, int start_index, int num_colors)
;
; Writes the VGA DAC palette from src[].  Waits for vertical retrace on the
; input-status register (0x3DA bit 3), resets the DAC read/write index latch
; via the read-index port (0x3C7), programs the write-index port (0x3C8) with
; start_index, then streams 3*num_colors bytes (R,G,B per slot) into the data
; port (0x3C9) inside a CLI/STI critical section using LODSB + LOOP.
; ----------------------------------------------------------------------------
_vga_write_palette	proc far
	push	bp
	mov	bp,sp
	push	si
	mov	si,word ptr [bp+6]		; src
	mov	cx,word ptr [bp+0ah]		; num_colors
	mov	ax,cx
	shl	cx,1
	add	cx,ax				; CX = num_colors*3
	mov	bx,word ptr [bp+8]		; start_index
	mov	dx,3dah
vretrace:
	in	al,dx
	and	al,8
	jz	vretrace			; wait for vertical retrace
	mov	dx,3c7h
	in	al,dx
	and	al,3
	cmp	al,3
	jz	skipreset
	mov	dx,3c9h				; 03c9h VGA DAC data port
	out	dx,al
skipreset:
	mov	dx,3c8h				; 03c8h VGA DAC write-index port
	mov	ax,bx
	out	dx,al				; write-index = start_index
	mov	dx,3c9h				; 03c9h VGA DAC data port
	cli
stream:
	lodsb
	out	dx,al
	loop	stream
	sti
	pop	si
	pop	bp
	retf
_vga_write_palette	endp

_TEXT	ends
	end
