; ============================================================================
; KEYBOARD.ASM -- KRONDOR.EXE keyboard/input-ISR driver module (segment 180c).
;
; Seven routines, contiguous in the image (180c:1eb0..22ae). One TASM module:
; the first three are coupled through code-segment-resident state:
;
;   _keyboard_install         (180c:1eb0 / 0x19f70) hooks INT 9 (and, if
;                             install_timer_int, INT 1C) to _isr_keyboard,
;                             saving the prior vectors into an 8-byte data
;                             island embedded in CS just ahead of the entry;
;                             probes the BIOS keyboard ID via INT 15h AH=10h
;                             and either takes the extended-scancode path or
;                             self-modifies _isr_keyboard's two scancode mask
;                             immediates; tidies the BIOS shift-state byte.
;   _keyboard_restore_handler (180c:1f74 / 0x1a034) restores the saved INT 9 /
;                             INT 1C vectors from the island and clears the
;                             BIOS keyboard buffer.
;   _isr_keyboard             (180c:1fb2 / 0x1a072) the INT 9 ISR: reads port
;                             0x60, ack's the keyboard, translates scancodes
;                             (numpad remap + shift/ctrl/alt state), enqueues
;                             into the BIOS keyboard buffer, and on
;                             Ctrl-Alt-Del / Ctrl-Break far-calls
;                             boot_engine_exit.
;   _input_axis_accumulate_isr (180c:21a2 / 0x1a262) the INT 1C (BIOS
;                             timer-tick, ~18.2 Hz) user-interrupt handler
;                             installed by keyboard_install; integrates a
;                             per-tick delta into the two signed axis
;                             accumulators of the selected input-mode
;                             channels, clamped to [-0x7f, +0x7f].
;   _kbhit_read                (180c:2250 / 0x1a310) non-blocking BIOS
;                             keyboard buffer read under a PUSHF/CLI/POPF
;                             critical section.
;   _key_state_get_via_2cf8_table (180c:227f / 0x1a33f) key-state lookup via
;                             the g_input_mode_lut-indexed table, non-standard
;                             (BP-in-DX) frame.
;   _key_is_down               (180c:2299 / 0x1a359) g_key_state[scancode] & 1
;                             query, non-standard (BP-in-DX) frame guarded by
;                             CLI/STI.
;
; Per-routine idioms:
;   * keyboard_install does `MOV word ptr CS:[0x1ea8],BX` (a store into its
;     own code segment), inline INT 21h get/setvect, INT 15h, and BIOS-area
;     writes, and SELF-MODIFIES _isr_keyboard's two `AND DL,0xff` immediate
;     operands (CS:[0x203e] and CS:[0x204a] <- 0xfe) to disable the
;     keypad-remap mask once the enhanced-keyboard path is rejected.
;   * isr_keyboard is an interrupt handler doing port I/O, XLAT scancode
;     tables, and a far chain to boot_engine_exit.
;   * input_axis_accumulate_isr is an ISR that saves ALL registers
;     (AX,BX,CX,DX,DI,SI,BP,DS,ES -- NOT the Borland `interrupt` push order),
;     sets DS=DGROUP by hand, uses ES purely as a scratch register (holds the
;     tick magnitude, never a real segment), returns via IRET, and its body
;     is sign-magnitude bit-walking (SHL flag,1 / JNC, CWD/XOR/SUB) over
;     CS-flat DGROUP data.
;   * kbhit_read manipulates ES directly to address the BIOS Data Area
;     (segment 0040h), uses PUSHF/CLI/POPF for a critical section, and reads
;     ES:[BX] from an absolute hardware address.
;   * key_state_get_via_2cf8_table and key_is_down both use the non-standard
;     prologue/epilogue MOV DX,BP ; MOV BP,SP ... MOV BP,DX (BP saved in a
;     register, never pushed) instead of PUSH BP / POP BP; key_is_down also
;     wraps its body in CLI/STI.
; The first three share the 8-byte CS-resident saved-vector island
; (CS:[0x1ea8..0x1eaf]) and the install routine patches immediates physically
; inside isr_keyboard, so all seven are one module.
;
; Absolutes relocated so they survive the relink:
;   * CS:0x1ea8..0x1eaf  -> label `g_savedKbdVecs` in this segment (8 bytes:
;                           {off,seg} of the saved INT 9 and INT 1C vectors).
;     It sits physically FIRST in this module, immediately before
;     _keyboard_install's entry point, just ahead of 180c:1eb0.
;   * the two self-modify targets CS:[0x203e]/CS:[0x204a] -> the `0xff`
;     immediate operands of two `AND DL,0xff` instructions in _isr_keyboard,
;     referenced by the labels `kbd_mask1`/`kbd_mask2` placed AT those
;     operand bytes (never a hardcoded offset).
;   * MOV DX,0x1fb2 (DS:DX = ISR offset for setvect) -> offset _isr_keyboard.
;   * MOV DX,0x21a2 (the INT 1C handler offset) -> offset
;     _input_axis_accumulate_isr, an intra-module label.
;   * MOV AX,0x180c (the install routine's own CS paragraph, used as the
;     setvect segment) -> MOV AX,S180C_TEXT (the segment's relocatable
;     paragraph).
;   * MOV AX,0x39ae (DGROUP paragraph) -> MOV AX,DGROUP.
; Cross-function and intra-function near JMPs/CALLs are intra-module labels.
; bios_compat_check (seg 180c) is emitted as a far call (CALLF, extrn :far;
; PUSH CS + near CALL after the far->near collapse). The far chain to
; boot_engine_exit (seg 3800) is a genuine far call, `extrn :far`.
; DGROUP-relative data is referenced by extrn name (offset survives the
; relink); BIOS-data-area absolutes (ES=0x40, e.g. ES:[0x17], ES:[0x1a],
; ES:[0x1c]) stay literal -- fixed hardware addresses, not relocatable.
; ============================================================================

	.286

	extrn	_bios_compat_check:far		; seg 180c (far<->near via gate)
	extrn	_boot_engine_exit:far		; seg 3800 (genuine far chain)

	extrn	_g_graphics_context:byte	; container for the interior-field alias below
	include	gfxctx.inc

	; medium-model group, so DGROUP / ASSUME DS:DGROUP resolve
	; This module's _DATA block (DG 0x2ce0..0x2e86): the keyboard/input driver's
	; scancode-translation tables + ISR state. The head 16B at 0x2ce0 is
	; g_abAdapterRowStrideShift (see below).
