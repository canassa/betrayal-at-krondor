; ============================================================================
; TIMER.ASM -- KRONDOR.EXE timer/IRQ-0 + callback-registry driver module
; (segment 180c).
;
; Five routines, contiguous in the image (180c:1485..1669). One TASM module:
; the last three share the 4-byte saved-vector "data island" embedded INSIDE
; the code segment (CS:0x14ee/0x14f0), physically between registry_slot_free's
; last byte and timer_install's entry point:
;
;   _registry_slot_alloc   (180c:1485 / 0x19545) allocates a slot in the
;                          16-entry registry bitmask g_registry_slot_mask,
;                          storing callback_off/callback_seg into
;                          g_aTimerCallback[slot] and interval into both the
;                          wCountdown and wReload fields of
;                          g_aTimerSched[slot]. Returns the 1-based slot
;                          index, or 0 if the timer is not installed or the
;                          registry is full.
;   _registry_slot_free    (180c:14cf / 0x1958f) frees a slot previously
;                          returned by registry_slot_alloc by clearing bit
;                          (slot-1) in g_registry_slot_mask. Returns 1 if
;                          slot was in range [1..16], else 0.
;   _timer_install          (180c:14f2 / 0x195b2) reprograms PIT ch0 to
;                          `frequency` Hz, unmasks IRQ0/1, hooks INT 8 to
;                          _timer_irq0_dispatch, saving the old BIOS vector
;                          into the island.
;   _timer_restore_default (180c:155f / 0x1961f) restores 18.2 Hz + the
;                          saved INT 8 vector.
;   _timer_irq0_dispatch   (180c:1598 / 0x19658) the ISR: saturating
;                          frame-tick decrement, 5 unrolled callback slots,
;                          then either EOI+IRET or (every BiosChainReload
;                          ticks) JMPF through the island to chain the
;                          original BIOS timer handler.
;
; Per-routine idioms:
;   * registry_slot_alloc's bit-scan loop is carry-coupled: `SHR AX,1` feeds
;     CF into the very next `JNC`, and the 4-per-slot displacement is built
;     by repeated 8-bit `ADD BL,4` (not a shift/multiply) while CX is
;     shifted left in lockstep to build the eventual OR mask. Its "is the
;     registry full" test is `INC AX` / `JZ` (mask == 0xffff) immediately
;     followed by `DEC AX` to undo it -- a flag-only probe, not a compare.
;   * registry_slot_free builds a one-hot clear-mask with `STC` + `RCL
;     AX,CL` (rotate-through-carry from a hand-seeded 0xfffe), not a
;     shift/NOT pair.
;   * timer_install does `MOV word ptr CS:[0x14ee],BX` (a store into its own
;     code segment), inline INT 21h getvect/setvect, and direct 8253
;     (ports 0x40/0x43) + 8259 (port 0x21) I/O.
;   * timer_restore_default loads DS directly from the CS-resident island
;     (`MOV DX,word ptr CS:[g_savedTimerVec]` / `MOV DS,word ptr
;     CS:[g_savedTimerVec+2]`) ahead of the setvect INT 21h call.
;   * timer_irq0_dispatch is a manually-pushed ISR (explicit
;     AX/BX/CX/DX/BP/DS/ES/SI/DI push/pop in a fixed order, not the Borland
;     `interrupt` keyword's push order), uses BP as a live array base
;     (`MOV BP,offset DGROUP:_g_aTimerSched` then `[BP+SI]` addressing) held
;     across all five unrolled slots, dispatches each slot with a two-flag
;     `SHR/JA/JNC` test (JA falls through only when both CF=0 and ZF=0; JNC
;     alone catches the "chain to BIOS" case), and chains to the saved BIOS
;     handler with a `JMP dword ptr CS:[g_savedTimerVec]` through the island
;     rather than a normal call/return.
; The last three share the 4-byte CS-resident saved-vector island
; (CS:[0x14ee..0x14f1]), which sits physically between registry_slot_free's
; end and timer_install's entry point, so all five routines are one module.
;
; Absolutes relocated so they survive the relink:
;   * CS:0x14ee/0x14f0  -> label `g_savedTimerVec` in this segment. It sits
;     physically between `_registry_slot_free ENDP` and `_timer_install
;     PROC`, just ahead of 180c:14f2.
;   * MOV AX,0x39ae     -> MOV AX,DGROUP            (DGROUP segment)
;   * MOV DX,0x1598     -> MOV DX,offset _timer_irq0_dispatch (ISR offset)
; The cross-function near JMPs are intra-module labels. The CALL to the far C
; helper bios_compat_check is emitted as a FAR call (extrn :far), matching its
; object (same stack effect as PUSH CS + near CALL, the far<->near TLINK
; collapse, as in KEYBOARD.ASM's identical call). DGROUP globals are extrn
; symbols referenced by name.
; ============================================================================

	.286

	extrn	_bios_compat_check:far
	extrn	_blit_sprite_flipped_clipped:far	; RECTSPR.ASM; target of _dgroup_farptr_2c50

	; medium-model group, so DGROUP / ASSUME DS:DGROUP resolve
	; This module's _DATA block (DG 0x2c50..0x2ce0): the timer/IRQ-0 driver's
	; registry + callback state. _g_nTimerPitDivisor (0x2c57) is owned here and
	; read by JOYSTICK.ASM (which keeps its extrn).
_DATA	segment word public 'DATA'

	; DG+0x2c50 (4B) far ptr, init image [c9 0f 0c 18] = 180c:0fc9 = the entry
	; of blit_sprite_flipped_clipped (RECTSPR.ASM). No code reads offset 0x2c50
	; (no xref) and nothing stores the 0x0fc9 constant. Placed at the TIMER obj
	; HEAD on placement grounds: PALDRV's pool ends at 0x2c50 and the timer
	; scalars start at 0x2c54, so this 4B slot is contiguous with the timer
	; block. Owning TU unconfirmed.
	public	_dgroup_farptr_2c50
_dgroup_farptr_2c50	dd	_blit_sprite_flipped_clipped	; DGROUP+0x2c50 (4B) far ptr 180c:0fc9

	public	_g_timer_installed, _g_nFrameTickCountdown, _g_nTimerPitDivisor
	public	_g_nTimerBiosChainReload, _g_nTimerBiosChainCountdown, _g_registry_slot_mask
	public	_g_aTimerCallback, _g_aTimerSched, _dgroup_pad_2cdf

_g_timer_installed		db	0	; DGROUP+0x2c54 (1B) char
_g_nFrameTickCountdown		dw	0	; DGROUP+0x2c55 (2B) int
_g_nTimerPitDivisor		dw	0ffffh	; DGROUP+0x2c57 (2B) ushort
_g_nTimerBiosChainReload	dw	0	; DGROUP+0x2c59 (2B) ushort
_g_nTimerBiosChainCountdown	dw	0	; DGROUP+0x2c5b (2B) ushort
_g_registry_slot_mask		dw	0	; DGROUP+0x2c5d (2B) ushort
_g_aTimerCallback		dd	16 dup(0)	; DGROUP+0x2c5f (64B) TimerCallback[16] (far ptr[16])
_g_aTimerSched			dw	32 dup(0)	; DGROUP+0x2c9f (64B) TimerSched[16] {countdown,reload}
_dgroup_pad_2cdf		db	0	; DGROUP+0x2cdf (1B) zero pad; word-aligns the next obj (adapter table @0x2ce0)
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_registry_slot_alloc, _registry_slot_free
	public	_timer_install, _timer_restore_default, _timer_irq0_dispatch

; ----------------------------------------------------------------------------
; int far registry_slot_alloc(undefined2 callback_off, undefined2 callback_seg, undefined2 interval)
; [BP+6]  = callback_off
; [BP+8]  = callback_seg
; [BP+0Ah] = interval
; ----------------------------------------------------------------------------
_registry_slot_alloc	proc far
	push	bp
	mov	bp,sp
	sub	ax,ax
	cmp	byte ptr [_g_timer_installed],al
	jz	L_alloc_ret
	mov	ax,[_g_registry_slot_mask]
	inc	ax
	jz	L_alloc_ret
	dec	ax
	sub	bx,bx
	mov	cx,1
L_scan:
	shr	ax,1
	jnc	L_store
	shl	cx,1
	add	bl,4
	jmp	short L_scan
L_store:
	mov	ax,word ptr [bp+0ah]
	mov	word ptr [bx+_g_aTimerSched+2],ax
	mov	word ptr [bx+_g_aTimerSched],ax
	mov	ax,word ptr [bp+6]
	mov	word ptr [bx+_g_aTimerCallback],ax
	mov	ax,word ptr [bp+8]
	mov	word ptr [bx+_g_aTimerCallback+2],ax
	cli
	or	word ptr [_g_registry_slot_mask],cx
	sti
	mov	ax,bx
	shr	ax,1
	shr	ax,1
	inc	ax
L_alloc_ret:
	pop	bp
	retf
_registry_slot_alloc	endp

; ----------------------------------------------------------------------------
; int registry_slot_free(int slot)   [BP+6] = slot
; ----------------------------------------------------------------------------
_registry_slot_free	proc far
	push	bp
	mov	bp,sp
	sub	ax,ax
	mov	cx,word ptr [bp+6h]
	dec	cx
	test	cl,0f0h
	jnz	L_free_ret
	stc
	mov	ax,0fffeh
	rcl	ax,cl
	cli
	and	word ptr [_g_registry_slot_mask],ax
	sti
	mov	ax,1h
L_free_ret:
	pop	bp
	retf
_registry_slot_free	endp

; --- the 4-byte saved-vector data island (was CS:0x14ee / CS:0x14f0) ---------
; Far pointer to the original BIOS INT-8 handler; written by _timer_install,
; read by _timer_restore_default and chained through by _timer_irq0_dispatch.
; Sits physically HERE -- between _registry_slot_free and _timer_install --
; reproducing its original position just ahead of 180c:14f2.
g_savedTimerVec	dw	0		; offset (was CS:0x14ee)
		dw	0		; segment (was CS:0x14f0)

; ----------------------------------------------------------------------------
; void timer_install(uint frequency)   [BP+6] = frequency
; ----------------------------------------------------------------------------
_timer_install	proc far
	push	bp
	mov	bp,sp
	sub	ax,ax
	cmp	byte ptr [_g_timer_installed],al
	jnz	L_install_ret
	mov	[_g_registry_slot_mask],ax
	call	_bios_compat_check
	mov	ax,3508h			; INT 21h AH=35h: getvect(8) -> ES:BX
	int	21h
	mov	word ptr cs:[g_savedTimerVec],bx
	mov	word ptr cs:[g_savedTimerVec+2],es
	sub	ax,ax
	mov	dx,ax
	mov	bx,word ptr [bp+6]		; frequency
	cmp	bx,0ffh
	jg	L_install_ret
	or	bx,bx
	jz	L_install_ret
	dec	ax				; AX = 0xffff
	mov	word ptr [_g_nTimerBiosChainReload],bx
	mov	word ptr [_g_nTimerBiosChainCountdown],bx
	div	bx				; AX = 0xffff / frequency  (DX=0)
	mov	bx,ax
	mov	[_g_nTimerPitDivisor],ax
	cli
	mov	al,36h				; 8253 ch0 mode 3, lo/hi
	out	43h,al
	mov	al,bl
	out	40h,al
	mov	al,bh
	out	40h,al
	in	al,21h				; unmask IRQ0/IRQ1 in 8259
	and	al,0fch
	out	21h,al
	push	ds
	mov	ax,cs
	mov	ds,ax
	mov	dx,offset _timer_irq0_dispatch	; (was 0x1598) DS:DX = CS:ISR
	mov	ax,2508h			; INT 21h AH=25h: setvect(8)
	int	21h
	pop	ds
	sti
	mov	ax,1
	mov	byte ptr [_g_timer_installed],al
L_install_ret:
	pop	bp
	retf
_timer_install	endp

; ----------------------------------------------------------------------------
; int timer_restore_default(void)   -> AX (1 if was installed, else 0)
; ----------------------------------------------------------------------------
_timer_restore_default	proc far
	mov	ax,0
	cmp	byte ptr [_g_timer_installed],al
	jz	L_restore_ret
	sub	bx,bx				; divisor 0 -> default 18.2 Hz
	cli
	mov	al,36h
	out	43h,al
	mov	al,bl
	out	40h,al
	mov	al,bh
	out	40h,al
	in	al,21h
	and	al,0fch
	out	21h,al
	push	ds
	mov	dx,word ptr cs:[g_savedTimerVec]
	mov	ds,word ptr cs:[g_savedTimerVec+2]
	mov	ax,2508h			; setvect(8) <- saved BIOS vector
	int	21h
	pop	ds
	mov	ax,1
	mov	byte ptr [_g_timer_installed],0
	sti
L_restore_ret:
	retf
_timer_restore_default	endp

; ----------------------------------------------------------------------------
; void interrupt far timer_irq0_dispatch(void)   -- the IRQ-0 ISR
; ----------------------------------------------------------------------------
_timer_irq0_dispatch	proc far
	push	ax
	push	bx
	push	cx
	push	dx
	push	bp
	push	ds
	push	es
	push	si
	push	di
	mov	ax,DGROUP			; (was 0x39ae)
	mov	ds,ax
	mov	ax,[_g_nFrameTickCountdown]	; saturating decrement, clamp at 0
	dec	ax
	cwd
	xor	ax,dx
	mov	[_g_nFrameTickCountdown],ax
	sub	si,si
	mov	di,word ptr [_g_registry_slot_mask]
	mov	bp,offset DGROUP:_g_aTimerSched	; (was 0x2c9f) countdown[] base
L_isr_loop:
	; --- slot 0 ---
	shr	di,1
	ja	L_skip0
	jnc	L_isr_chain
	mov	ax,ds:[bp+si]
	dec	ax
	jnz	L_store0
	call	dword ptr [si+_g_aTimerCallback]
	mov	ax,[si+_g_aTimerSched+2]
L_store0:
	mov	ds:[bp+si],ax
L_skip0:
	add	si,4
	; --- slot 1 ---
	shr	di,1
	ja	L_skip1
	jnc	L_isr_chain
	mov	ax,ds:[bp+si]
	dec	ax
	jnz	L_store1
	call	dword ptr [si+_g_aTimerCallback]
	mov	ax,[si+_g_aTimerSched+2]
L_store1:
	mov	ds:[bp+si],ax
L_skip1:
	add	si,4
	; --- slot 2 ---
	shr	di,1
	ja	L_skip2
	jnc	L_isr_chain
	mov	ax,ds:[bp+si]
	dec	ax
	jnz	L_store2
	call	dword ptr [si+_g_aTimerCallback]
	mov	ax,[si+_g_aTimerSched+2]
L_store2:
	mov	ds:[bp+si],ax
L_skip2:
	add	si,4
	; --- slot 3 ---
	shr	di,1
	ja	L_skip3
	jnc	L_isr_chain
	mov	ax,ds:[bp+si]
	dec	ax
	jnz	L_store3
	call	dword ptr [si+_g_aTimerCallback]
	mov	ax,[si+_g_aTimerSched+2]
L_store3:
	mov	ds:[bp+si],ax
L_skip3:
	add	si,4
	; --- slot 4 ---
	shr	di,1
	ja	L_skip4
	jnc	L_isr_chain
	mov	ax,ds:[bp+si]
	dec	ax
	jnz	L_store4
	call	dword ptr [si+_g_aTimerCallback]
	mov	ax,[si+_g_aTimerSched+2]
L_store4:
	mov	ds:[bp+si],ax
L_skip4:
	add	si,4
	jmp	L_isr_loop			; (was JMP 0x15b9) drain remaining bits
L_isr_chain:
	mov	ax,[_g_nTimerBiosChainCountdown]
	dec	ax
	jz	L_isr_reload
	mov	[_g_nTimerBiosChainCountdown],ax
	pop	di
	pop	si
	pop	es
	pop	ds
	pop	bp
	pop	dx
	pop	cx
	pop	bx
	mov	al,20h				; non-specific EOI to master 8259
	out	20h,al
	pop	ax
	iret
L_isr_reload:
	mov	ax,[_g_nTimerBiosChainReload]
	mov	[_g_nTimerBiosChainCountdown],ax
	pop	di
	pop	si
	pop	es
	pop	ds
	pop	bp
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	jmp	dword ptr cs:[g_savedTimerVec]	; chain old BIOS INT-8 (was JMPF CS:0x14ee)
_timer_irq0_dispatch	endp

S180C_TEXT	ends
	end
