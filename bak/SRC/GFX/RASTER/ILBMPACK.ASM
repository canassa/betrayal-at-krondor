; ============================================================================
; ILBMPACK.ASM -- ilbm_pack_row_to_planes @ 1000:030e  (0x152 bytes)
;
; Bit-plane packing: transposes 40 groups of 4 packed-pixel words (uint[4])
; from src into 8 bit-planes at dst[0], dst[0x28], dst[0x50], ..., dst[0x118].
;
; Each group of 4 words carries 16 pixels × 4 bits-per-plane = 64 bits.
; The inner body shifts each word right 1 bit at a time (SHR BP,1) and
; rotates the carry bit into one of 8 byte registers (AH, AL, BH, BL,
; CH, CL, DH, DL) via RCL. After processing all 4 words (32 SHR/RCL pairs
; per word = 16 bits × 2 words per uint = 128 shifts total), each byte
; register holds one bitplane byte; these are stored to dst at 0x28-spaced
; offsets (one for each of 8 bitplanes), then dst is advanced by 1 and the
; loop counter (kept on the stack) is decremented.
;
; WHY ASM: the SHR BP,1 / RCL <bytereg>,1 rotate-through-carry bit-transpose has
; no C form -- C has no rotate-through-carry operator, and BCC 3.1 has no
; intrinsic that maps to RCL.
; ============================================================================

	.286

; no DGROUP externals — function accesses only stack-passed pointers

	_DATA	segment word public 'DATA'
	_DATA	ends
	_BSS	segment word public 'BSS'
	_BSS	ends
	DGROUP	group _DATA, _BSS

_TEXT	segment byte public use16 'CODE'
	assume	cs:_TEXT, ds:DGROUP

	public	_ilbm_pack_row_to_planes

; void ilbm_pack_row_to_planes(uint *src, uchar *dst)
_ilbm_pack_row_to_planes	proc far
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	si,word ptr [bp+6]       ; SI = src
	mov	di,word ptr [bp+8]       ; DI = dst
	mov	ax,028h
	push	ax                       ; loop counter = 40 on stack
L_loop:
	mov	bp,word ptr [si]         ; BP = src[0]
	shr	bp,1
	rcl	ah,1
	shr	bp,1
	rcl	al,1
	shr	bp,1
	rcl	bh,1
	shr	bp,1
	rcl	bl,1
	shr	bp,1
	rcl	ch,1
	shr	bp,1
	rcl	cl,1
	shr	bp,1
	rcl	dh,1
	shr	bp,1
	rcl	dl,1
	shr	bp,1
	rcl	ah,1
	shr	bp,1
	rcl	al,1
	shr	bp,1
	rcl	bh,1
	shr	bp,1
	rcl	bl,1
	shr	bp,1
	rcl	ch,1
	shr	bp,1
	rcl	cl,1
	shr	bp,1
	rcl	dh,1
	shr	bp,1
	rcl	dl,1
	mov	bp,word ptr [si+2]       ; BP = src[1]
	shr	bp,1
	rcl	ah,1
	shr	bp,1
	rcl	al,1
	shr	bp,1
	rcl	bh,1
	shr	bp,1
	rcl	bl,1
	shr	bp,1
	rcl	ch,1
	shr	bp,1
	rcl	cl,1
	shr	bp,1
	rcl	dh,1
	shr	bp,1
	rcl	dl,1
	shr	bp,1
	rcl	ah,1
	shr	bp,1
	rcl	al,1
	shr	bp,1
	rcl	bh,1
	shr	bp,1
	rcl	bl,1
	shr	bp,1
	rcl	ch,1
	shr	bp,1
	rcl	cl,1
	shr	bp,1
	rcl	dh,1
	shr	bp,1
	rcl	dl,1
	mov	bp,word ptr [si+4]       ; BP = src[2]
	shr	bp,1
	rcl	ah,1
	shr	bp,1
	rcl	al,1
	shr	bp,1
	rcl	bh,1
	shr	bp,1
	rcl	bl,1
	shr	bp,1
	rcl	ch,1
	shr	bp,1
	rcl	cl,1
	shr	bp,1
	rcl	dh,1
	shr	bp,1
	rcl	dl,1
	shr	bp,1
	rcl	ah,1
	shr	bp,1
	rcl	al,1
	shr	bp,1
	rcl	bh,1
	shr	bp,1
	rcl	bl,1
	shr	bp,1
	rcl	ch,1
	shr	bp,1
	rcl	cl,1
	shr	bp,1
	rcl	dh,1
	shr	bp,1
	rcl	dl,1
	mov	bp,word ptr [si+6]       ; BP = src[3]
	shr	bp,1
	rcl	ah,1
	shr	bp,1
	rcl	al,1
	shr	bp,1
	rcl	bh,1
	shr	bp,1
	rcl	bl,1
	shr	bp,1
	rcl	ch,1
	shr	bp,1
	rcl	cl,1
	shr	bp,1
	rcl	dh,1
	shr	bp,1
	rcl	dl,1
	shr	bp,1
	rcl	ah,1
	shr	bp,1
	rcl	al,1
	shr	bp,1
	rcl	bh,1
	shr	bp,1
	rcl	bl,1
	shr	bp,1
	rcl	ch,1
	shr	bp,1
	rcl	cl,1
	shr	bp,1
	rcl	dh,1
	shr	bp,1
	rcl	dl,1
	push	di
	add	si,8                     ; src += 4 (4 words = 8 bytes)
	mov	byte ptr [di],ah         ; dst[0]      = plane 0
	add	di,028h
	mov	byte ptr [di],al         ; dst[0x28]   = plane 1
	add	di,028h
	mov	byte ptr [di],bh         ; dst[0x50]   = plane 2
	add	di,028h
	mov	byte ptr [di],bl         ; dst[0x78]   = plane 3
	add	di,028h
	mov	byte ptr [di],ch         ; dst[0xa0]   = plane 4
	add	di,028h
	mov	byte ptr [di],cl         ; dst[0xc8]   = plane 5
	add	di,028h
	mov	byte ptr [di],dh         ; dst[0xf0]   = plane 6
	add	di,028h
	mov	byte ptr [di],dl         ; dst[0x118]  = plane 7
	pop	di
	inc	di                       ; dst++
	pop	ax
	dec	ax
	push	ax
	jz	short L_done
	jmp	L_loop
L_done:
	pop	ax
	pop	di
	pop	si
	pop	bp
	retf
_ilbm_pack_row_to_planes	endp

_TEXT	ends
	end