_DATA	segment word public 'DATA'

	; DG+0x2ce0 (16B) g_abAdapterRowStrideShift: a per-video-adapter
	; row-stride-shift LUT, indexed only by blit_image_stretched (STRBLIT.C,
	; `mov cl,[BX+0x2ce0]`) — a video blitter, unrelated to the keyboard.
	; Placed at this obj's HEAD on alignment/position grounds: the 1B pad at
	; 0x2cdf word-aligns a new _DATA segment starting at 0x2ce0, and the
	; keyboard block ("andy" @0x2cf0) follows it contiguously, so
	; 0x2ce0..0x2e85 is one contiguous obj span. STRBLIT.C references it by
	; extrn. Owning TU unconfirmed.
	public	_g_abAdapterRowStrideShift
	public	_g_szAndyTag
	public	_g_keyboard_installed, _g_bCapsLockEnabled, _g_wIsrLastKeyEventDead
	public	_g_input_mode_lut, _g_bUnused2cfa, _g_key_state
	public	_g_ext_scancode_from, _g_ext_scancode_to, _g_bEnhancedKeyboard
	public	_dgroup_pad_2e84

_g_abAdapterRowStrideShift	label byte	; DGROUP+0x2ce0 (16B) uchar[16]
	db	0ffh,002h,003h,001h,0ffh,000h,0ffh,000h,000h,003h,001h,003h,003h,003h,003h,000h	; +0x2ce0
