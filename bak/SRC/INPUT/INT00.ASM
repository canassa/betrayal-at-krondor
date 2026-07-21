; ============================================================================
; INT00.ASM -- KRONDOR.EXE divide-by-zero (INT 00) handler module (3 routines).
;
;   _install_int00_handler   hooks INT 00 to _int00_divide_recovery, saving the
;                             prior IVT slot 0 first.
;   _int00_divide_recovery   the ISR itself: fixes up the faulting DIV/IDIV and
;                             returns a synthetic quotient so execution
;                             continues.
;   _restore_int00_handler   paired teardown for install_int00_handler.
;
; install_int00_handler's IVT write bakes the offset of int00_divide_recovery
; directly (`mov word ptr es:[0h],offset _int00_divide_recovery`), an
; intra-module reference.
;
; Per-routine idioms:
;   * install_int00_handler manipulates ES directly (ES=0000h to address the
;     real-mode IVT), stores CS inline with `MOV word ptr ES:[2],CS`, and
;     brackets the vector write in CLI/STI.
;   * int00_divide_recovery is a register-IN/OUT interrupt handler: it reads
;     the stacked faulting CS:IP off its own frame ([BP+2]/[BP+4]), fetches
;     the faulting opcode byte at that address, REWRITES the stacked return
;     IP in place to skip past the DIV/IDIV, and computes its result from the
;     interrupted AX/DX pushed on entry (POP AX / SAR DX,1 / RCR AX,1). It
;     terminates with IRET, not RET/RETF.
;   * restore_int00_handler has no BP frame (PUSH AX/PUSH ES prologue only),
;     uses direct-address MOV forms against DGROUP and an ES-prefixed direct
;     read of the IVT, and brackets the body in CLI/STI.
;
; Behavioral facts:
;   * install_int00_handler saves the IVT slot 0 OFFSET word (ES:[0]) into
;     `g_wInt00SaveOff` and the SEGMENT word (ES:[2]) into `g_wInt00SaveSeg`.
;   * DEFECT in restore_int00_handler: after clearing g_int00_installed, it
;     reads `g_wInt00SaveOff`/`g_wInt00SaveSeg` into AX and separately reads
;     the live IVT slot 0 (ES:[0]/ES:[2]) into AX -- every one of these four
;     MOVs is immediately clobbered by the next, and the function never writes
;     the IVT back. The saved vector is NEVER restored; the routine's IVT
;     "restore" is dead code.
; ============================================================================

	.286

; This module's _DATA block (DG 0x2ea2..0x2ea8): the INT 0 (divide-error)
; handler-install state.
_DATA	segment word public 'DATA'

	public	_g_int00_installed, _g_wInt00SaveSeg, _g_wInt00SaveOff

_g_int00_installed	db	0	; DGROUP+0x2ea2 (1B) uchar
_g_wInt00SaveSeg	dw	0	; DGROUP+0x2ea3 (2B) ushort  saved IVT[0] segment
_g_wInt00SaveOff	dw	0	; DGROUP+0x2ea5 (2B) ushort  saved IVT[0] offset
	; DG+0x2ea7 (1B) word-alignment pad ahead of the video-subsystem block at
	; 0x2ea8.
	public	_dgroup_pad_2ea7
_dgroup_pad_2ea7	db	0	; DGROUP+0x2ea7 (1B) zero pad (unidentified)
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_install_int00_handler
	public	_int00_divide_recovery
	public	_restore_int00_handler

; ----------------------------------------------------------------------------
; void install_int00_handler(void)
;
; Installs the game's divide-by-zero (INT 00) handler. Saves the current IVT
; entry at 0000:0000 (offset) and 0000:0002 (segment) into g_wInt00SaveOff
; and g_wInt00SaveSeg, sets g_int00_installed=1, then writes
; _int00_divide_recovery as the new INT 00 vector.
; ----------------------------------------------------------------------------
_install_int00_handler	proc far
	push	ax
	push	es
	mov	byte ptr [_g_int00_installed],1h
	sub	ax,ax
	mov	es,ax
	mov	ax,es:[0h]
	mov	[_g_wInt00SaveOff],ax
	mov	ax,es:[2h]
	mov	[_g_wInt00SaveSeg],ax
	cli
	mov	word ptr es:[0h],offset _int00_divide_recovery
	mov	word ptr es:[2h],cs
	sti
	pop	es
	pop	ax
	retf
