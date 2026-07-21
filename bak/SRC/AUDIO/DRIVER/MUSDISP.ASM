; ============================================================================
; MUSDISP.ASM -- KRONDOR.EXE segment 0x1000 music-driver dispatch band.
;
; Eight far command stubs plus the shared near dispatcher. One TASM module:
; the stubs near-call the dispatcher intra-segment.
;
; ABI
; ---
; Each far stub sets AX = a command/slot index (and audio_music_tick also sends
; the PIC end-of-interrupt), then NEAR-calls the shared dispatcher. The
; dispatcher sets SS:SI = &arg-block (BP+8) and FAR-calls the installed music
; driver via [g_pMusicDriver]. The driver reads its command from AX and its
; argument pointer from SI -- a register-IN calling convention. Both AX (per
; stub) and SI (in the dispatcher) must be set exactly.
;
;   13d0 audio_driver_disp_seg1000_alt  ax=0
;   13d7 FUN_1000_13d7                  ax=6
;   13de audio_music_tick           mov al,20h; out 20h,al; ax=1   (PIC EOI)
;   13e9 FUN_1000_13e9                  ax=9
;   13f0 FUN_1000_13f0                  ax=0ah
;   13f7 FUN_1000_13f7                  ax=0bh
;   13fe audio_driver_disp_seg1000_far  ax=2
;   1405 FUN_1000_1405                  ax=0ch
;   140c audio_driver_dispatch_seg1000  push bp; mov bp,sp; push di; push si;
;        mov si,bp; add si,8; callf [g_pMusicDriver]; pop si; pop di; pop bp; ret
;
; near/far: the dispatcher ends in RET (NEAR; called only by the in-module stubs
; via intra-segment near call). Every stub ends in RETF (FAR; they are the far-
; callable music API + timer-tick callback). g_pMusicDriver is the DGROUP far-ptr
; global at DGROUP+0x35e0, referenced as an extrn (never a hardcoded offset).
; ============================================================================

	.286

	extrn	_g_pMusicDriver:dword		; DGROUP+0x35e0  far ptr to music driver

	; medium-model group, so DGROUP / ASSUME DS:DGROUP resolve
_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

; WORD-aligned: the preceding module (FARTHUNK.C) ends at the odd load-module
; byte 0x113cf, so TLINK emits a single 0x00 pad at 0x113cf and starts this
; module at the even 0x113d0. A BYTE-aligned _TEXT here drops that pad and
; shifts the whole segment tail by -1.
_TEXT	segment word public use16 'CODE'
	assume	cs:_TEXT, ds:DGROUP

	public	_audio_driver_disp_seg1000_alt
	public	_FUN_1000_13d7
	public	_audio_music_tick
	public	_FUN_1000_13e9
	public	_FUN_1000_13f0
	public	_FUN_1000_13f7
	public	_audio_driver_disp_seg1000_far
	public	_FUN_1000_1405
	public	_audio_driver_dispatch_seg1000

; ----------------------------------------------------------------------------
; far command stubs: load AX = <cmd>, near-call the dispatcher, far-return
; ----------------------------------------------------------------------------

; int audio_driver_disp_seg1000_alt(int a, int b)   (cmd 0)
_audio_driver_disp_seg1000_alt proc far
	mov	ax,0
	call	_audio_driver_dispatch_seg1000
	retf
_audio_driver_disp_seg1000_alt endp

; undefined FUN_1000_13d7()   (cmd 6)
_FUN_1000_13d7	proc far
	mov	ax,6
	call	_audio_driver_dispatch_seg1000
	retf
_FUN_1000_13d7	endp

; void audio_music_tick(void)   (cmd 1, plus PIC EOI)
_audio_music_tick proc far
	mov	al,20h
	out	20h,al			; non-specific EOI to master 8259
	mov	ax,1
	call	_audio_driver_dispatch_seg1000
	retf
_audio_music_tick endp

; undefined FUN_1000_13e9()   (cmd 9)
_FUN_1000_13e9	proc far
	mov	ax,9
	call	_audio_driver_dispatch_seg1000
	retf
_FUN_1000_13e9	endp

; undefined FUN_1000_13f0()   (cmd 0ah)
_FUN_1000_13f0	proc far
	mov	ax,0ah
	call	_audio_driver_dispatch_seg1000
	retf
_FUN_1000_13f0	endp

; undefined FUN_1000_13f7()   (cmd 0bh)
_FUN_1000_13f7	proc far
	mov	ax,0bh
	call	_audio_driver_dispatch_seg1000
	retf
_FUN_1000_13f7	endp

; void audio_driver_disp_seg1000_far(void)   (cmd 2)
_audio_driver_disp_seg1000_far proc far
	mov	ax,2
	call	_audio_driver_dispatch_seg1000
	retf
_audio_driver_disp_seg1000_far endp

; void FUN_1000_1405(void)   (cmd 0ch)
_FUN_1000_1405	proc far
	mov	ax,0ch
	call	_audio_driver_dispatch_seg1000
	retf
_FUN_1000_1405	endp

; ----------------------------------------------------------------------------
; int audio_driver_dispatch_seg1000(void)   -- NEAR shared dispatcher
;   SI = &arg-block (BP+8); far-call the installed music driver via the vector.
; ----------------------------------------------------------------------------
_audio_driver_dispatch_seg1000 proc near
	push	bp
	mov	bp,sp
	push	di
	push	si
	mov	si,bp
	add	si,8			; SS:SI -> caller's arg block
	call	dword ptr [_g_pMusicDriver]	; far-call installed music driver
	pop	si
	pop	di
	pop	bp
	ret
_audio_driver_dispatch_seg1000 endp

_TEXT	ends
	end