_g_szAndyTag	db	'andy'	; DGROUP+0x2cf0 (4B) dev tag, NO NUL (g_keyboard_installed supplies the 0)
_g_keyboard_installed	db	0	; DGROUP+0x2cf4 (1B) uchar
_g_bCapsLockEnabled	db	0	; DGROUP+0x2cf5 (1B) uchar
_g_wIsrLastKeyEventDead	dw	0	; DGROUP+0x2cf6 (2B) ushort
_g_input_mode_lut	db	0,0	; DGROUP+0x2cf8 (2B) byte[2]
_g_bUnused2cfa	label byte	; DGROUP+0x2cfa (250B) uchar[250] scancode-translation tables
	db	001h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h	; +0x2cfa
	db	000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h	; +0x2d0a
	db	000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h	; +0x2d1a
	db	000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h	; +0x2d2a
	db	000h,000h,000h,000h,000h,000h,000h,000h,000h,01bh,031h,032h,033h,034h,035h,036h	; +0x2d3a
	db	037h,038h,039h,030h,02dh,03dh,008h,009h,071h,077h,065h,072h,074h,079h,075h,069h	; +0x2d4a
	db	06fh,070h,05bh,05dh,00dh,084h,061h,073h,064h,066h,067h,068h,06ah,06bh,06ch,03bh	; +0x2d5a
	db	027h,060h,082h,05ch,07ah,078h,063h,076h,062h,06eh,06dh,02ch,02eh,02fh,081h,02ah	; +0x2d6a
	db	088h,020h,0c0h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h	; +0x2d7a
	db	000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h	; +0x2d8a
	db	000h,000h,01bh,021h,040h,023h,024h,025h,05eh,026h,02ah,028h,029h,05fh,02bh,008h	; +0x2d9a
	db	000h,051h,057h,045h,052h,054h,059h,055h,049h,04fh,050h,07bh,07dh,00dh,084h,041h	; +0x2daa
	db	053h,044h,046h,047h,048h,04ah,04bh,04ch,03ah,022h,07eh,082h,07ch,05ah,058h,043h	; +0x2dba
	db	056h,042h,04eh,04dh,03ch,03eh,03fh,081h,000h,088h,020h,0c0h,000h,000h,000h,000h	; +0x2dca
	db	000h,000h,000h,000h,000h,000h,000h,000h,037h,038h,039h,02dh,034h,035h,036h,02bh	; +0x2dda
	db	031h,032h,033h,030h,02eh,000h,000h,000h,000h,000h	; +0x2dea
_g_key_state	label byte	; DGROUP+0x2df4 (121B) uchar[121]
	db	000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h	; +0x2df4
	db	06eh,07eh,08eh,006h,006h,006h,006h,006h,006h,006h,002h,002h,000h,000h,05eh,09eh	; +0x2e04
	db	01eh,006h,006h,006h,006h,006h,006h,000h,000h,000h,000h,002h,04eh,03eh,02eh,006h	; +0x2e14
	db	006h,006h,006h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h	; +0x2e24
	db	000h,000h,000h,000h,000h,000h,000h,060h,070h,080h,000h,050h,090h,010h,000h,040h	; +0x2e34
	db	030h,020h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h,000h	; +0x2e44
	db	000h,001h,000h,001h,000h,003h,000h,080h,0a0h,040h,0e0h,0c0h,0f0h,060h,0b0h,000h	; +0x2e54
	db	008h,00ah,002h,006h,004h,005h,001h,009h,000h	; +0x2e64
_g_ext_scancode_from	db	059h,05ah,055h,054h,029h,058h,02bh,04ah,04eh,056h,057h	; DGROUP+0x2e6d (11B)
_g_ext_scancode_to	db	057h,058h,052h,046h,048h,047h,04bh,050h,04dh,053h,01ch	; DGROUP+0x2e78 (11B)
_g_bEnhancedKeyboard	db	0	; DGROUP+0x2e83 (1B) uchar
_dgroup_pad_2e84	db	0,0	; DGROUP+0x2e84 (2B) zero pad (unidentified, likely uninit joystick-block head)
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_keyboard_install, _keyboard_restore_handler, _isr_keyboard
	public	_input_axis_accumulate_isr, _kbhit_read
	public	_key_state_get_via_2cf8_table, _key_is_down

; --- the 8-byte CS-resident saved-vector island (was CS:[0x1ea8..0x1eaf]) ----
; Saved far pointers to the prior INT 9 (kbd) and INT 1C (timer-tick) handlers;
; written by _keyboard_install, read back by _keyboard_restore_handler. Must
; stay physically first in this module (immediately before _keyboard_install)
; to reproduce its original position just ahead of 180c:1eb0.
g_savedKbdVecs:
	dw	0		; +0 INT 9  offset  (was CS:0x1ea8)
	dw	0		; +2 INT 9  segment (was CS:0x1eaa)
	dw	0		; +4 INT 1C offset  (was CS:0x1eac)
	dw	0		; +6 INT 1C segment (was CS:0x1eae)

; ----------------------------------------------------------------------------
; int keyboard_install(int install_timer_int)   [BP+6] = install_timer_int
; ----------------------------------------------------------------------------
_keyboard_install	proc far
	push	bp
	mov	bp,sp
	push	di
	push	si
	sub	ax,ax
	cmp	byte ptr [_g_keyboard_installed],al
	jz	L_install_body
	jmp	L_install_tail
