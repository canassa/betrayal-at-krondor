; ============================================================================
; VIDDET.ASM -- KRONDOR.EXE video shutdown + adapter detection (segment 180c).
;
; Three near/far routines, contiguous in the image (180c:2b7b..2ce8, linear
; 0x1ac3b..0x1adc2):
;
;   _video_shutdown            restores the BIOS video mode saved by video_init
;                             (unless already restored) via
;                             bios_set_video_mode_bits.
;   _video_detect_adapter      detects the installed video adapter and returns a
;                             small numeric ID via INT 10h AH=1Ah (VGA/MCGA
;                             detect), INT 10h AH=12h BL=10h (EGA info), and a
;                             direct CRTC port probe at 0x3D4/0x3D5 or
;                             0x3B4/0x3B5 to distinguish CGA/MDA variants.
;   _crtc_probe_data_register  probes a CRTC index/data register pair for
;                             read/write capability (writes 0Fh/66h, spins a
;                             settle delay, reads back, restores); CF set =
;                             absent.
;
; video_detect_adapter uses INT 10h + register-convention calls (BL/BH results),
; a PUSH CS + near CALL to the far-convention bios_compat_check (RETF), direct
; I/O port accesses in a NOP+LOOP delay loop, and LOOPZ for a polling loop.
; crtc_probe_data_register is a leaf register-convention routine (DX in, CF out)
; doing raw port I/O and a settle-delay LOOP.
; ============================================================================

	.286

	; callees genuinely external to this unit
	extrn	_bios_video_int10_helper:near
	extrn	_bios_compat_check:far		; far proc in another module of this segment;
						; TLINK's backward far->near collapse emits the
						; 90 0e e8 bytes at the call site
	extrn	_bios_set_video_mode_bits:near

	; DGROUP globals
	extrn	_g_bSavedBiosVideoMode:byte
	extrn	_g_bRequestedVideoMode:byte		; DGROUP+0x2ea9 (1B)
	; g_bVideoAutoDetectEnabled is render-tail field +0x3c6 of GraphicsContextRender
	; (DGROUP+0x2ac4, structs.md §36); gfxctx.inc: _g_graphics_context_render.
	include	gfxctx.inc

	; medium-model group, so DGROUP / ASSUME DS:DGROUP resolve
_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_video_shutdown, _video_detect_adapter, _crtc_probe_data_register

; ----------------------------------------------------------------------------
; void far video_shutdown(void) -- restores the BIOS video mode saved by
; video_init, unless it was already restored (g_bSavedBiosVideoMode == 0xff).
; ----------------------------------------------------------------------------
_video_shutdown	proc far
	push	bp
	mov	bp,sp
	xor	ax,ax
	mov	al,byte ptr [_g_bSavedBiosVideoMode]
	cmp	al,0ffh
	jz	short L_done
	push	ax
	call	near ptr _bios_set_video_mode_bits
	pop	ax
	mov	byte ptr [_g_bSavedBiosVideoMode],0ffh
L_done:
	pop	bp
	retf
_video_shutdown	endp

; ----------------------------------------------------------------------------
; int near video_detect_adapter(void)  -> AX  (341 bytes)
; Result IDs: 0=plain CGA/MDA, 1=CGA-EGA-compat, 3=CGA-extended, 4=MDA,
;             5=EGA, 8=VGA/MCGA, 9=requested-mode.
; ----------------------------------------------------------------------------
_video_detect_adapter	proc near		; ends with RET (0xc3)

	; off 0x0000: entry — load requested mode and check auto-detect flag
	mov	al,[_g_bRequestedVideoMode]
	cmp	word ptr [_g_graphics_context_render.bVideoAutoDetectEnabled],0h	; 5-byte form: 83 3e addr 00
	jnz	L_2ba0				; 0008: 75 03
	xor	ah,ah
	ret					; 000c: c3

