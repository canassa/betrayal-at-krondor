; ============================================================================
; DOSRW.ASM -- DOS chunked read/write tail-call stubs @ 1000:04f6 (118 bytes)
;
; Three procs from ONE original TU, contiguous at 04f6/04fd/0504:
;   _dos_read       @ 04f6 (7 bytes)  -- ES=0x3f00 (AH=3F read),  tail-jmp helper
;   _dos_write      @ 04fd (7 bytes)  -- ES=0x4000 (AH=40 write), tail-jmp helper
;   _dos_rw_chunked @ 0504 (104 bytes)-- the shared chunked-transfer body
;
; One module: the two stubs tail-jump into the helper with a 2-byte SHORT near
; JMP (`EB 07` / `EB 00`).  A short rel8 jump to an *external* near symbol is
; mis-fixed-up by TLINK by one byte (it lands one byte before _dos_rw_chunked's
; prologue, on the helper's `EB FF`/garbage), which silently breaks every
; savegame copy -- the "important data file could not be created" new-game bug.
; With all three in one module `_dos_rw_chunked` is a LOCAL label, so TASM
; resolves the short displacement at assembly time (no FIXUP).
;
; Register-IN convention: the DOS service number (AH = 0x3F read / 0x40 write)
; is delivered in *ES*, not as a parameter: the body does `MOV AX,ES ; INT 21h`
; so AH = ES>>8.  The LDS-based far-pointer normalization (SHR/SHL DL ladder
; folding the offset into the segment) is hand-written.
;
; SEG 1000 is the resident _TEXT segment shared with the CM.LIB CRT, so the
; module names the segment plain `_TEXT` (not S1000_TEXT) and the JMP into
; _dos_rw_chunked is a NEAR intra-segment jump.
;
; Convention (all three): far (RETF).  The stubs RETF to the caller via the
; helper; the helper RETFs directly.  Returns the bytes-transferred count in
; DX:AX on success, 0 on error.
; ============================================================================

	.8086

_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group	_DATA, _BSS

_TEXT	segment byte public use16 'CODE'
	assume	cs:_TEXT, ds:DGROUP

	public	_dos_read
	public	_dos_write
	public	_dos_rw_chunked

; ulong _dos_read(uchar far *buf, ulong count, int handle)  [tail-call -> _dos_rw_chunked, ES=0x3f00]
_dos_read	proc far
	mov	ax,3f00h		; 3f00h DOS fn code AH=3F via ES (reg-arg)
	mov	es,ax			; deliver DOS function code in ES
	jmp	short _dos_rw_chunked	; near short tail-call (inherits frame + args)
_dos_read	endp

; ulong _dos_write(uchar far *buf, ulong count, int handle)  [tail-call -> _dos_rw_chunked, ES=0x4000]
_dos_write	proc far
	mov	ax,4000h		; 4000h DOS fn code AH=40 via ES (reg-arg)
	mov	es,ax			; deliver DOS function code in ES
	jmp	short _dos_rw_chunked	; near short tail-call (inherits frame + args)
_dos_write	endp

; ulong _dos_rw_chunked(uchar far *buf, ulong count, int handle)  [register-IN: ES=AH]
;   [BP+6]  = buf    (far ptr)
;   [BP+0a] = count  (ulong, low=SI, high=DI)
;   [BP+0e] = handle (int -> BX)
_dos_rw_chunked	proc far
	push	bp
	mov	bp,sp
	push	ds
	push	si
	push	di
	mov	bx,word ptr [bp+0eh]	; handle
	mov	si,word ptr [bp+0ah]	; count low
	mov	di,word ptr [bp+0ch]	; count high
	lds	dx,[bp+6]		; buf -> DS:DX
L_norm:
	mov	cl,4
	mov	ax,dx
	shr	ax,cl			; AX = offset >> 4 (paragraphs)
	shl	dl,cl
	shr	dl,cl			; DL = offset & 0x0f
	xor	dh,dh
	mov	cx,ax
	mov	ax,ds
	add	ax,cx			; fold paragraphs into segment
	mov	ds,ax
	or	di,di
	jnz	short L_chunk		; high word nonzero -> full 0x7fff chunk
	cmp	si,7fffh
	jbe	short L_last		; remainder fits in one call
L_chunk:
	mov	cx,7fffh
	mov	ax,es			; AH = DOS function code (from ES)
	int	21h
	jc	short L_fail
	cmp	ax,7fffh
	jnz	short L_fail
	add	dx,7fffh
	sub	si,7fffh
	sbb	di,0
	jmp	short L_norm
L_last:
	mov	cx,si
	mov	ax,es			; AH = DOS function code (from ES)
	int	21h
	jc	short L_fail
	cmp	ax,si
	jnz	short L_fail
	mov	ax,word ptr [bp+0ah]	; return original count in DX:AX
	mov	dx,word ptr [bp+0ch]
	jmp	short L_ret
L_fail:
	xor	ax,ax
	xor	dx,dx
L_ret:
	pop	di
	pop	si
	pop	ds
	pop	bp
	retf
_dos_rw_chunked	endp

_TEXT	ends
	end