L_install_body:
	push	ds
	mov	ax,3509h			; INT 21h AH=35h: getvect(9) -> ES:BX
	int	21h
	mov	word ptr cs:[g_savedKbdVecs],bx
	mov	word ptr cs:[g_savedKbdVecs+2],es
	mov	ax,351ch			; getvect(0x1c) -> ES:BX
	int	21h
	mov	word ptr cs:[g_savedKbdVecs+4],bx
	mov	word ptr cs:[g_savedKbdVecs+6],es
	mov	dx,offset _isr_keyboard		; (was 0x1fb2) DS:DX = CS:ISR
	mov	ax,S180C_TEXT			; (was 0x180c) install routine's CS
	mov	ds,ax
	mov	ax,2509h			; setvect(9) <- _isr_keyboard
	int	21h
	mov	ax,word ptr [bp+6]		; install_timer_int
	neg	ax
	jnc	L_install_skip1c
	mov	dx,offset _input_axis_accumulate_isr	; (was 0x21a2) INT 1C handler offset
	mov	ax,S180C_TEXT			; (was 0x180c)
	mov	ds,ax
	mov	ax,251ch			; setvect(0x1c)
	int	21h
L_install_skip1c:
	pop	ds
	mov	byte ptr [_g_bEnhancedKeyboard],0
	call	_bios_compat_check		; (orig TLINK far->near: NOP;PUSH CS;CALL)
	neg	ax
	jnc	L_install_set			; bios_compat_check == 0 -> skip probe
	int	15h				; AH=10h keyboard ID probe (AH set by caller path)
	jnc	L_install_remap
	mov	ax,40h
	mov	es,ax
	mov	si,96h
	cmp	byte ptr es:[si],10h		; BDA 0x496 == 0x10 -> enhanced kbd
	jnz	L_install_remap
	mov	byte ptr [_g_bEnhancedKeyboard],1
	jmp	short L_install_set
L_install_remap:
	; disable the keypad-remap masks by patching isr_keyboard's two
	; `AND DL,0xff` immediates (CS:[0x203e]/CS:[0x204a]) to 0xfe.
	mov	byte ptr cs:[kbd_mask1+2],0feh	; patch AND DL,imm8 (orig CS:[0x203e])
	mov	byte ptr cs:[kbd_mask2+2],0feh	; patch AND DL,imm8 (orig CS:[0x204a])
	mov	bx,offset _g_key_state		; (was 0x2df4) key-state table
	mov	al,byte ptr [bx+48h]
	mov	byte ptr [bx+29h],al
	mov	al,byte ptr [bx+4bh]
	mov	byte ptr [bx+2bh],al
	mov	al,byte ptr [bx+4dh]
	mov	byte ptr [bx+4eh],al
	mov	al,byte ptr [bx+50h]
	mov	byte ptr [bx+4ah],al
L_install_set:
	mov	ax,1
	mov	[_g_keyboard_installed],al
L_install_tail:
	mov	ax,40h
	mov	es,ax
	and	byte ptr es:[17h],0dfh		; clear BIOS shift-state bit 0x20
	test	byte ptr [_g_bCapsLockEnabled],0ffh
	jz	L_install_ret
	or	byte ptr es:[17h],40h		; set caps-lock state bit
L_install_ret:
	mov	al,[_g_keyboard_installed]
	pop	si
	pop	di
	pop	bp
	retf
_keyboard_install	endp

; ----------------------------------------------------------------------------
; unsigned char keyboard_restore_handler(void)   -> AX (1 if was installed, else 0)
; ----------------------------------------------------------------------------
_keyboard_restore_handler	proc far
	sub	ax,ax
	cmp	byte ptr [_g_keyboard_installed],al
	jz	L_restore_ret
	mov	[_g_keyboard_installed],al
	mov	ax,40h
	mov	es,ax
	mov	ax,es:[1ch]			; BDA kbd buffer tail
	mov	es:[1ah],ax			; -> head (flush buffer)
	push	ds
	mov	dx,word ptr cs:[g_savedKbdVecs]	; saved INT 9 vector
	mov	ax,word ptr cs:[g_savedKbdVecs+2]
	mov	ds,ax
	mov	ax,2509h			; setvect(9) <- saved
	int	21h
	mov	dx,word ptr cs:[g_savedKbdVecs+4]	; saved INT 1C vector
	mov	ax,word ptr cs:[g_savedKbdVecs+6]
	mov	ds,ax
	mov	ax,251ch			; setvect(0x1c) <- saved
	int	21h
	pop	ds
	mov	ax,1