L_2ba0:	; off 0x000d
	or	al,al
	jz	L_2bdb				; 000f: 74 37
	cmp	al,9h
	jz	L_2bd3				; 0013: 74 2b
	cmp	al,0ah
	jz	L_2bdb				; 0017: 74 2f  (note: forward to 0x48)
	cmp	al,8h
	jz	L_2bdb				; 001b: 74 2b
	cmp	al,0dh
	jz	L_2bdb				; 001f: 74 27
	cmp	al,0ch
	jz	L_2bdb				; 0023: 74 23
	cmp	al,0eh
	jz	L_2bdb				; 0027: 74 1f
	cmp	al,0fh
	jz	L_2bdb				; 002b: 74 1b
	cmp	al,5h
	jz	L_2c0c				; 002f: 74 48
	cmp	al,2h
	jz	L_2c43				; 0033: 74 7b
	cmp	al,7h
	jz	L_2c43				; 0037: 74 77
	cmp	al,0bh
	jz	L_2c43				; 003b: 74 73
	jmp	L_2c6c				; 003d: e9 99 00

L_2bd3:	; off 0x0040
	call	_bios_video_int10_helper	; e8 67 01
	mov	al,9h
	jmp	L_2ce5				; 0045: e9 0a 01

L_2bdb:	; off 0x0048
	cmp	byte ptr [_g_graphics_context_render.bVideoAutoDetectEnabled],0h	; 80 3e addr 00 — 5-byte form
	mov	ax,1a00h
	int	10h
	cmp	bl,7h
	jz	L_2bfe				; 0055: 74 14
	cmp	bl,8h
	jz	L_2bfe				; 005a: 74 0f
	cmp	bh,7h
	jz	L_2bfb				; 005f: 74 07
	cmp	bh,8h
	jz	L_2bfb				; 0064: 74 02
	jnz	L_2c0c				; 0066: 75 11

L_2bfb:	; off 0x0068
	call	_bios_video_int10_helper	; e8 3f 01

L_2bfe:	; off 0x006b
	mov	al,[_g_bRequestedVideoMode]
	xor	ah,ah
	or	ax,ax
	jnz	L_2c09				; 0072: 75 02
	mov	al,8h

L_2c09:	; off 0x0076
	jmp	L_2ce5				; e9 d9 00

L_2c0c:	; off 0x0079
	mov	ax,1a00h
	int	10h
	cmp	bl,7h
	jz	L_2c3e				; 0081: 74 28
	cmp	bl,8h
	jz	L_2c3e				; 0086: 74 23
	cmp	bh,7h
	jz	L_2c3b				; 008b: 74 1b
	cmp	bh,8h
	jz	L_2c3b				; 0090: 74 16
	cmp	bl,0bh
	jz	L_2c3e				; 0095: 74 14
	cmp	bl,0ch
	jz	L_2c3e				; 009a: 74 0f
	cmp	bh,0bh
	jz	L_2c3b				; 009f: 74 07
	cmp	bh,0ch
	jz	L_2c3b				; 00a4: 74 02
	jnz	L_2c43				; 00a6: 75 08

L_2c3b:	; off 0x00a8
	call	_bios_video_int10_helper	; e8 ff 00

L_2c3e:	; off 0x00ab
	mov	al,5h
	jmp	L_2ce5				; 00ad: e9 a2 00

L_2c43:	; off 0x00b0
	mov	ax,40h
	mov	es,ax
	mov	ah,12h
	mov	bx,10h
	int	10h
	cmp	bx,10h
	jz	L_2c6c				; 00bf: 74 18
	mov	bx,87h
	mov	al,byte ptr es:[bx]		; read BIOS data area: 0040:0087 (equipment flags)
	and	al,8h
	jnz	L_2c64				; 00c9: 75 06
	mov	al,[_g_bRequestedVideoMode]
	jmp	L_2ce5				; 00ce: e9 81 00

L_2c64:	; off 0x00d1
	call	_bios_video_int10_helper	; e8 d6 00
	mov	al,[_g_bRequestedVideoMode]
	jmp	short L_2ce5			; 00d7: eb 79