_install_int00_handler	endp

; ----------------------------------------------------------------------------
; void interrupt far int00_divide_recovery(void)
;
; INT 00 (divide-by-zero) handler installed by install_int00_handler. It walks
; the stacked CS:IP of the faulting instruction, identifies DIV/IDIV byte vs
; word (opcode 0xF6/0xF7), and hands back a synthetic quotient (AX >> 1, with
; the IDIV path folding DX bit 0 into the sign), letting the program keep
; running instead of dying on /0.
;
; Runs on the interrupt frame ([BP+2]=faulted IP, [BP+4]=faulted CS), loads
; the faulted CS into ES, and reads the faulting opcode at ES:[BX]. REWRITES
; the stacked return IP in place (MOV [BP+2],AX) to skip the DIV instruction.
; The result is computed from the interrupted, stack-saved AX/DX register
; state (POP AX; SAR DX,1; RCR AX,1) and returned in AX. Terminates with
; IRET, not RET/RETF.
; ----------------------------------------------------------------------------
_int00_divide_recovery	proc far
	push	bp
	mov	bp,sp
	push	bx
	push	es
	push	ax
	mov	ax,word ptr [bp+2]	; faulted IP
	mov	bx,ax
	mov	ax,word ptr [bp+4]	; faulted CS
	mov	es,ax
	mov	ax,word ptr es:[bx]	; faulting opcode word
	and	ax,0feh
	cmp	ax,0f6h			; DIV/IDIV (0xF6/0xF7)?
	jz	L_29a2
	sub	bx,2			; rewind past prefix byte
	mov	ax,bx
	mov	word ptr [bp+2],ax	; patch stacked return IP
L_29a2:
	mov	ax,word ptr es:[bx]
	test	ax,1			; word form (0xF7)?
	jz	L_29b1
	pop	ax			; restore interrupted AX
	sar	dx,1
	rcr	ax,1			; (DX:AX) >> 1, sign-aware
	jmp	short L_29b4
L_29b1:
	pop	ax			; restore interrupted AX
	sar	ax,1			; AX >> 1
L_29b4:
	pop	es
	pop	bx
	pop	bp
	iret
_int00_divide_recovery	endp

; ----------------------------------------------------------------------------
; void restore_int00_handler(void)
;
; Paired with install_int00_handler. If g_int00_installed is set, clears it
; and performs four IVT-slot-0 reads that are ALL dead code (see module
; header) -- the function never writes the IVT back, so INT 00 is left
; pointed at int00_divide_recovery even after "restore." A defect.
;
; No BP frame (PUSH AX / PUSH ES prologue, no PUSH BP). Uses DS-short-form
; MOV (A1/A2 opcodes) and ES-override short-form (26 A1 xx xx) for the direct
; word accesses.
; ----------------------------------------------------------------------------
_restore_int00_handler	proc far
	push	ax
	push	es
	xor	ax,ax
	cmp	byte ptr [_g_int00_installed],al
	jz	L_29d9
	mov	byte ptr [_g_int00_installed],al
	sub	ax,ax
	mov	es,ax
	cli
	mov	ax,word ptr [_g_wInt00SaveOff]
	mov	ax,word ptr es:[0000h]
	mov	ax,word ptr [_g_wInt00SaveSeg]
	mov	ax,word ptr es:[0002h]
	sti
L_29d9:
	pop	es
	pop	ax
	retf
_restore_int00_handler	endp

S180C_TEXT	ends
	end