L_restore_ret:
	retf
_keyboard_restore_handler	endp

; ----------------------------------------------------------------------------
; void interrupt far isr_keyboard(void)   -- the INT 9 (IRQ-1) keyboard ISR
; ----------------------------------------------------------------------------
_isr_keyboard	proc far
	push	ax
	push	bx
	push	cx
	push	dx
	push	ds
	push	es
	push	di
	mov	ax,40h
	mov	es,ax
	mov	ax,DGROUP			; (was 0x39ae)
	mov	ds,ax
	xor	ax,ax
	in	al,60h				; read scancode from keyboard port
	mov	dx,61h
	mov	bx,ax
	in	al,dx				; pulse port 0x61 bit 7 to ack
	mov	ah,al
	or	al,80h
	out	dx,al
	mov	al,ah
	out	dx,al
	mov	ax,bx
	and	al,7fh				; AL = scancode (strip break bit)
	and	bl,80h				; BL = break flag
	cmp	byte ptr [_g_graphics_context.bBiosCompatible],1
	jnz	L_isr_translated
	cmp	byte ptr [_g_bEnhancedKeyboard],1
	jz	L_isr_chk_29
	mov	di,offset _g_ext_scancode_from	; (was 0x2e6d) -1 for pre-inc
	dec	di
	mov	cx,0bh
L_isr_extloop:
	inc	di
	cmp	al,byte ptr [di]
	loopnz	L_isr_extloop
	jnz	L_isr_translated
	add	di,0bh				; index into _g_ext_scancode_to
	mov	al,byte ptr [di]
	jmp	short L_isr_translated
L_isr_chk_29:
	cmp	al,29h
	jnz	L_isr_chk_2b
	mov	al,48h
L_isr_chk_2b:
	cmp	al,2bh
	jnz	L_isr_translated
	mov	al,4bh
L_isr_translated:
	or	al,bl				; re-apply break flag
	mov	dh,0ffh
	mov	dl,al
	shl	dx,1
	shr	dl,1
	cmp	dl,59h
	jl	L_isr_have_idx
	jmp	L_isr_eoi
L_isr_have_idx:
	xor	bh,bh
	mov	bl,dl
	mov	dl,byte ptr [bx+_g_key_state]	; (was 0x2df4)
	and	dh,dl
	xor	dh,1
	mov	byte ptr [bx+_g_key_state],dh
	cmp	byte ptr [_g_bEnhancedKeyboard],1
	jnz	L_isr_post
	cmp	bl,3ah
	jnz	L_isr_chk_45
	mov	al,bl
kbd_mask1:
	and	dl,0ffh				; CS:[0x203c]+2 self-modify target
	jmp	short L_isr_post
L_isr_chk_45:
	cmp	bl,45h
	jnz	L_isr_post
	mov	al,bl
kbd_mask2:
	and	dl,0ffh				; CS:[0x2048]+2 self-modify target
L_isr_post:
	mov	bx,offset _g_bUnused2cfa+48h	; (was 0x2d42) scancode->ascii XLAT base
	test	al,80h
	jz	L_isr_break
	test	dl,0f8h
	jz	L_isr_make_noidx
	mov	cx,dx
	mov	ch,0
	shr	cx,1
	shr	cx,1
	shr	cx,1
	mov	di,cx
	shr	cx,1
	and	di,1
	mov	ch,byte ptr [di+_g_input_mode_lut]	; (was 0x2cf8)
	cmp	ch,cl
	jnz	L_isr_make_noidx
	mov	byte ptr [di+_g_input_mode_lut],0
L_isr_make_noidx:
	mov	word ptr [_g_wIsrLastKeyEventDead],0
	and	al,7fh
	xlat
	test	al,80h
	jz	L_isr_make_done
	test	al,70h
	jnz	L_isr_make_done
	xor	al,7fh
	and	byte ptr es:[17h],al
L_isr_make_done:
	jmp	L_isr_eoi
L_isr_break:
	test	dl,0f8h
	jz	L_isr_brk_noidx
	mov	cx,dx
	mov	ch,0
	shr	cx,1
	shr	cx,1
	shr	cx,1
	mov	di,cx
	shr	cx,1
	and	di,1
	mov	byte ptr [di+_g_input_mode_lut],cl