L_2c6c:	; off 0x00d9
	mov	al,[_g_bRequestedVideoMode]
	or	al,al
	jz	L_2c7b				; 00de: 74 08
	cmp	al,1h
	jz	L_2c7b				; 00e2: 74 04
	cmp	al,3h
	jnz	L_2cb8				; 00e6: 75 3d

L_2c7b:	; off 0x00e8
	mov	dx,3d4h		; 03d4h CRTC index I/O port
	mov	al,0fh
	out	dx,al
	inc	dx
	mov	ah,al
	mov	al,66h
	out	dx,al
	mov	cx,64h

L_2c8a:	; off 0x00f7 -- LOOP target (delay loop)
	nop
	loop	L_2c8a				; e2 fd
	in	al,dx
	xchg	ah,al				; 86 e0: modrm=e0 (reg=AH, rm=AL)
	out	dx,al
	cmp	ah,66h
	jnz	L_2cb8				; 0101: 75 22
	call	_bios_video_int10_helper	; 0103: e8 a4 00
	call	_bios_compat_check		; 90 0e e8 5e ed via TLINK's backward
						; far->near collapse of the 5-byte far call
	cmp	byte ptr [_g_bRequestedVideoMode],1h
	jz	L_2cad				; 0110: 74 08
	or	al,al
	jz	L_2cad				; 0114: 74 04
	mov	al,3h
	jmp	short L_2ce5			; 0118: eb 38

L_2cad:	; off 0x011a
	cmp	byte ptr [_g_bRequestedVideoMode],3h
	jz	L_2ce3				; 011f: 74 2f
	mov	al,1h
	jmp	short L_2ce5			; 0123: eb 2d

L_2cb8:	; off 0x0125
	mov	al,[_g_bRequestedVideoMode]
	or	al,al
	jz	L_2cc3				; 012a: 74 04
	cmp	al,4h
	jnz	L_2ce3				; 012e: 75 20

L_2cc3:	; off 0x0130
	mov	dx,3b4h		; 03b4h MDA CRTC index I/O port
	call	_crtc_probe_data_register	; intra-unit near call
	jc	L_2ce3				; 0136: 72 18
	mov	dl,0bah
	in	al,dx
	and	al,80h
	mov	ah,al
	mov	cx,8000h

L_2cd5:	; off 0x0142 -- LOOPZ target (polling loop)
	in	al,dx
	and	al,80h
	cmp	ah,al
	loopz	L_2cd5				; e1 f9
	jz	L_2ce3				; 0149: 74 05
	mov	ax,4h
	jmp	short L_2ce5			; 014e: eb 02

L_2ce3:	; off 0x0150
	xor	al,al

L_2ce5:	; off 0x0152
	xor	ah,ah
	ret					; 0154: c3

_video_detect_adapter	endp

; ----------------------------------------------------------------------------
; bool near crtc_probe_data_register(unsigned port /* DX */)  -> CF
; Probes a VGA/CRTC data register pair for read/write capability. DX on
; entry = CRTC index port. Writes index 0Fh, reads it back into AH, writes
; 66h to the data port (DX+1), spins a 256-iteration LOOP delay, reads the
; data port back, swaps the byte back (XCHG restores AH=old,AL=read),
; restores the original value, and compares the read-back to 66h.
; Match -> CF clear (register is writable); mismatch -> STC sets CF (absent).
; No args/result in C terms; register convention. No DGROUP globals.
; ----------------------------------------------------------------------------
_crtc_probe_data_register	proc near
	mov	al,0fh
	out	dx,al
	inc	dx
	in	al,dx
	mov	ah,al
	mov	al,66h
	out	dx,al
	mov	cx,100h		; 100h LOOP count: 256-iter settle delay
delay_loop:
	loop	delay_loop
	in	al,dx
	xchg	ah,al
	out	dx,al
	cmp	ah,66h
	jz	L_cpd_done
	stc
L_cpd_done:
	ret
_crtc_probe_data_register	endp

S180C_TEXT	ends

	end
