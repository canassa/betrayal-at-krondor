; ============================================================================
; DISP35E0.ASM -- KRONDOR.EXE segment-0x1000 music-driver direct-dispatch stub.
;
; Two contiguous members (1000:141e..1435):
;
;   _dispatch_via_35e0_cmd0d_seg1000 (1000:141e, 3 bytes)
;       MOV AX,0Dh   -- loads music command 0x0D, then FALLS THROUGH into:
;   _dispatch_via_35e0_seg1000       (1000:1421, 21 bytes)
;       builds a 6-byte SS:SI arg block and FAR-calls the installed music driver
;       via [g_pMusicDriver]; returns DX:AX torn off the stack.
;
; One TASM module: the cmd-0x0D entry has no return of its own -- it loads a
; register-IN command (AX) and falls straight into the shared dispatcher body,
; a fall-through that cannot cross a link-module boundary.
;
; ABI
; ---
; The driver is invoked with SS:SI pointing at the argument block (a register-IN
; calling convention) and its command index in AX; it returns its result words in
; the block, which the stub tears off the stack as POP AX; POP AX; POP DX (so the
; effective return is block[2..3] in AX, block[4..5] in DX). g_pMusicDriver is the
; DGROUP far-ptr global at DGROUP+0x35e0, referenced as an extrn (never a
; hardcoded offset). The cmd-0x0D entry is the command-0x0D sibling of the
; MUSDISP band stubs (commands 0,1,2,6,9,0Ah,0Bh,0Ch there).
;
; near/far: both end/pass into a RETF (FAR; a far-callable music API entry).
; ============================================================================

	.286

	extrn	_g_pMusicDriver:dword		; DGROUP+0x35e0  far ptr to music driver

	; medium-model group, so DGROUP / ASSUME DS:DGROUP resolve
_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

_TEXT	segment byte public use16 'CODE'
	assume	cs:_TEXT, ds:DGROUP

	public	_dispatch_via_35e0_cmd0d_seg1000
	public	_dispatch_via_35e0_seg1000

; undefined dispatch_via_35e0_cmd0d_seg1000(void)  -- cmd-0x0D far entry, falls through
_dispatch_via_35e0_cmd0d_seg1000 proc far
	mov	ax,0dh			; music command 0x0D; falls through to the body
_dispatch_via_35e0_cmd0d_seg1000 endp

; undefined2 dispatch_via_35e0_seg1000(void)
_dispatch_via_35e0_seg1000 proc far
	push	bp
	mov	bp,sp
	push	di
	push	si
	sub	sp,6			; 6-byte arg/return block
	mov	si,sp			; SS:SI -> arg block (register-IN)
	call	dword ptr [_g_pMusicDriver]	; far-call installed music driver
	pop	ax
	pop	ax			; AX = block[2..3]
	pop	dx			; DX = block[4..5]
	pop	si
	pop	di
	pop	bp
	retf
_dispatch_via_35e0_seg1000 endp

_TEXT	ends
	end