L_isr_brk_noidx:
	mov	cl,al
	xor	ah,ah
	mov	di,ax
	xlat
	test	al,80h
	jz	L_isr_ascii
	and	al,7fh
	test	al,70h
	jnz	L_isr_mod_state
	or	byte ptr es:[17h],al
	jmp	L_isr_eoi
L_isr_mod_state:
	test	al,40h
	jz	L_isr_toggle
	test	byte ptr [_g_bCapsLockEnabled],0ffh
	jnz	L_isr_brk_eoi
L_isr_toggle:
	shr	dl,1
	jc	L_isr_brk_eoi
	xor	byte ptr es:[17h],al
L_isr_brk_eoi:
	jmp	L_isr_eoi
L_isr_ascii:
	test	byte ptr es:[17h],4		; ctrl down?
	jz	L_isr_chk_alt
	or	al,80h
	test	dl,4
	jz	L_isr_have_ascii
	sub	al,20h
	jmp	short L_isr_have_ascii
L_isr_chk_alt:
	test	byte ptr es:[17h],40h		; caps-lock?
	jz	L_isr_chk_shift
	test	dl,4
	jz	L_isr_chk_shift
	sub	al,20h
	jmp	short L_isr_have_ascii
L_isr_chk_shift:
	test	byte ptr es:[17h],3		; either shift?
	jz	L_isr_have_ascii
	mov	al,byte ptr [di+_g_bUnused2cfa+0a1h]	; (was 0x2d9b) shifted-ascii table
L_isr_have_ascii:
	mov	ah,cl				; AH = scancode, AL = ascii
	mov	[_g_wIsrLastKeyEventDead],ax
	mov	cx,word ptr es:[1ah]		; BDA kbd buffer head
	mov	di,word ptr es:[1ch]		; BDA kbd buffer tail
	cmp	cx,3ch
	jz	L_isr_head_wrap
	inc	cx
	inc	cx
	cmp	cx,di
	jz	L_isr_special
	jmp	short L_isr_enqueue
L_isr_head_wrap:
	cmp	di,1eh
	jz	L_isr_special
L_isr_enqueue:
	mov	word ptr es:[di],ax		; store into BIOS buffer
	cmp	di,3ch
	jnz	L_isr_no_wrap
	mov	di,1ch
L_isr_no_wrap:
	add	di,2
	mov	word ptr es:[1ch],di		; advance tail
L_isr_special:
	cmp	ah,20h				; D scancode?
	jnz	L_isr_chk_ctrlbreak
	test	byte ptr es:[17h],4		; ctrl?
	jz	L_isr_chk_ctrlbreak
	mov	al,20h
	out	20h,al				; EOI
	jmp	short L_isr_done
L_isr_chk_ctrlbreak:
	xor	bx,bx
	cmp	ax,19bh				; 019bh keycode scancode:ascii cmp, not addr
	jz	L_isr_reboot
	inc	bx
	cmp	ax,5380h			; 05380h Del keycode 53:80 cmp, not addr
	jnz	L_isr_eoi
	test	byte ptr es:[17h],8		; alt?
	jz	L_isr_eoi
L_isr_reboot:
	test	byte ptr es:[17h],4		; ctrl?
	jz	L_isr_eoi
	sub	di,2
	cmp	di,1ch
	jnz	L_isr_no_wrap2
	mov	di,3ch
L_isr_no_wrap2:
	mov	word ptr es:[di],0		; remove last buffered key
	mov	ax,es:[1ch]
	mov	es:[1ah],ax			; flush buffer
	mov	al,20h
	out	20h,al				; EOI
	sti
	mov	ax,bx
	push	ax
	call	_boot_engine_exit		; far chain (Ctrl-Alt-Del / Ctrl-Break)
	pop	ax
	jmp	short L_isr_done
L_isr_eoi:
	mov	al,20h
	out	20h,al				; non-specific EOI to master 8259
L_isr_done:
	pop	di
	pop	es
	pop	ds
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	iret
_isr_keyboard	endp

; ----------------------------------------------------------------------------
; void input_axis_accumulate_isr(void)   -- INT 1C handler, returns via IRET
;
; Each tick it integrates input into the keyboard/input-state block
; (g_key_state): for the 2 channels selected by g_input_mode_lut[0..1], it
; accumulates a signed delta (magnitude held at g_key_state+0x65) into two
; signed axis accumulators per channel (g_key_state+0x59 and +0x5d), clamping
; each to the signed-byte range [-0x7f, +0x7f]. A per-mode behaviour table
; (g_key_state+0x67) selects which of the two axes to update and the sign; a
; channel whose gate word (g_key_state+0x61) is zero is cleared. Sign
; handling uses the `CWD ; XOR ; SUB` abs/sign-restore idiom throughout.
; Label-style entry (no PROC/ENDP), matching the original's direct-vectored
; interrupt-handler shape.
; ----------------------------------------------------------------------------
_input_axis_accumulate_isr:
	push	ax				; 21a2
	push	bx				; 21a3
	push	cx				; 21a4
	push	dx				; 21a5
	push	di				; 21a6
	push	si				; 21a7
	push	bp				; 21a8
	push	ds				; 21a9
	push	es				; 21aa
	mov	ax,DGROUP			; 21ab (was 0x39ae)
	mov	ds,ax				; 21ae
	mov	ax,word ptr [_g_key_state+65h]		; 21b0  magnitude (was [0x2e59])
	mov	es,ax				; 21b3  ES = magnitude scratch
	mov	bp,7fh				; 21b5  clamp limit
	mov	si,2				; 21b8  channel index (2, then 0)
	mov	bh,0				; 21bb
L_loop:
	sub	ax,ax				; 21bd  AX = 0
	shr	si,1				; 21bf
	mov	bl,byte ptr [si+_g_input_mode_lut] ; 21c1 mode = lut[chan] (was [si+0x2cf8])
	shl	si,1				; 21c5
	dec	bl				; 21c7
	jns	short L_mode_ge1		; 21c9 (-> 21db)
	cmp	word ptr [si+_g_key_state+61h],ax ; 21cb gate (was [si+0x2e55])
	jz	short L_loop_bottom		; 21cf (-> 223e)
L_clear:
	mov	word ptr [si+_g_key_state+59h],ax ; 21d1 axis1 = 0 (was [si+0x2e4d])
	mov	word ptr [si+_g_key_state+5dh],ax ; 21d5 axis2 = 0 (was [si+0x2e51])
	jmp	short L_loop_bottom		; 21d9 (-> 223e)
L_mode_ge1:
	cmp	bl,8				; 21db
	jz	short L_clear			; 21de (-> 21d1)
	mov	bl,byte ptr [bx+_g_key_state+67h] ; 21e0 mode-flags (was [bx+0x2e5b])
	shl	bl,1				; 21e4  test axis1 enable
	jnc	short L_axis2			; 21e6 (-> 2212)
	mov	ax,word ptr [si+_g_key_state+59h] ; 21e8 axis1 (was [si+0x2e4d])
	cwd					; 21ec  abs(axis1) -> AX, sign -> DX
	xor	ax,dx				; 21ed
	sub	ax,dx				; 21ef
	mov	cx,ax				; 21f1  CX = |axis1|
	mov	di,dx				; 21f3  DI = sign(axis1)
	mov	ah,bl				; 21f5
	shl	bl,1				; 21f7
	cwd					; 21f9  delta-sign from BL msb
	xor	dx,di				; 21fa
	mov	ax,es				; 21fc  AX = magnitude
	xor	ax,dx				; 21fe  apply sign
	sub	ax,dx				; 2200
	add	ax,cx				; 2202  accumulate
	cmp	ax,bp				; 2204  clamp to +0x7f
	jle	short L_store1			; 2206 (-> 220a)
	mov	ax,bp				; 2208
L_store1:
	xor	ax,di				; 220a  restore axis1 sign
	sub	ax,di				; 220c
	mov	word ptr [si+_g_key_state+59h],ax ; 220e store axis1 (was [si+0x2e4d])
L_axis2:
	shl	bl,1				; 2212  test axis2 enable
	jnc	short L_loop_bottom		; 2214 (-> 223e)
	mov	ax,word ptr [si+_g_key_state+5dh] ; 2216 axis2 (was [si+0x2e51])
	cwd					; 221a  abs(axis2) -> AX, sign -> DX
	xor	ax,dx				; 221b
	sub	ax,dx				; 221d
	mov	cx,ax				; 221f  CX = |axis2|
	mov	di,dx				; 2221  DI = sign(axis2)
	mov	ah,bl				; 2223
	cwd					; 2225  delta-sign from BL msb
	xor	dx,di				; 2226
	mov	ax,es				; 2228  AX = magnitude
	xor	ax,dx				; 222a  apply sign
	sub	ax,dx				; 222c
	add	ax,cx				; 222e  accumulate
	cmp	ax,bp				; 2230  clamp to +0x7f
	jle	short L_store2			; 2232 (-> 2236)
	mov	ax,bp				; 2234
L_store2:
	xor	ax,di				; 2236  restore axis2 sign
	sub	ax,di				; 2238
	mov	word ptr [si+_g_key_state+5dh],ax ; 223a store axis2 (was [si+0x2e51])
L_loop_bottom:
	sub	si,2				; 223e  next channel
	js	short L_done			; 2241 (-> 2246)
	jmp	L_loop				; 2243 (-> 21bd)
L_done:
	pop	es				; 2246
	pop	ds				; 2247
	pop	bp				; 2248
	pop	si				; 2249
	pop	di				; 224a
	pop	dx				; 224b
	pop	cx				; 224c
	pop	bx				; 224d
	pop	ax				; 224e
	iret					; 224f

; ----------------------------------------------------------------------------
; unsigned kbhit_read(void)  -- non-blocking BIOS keyboard buffer read
;
; Reads the BIOS Data Area keyboard ring buffer (segment 0040h) under a
; PUSHF/CLI/POPF critical section, returns the buffered scancode:ASCII word
; in AX (0 if buffer empty), and advances the BDA kbd head with wrap-around.
; No DGROUP globals are referenced; the BIOS Data Area is accessed as an
; absolute far address via ES.
; ----------------------------------------------------------------------------
_kbhit_read	proc	far
	pushf
	cli
	push	es
	mov	ax,040h
	mov	es,ax
	xor	ax,ax
	mov	bx,word ptr es:[01ah]
	cmp	bx,word ptr es:[01ch]
	jz	L_227c
	mov	ax,word ptr es:[bx]
	inc	bx
	inc	bx
	cmp	bx,word ptr es:[082h]
	jnz	L_2277
	mov	bx,word ptr es:[080h]
L_2277:
	mov	word ptr es:[01ah],bx
L_227c:
	pop	es
	popf
	retf
_kbhit_read	endp

; ----------------------------------------------------------------------------
; int key_state_get_via_2cf8_table(int mode)   -- non-standard frame
;
; Disassembly (180c:227f):
;   MOV DX,BP          ; save caller's BP in DX (no stack push)
;   MOV BP,SP          ; frame pointer from SP
;   SUB BX,BX          ; BX = 0
;   MOV AX,[BP+4]      ; mode arg
;   NEG AX             ; sets CF if AX != 0
;   RCL BX,1           ; BX = (mode != 0) ? 1 : 0
;   MOV BL,[BX+0x2cf8] ; BL = g_input_mode_lut[BX]
;   MOV AH,BH          ; AH = 0 (BH is still 0)
;   MOV AL,[BX+0x2e63] ; AL = (g_key_state+0x6f)[BL]
;   MOV BP,DX          ; restore caller's BP from DX
;   RETF
;
; Non-standard prologue (MOV DX,BP; MOV BP,SP) and epilogue (MOV BP,DX; RETF):
; BP saved in a register, never pushed.
; ----------------------------------------------------------------------------
_key_state_get_via_2cf8_table	proc far
	mov	dx,bp
	mov	bp,sp
	sub	bx,bx
	mov	ax,word ptr [bp+4h]
	neg	ax
	rcl	bx,1h
	mov	bl,byte ptr [bx+_g_input_mode_lut]
	mov	ah,bh
	mov	al,byte ptr [bx+_g_key_state+06fh]
	mov	bp,dx
	retf
_key_state_get_via_2cf8_table	endp

; ----------------------------------------------------------------------------
; int key_is_down(int scancode)  -- non-standard frame, CLI/STI-guarded
;
; Disassembly (180c:2299):
;   CLI
;   MOV DX,BP
;   MOV BP,SP
;   MOV BX,word ptr [BP+4]
;   XOR AX,AX
;   MOV AL,byte ptr [BX+2df4h]
;   AND AL,1h
;   MOV BP,DX
;   STI
;   RETF
;
; Non-standard prologue (CLI + MOV DX,BP / MOV BP,SP): BP saved in a register,
; body wrapped in a CLI/STI critical section.
; ----------------------------------------------------------------------------
_key_is_down	proc far
	cli
	mov	dx,bp
	mov	bp,sp
	mov	bx,word ptr [bp+4h]
	xor	ax,ax
	mov	al,byte ptr [bx+_g_key_state]
	and	al,1h
	mov	bp,dx
	sti
	retf
_key_is_down	endp

S180C_TEXT	ends
	end
