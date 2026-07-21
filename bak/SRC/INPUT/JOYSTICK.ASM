; ============================================================================
; JOYSTICK.ASM -- KRONDOR.EXE segment 0x180c gameport/joystick driver module
; (180c:2349..180c:2609+30, linear 0x1a409..0x1a6f9, seven functions, one
; TASM TU).
;
; joystick_init, joystick_read_position and joystick_poll_axis NEAR-call the
; two register-convention helpers gameport_read_axis (axis bitmask in BL,
; results in DI/SI) and joystick_normalize_axis (AX/BX/CX in, AX out).
; joystick_read_direction reaches joystick_read_position -- a FAR proc in
; this module -- via the PUSH CS + NEAR CALL idiom (4 bytes, saves a byte over
; a real far call within the same segment; see GOURAUD.ASM's edge_step_init
; for the same pattern). One module so all of these intra-segment calls are
; real near calls, not masked external fixups.
;
;   2349  gameport_read_axis          (103 bytes)  near, gameport axis sampler
;   23b0  joystick_normalize_axis      (55 bytes)  near, raw sample -> position
;   23e7  joystick_init                (311 bytes)  far,  calibration/detection
;   251e  joystick_read_position       (120 bytes)  far,  per-stick X/Y reader
;   2596  joystick_read_direction       (89 bytes)  far,  4-way direction mask
;   25ef  joystick_button_pressed       (26 bytes)  far,  button-line reader
;   2609  joystick_poll_axis            (48 bytes)  far,  single-axis reader
;
; ============================================================================

	.286

; --- DGROUP / segment declarations -----------------------------------------
; This module's _DATA block (DG 0x2e86..0x2ea2): the gameport/joystick driver
; state. _g_nTimerPitDivisor (0x2c57) is owned by TIMER.ASM and stays an extrn
; here.
_DATA	segment word public 'DATA'

	public	_g_bJoystick0Installed, _g_bJoystick1Installed, _g_bJoyAxisTimeoutMask
	public	_g_nJoy0CenterX, _g_nJoy0CenterY, _g_nJoy1CenterX, _g_nJoy1CenterY
	public	_g_nJoy0SensX, _g_nJoy0SensY, _g_nJoy1SensX, _g_nJoy1SensY
	public	_g_nJoyReadScratchX, _g_nJoyLoopDelay, _g_nJoyDirScratchX, _g_nJoyDirScratchY
	public	_dgroup_pad_2ea1

_g_bJoystick0Installed	db	0	; DGROUP+0x2e86 (1B) uchar
_g_bJoystick1Installed	db	0	; DGROUP+0x2e87 (1B) uchar
_g_bJoyAxisTimeoutMask	db	0	; DGROUP+0x2e88 (1B) byte
_g_nJoy0CenterX		dw	0	; DGROUP+0x2e89 (2B) ushort
_g_nJoy0CenterY		dw	0	; DGROUP+0x2e8b (2B) ushort
_g_nJoy1CenterX		dw	0	; DGROUP+0x2e8d (2B) ushort
_g_nJoy1CenterY		dw	0	; DGROUP+0x2e8f (2B) ushort
_g_nJoy0SensX		dw	0	; DGROUP+0x2e91 (2B) ushort
_g_nJoy0SensY		dw	0	; DGROUP+0x2e93 (2B) ushort
_g_nJoy1SensX		dw	0	; DGROUP+0x2e95 (2B) ushort
_g_nJoy1SensY		dw	0	; DGROUP+0x2e97 (2B) ushort
_g_nJoyReadScratchX	dw	0	; DGROUP+0x2e99 (2B) ushort
_g_nJoyLoopDelay	dw	0	; DGROUP+0x2e9b (2B) ushort
_g_nJoyDirScratchX	dw	0	; DGROUP+0x2e9d (2B) short
_g_nJoyDirScratchY	dw	0	; DGROUP+0x2e9f (2B) short
_dgroup_pad_2ea1	db	0	; DGROUP+0x2ea1 (1B) zero pad (unidentified)
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

	extrn	_g_nTimerPitDivisor:word	; DGROUP+0x2c57 (owned by TIMER.ASM)

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_gameport_read_axis
	public	_joystick_normalize_axis
	public	_joystick_init
	public	_joystick_read_position
	public	_joystick_read_direction
	public	_joystick_button_pressed
	public	_joystick_poll_axis

; ============================================================================
; gameport_read_axis @ 180c:2349 (linear 0x1a409, 103 bytes)
;
;   - Non-standard register calling convention: the axis bitmask is passed in
;     BL (no stack args; all callers MOV BX before the CALL). The result is
;     returned in DI (X count) and SI (Y count), accumulated bit-by-bit with
;     ADC SI/DI,0 from SHR of the port byte -- AX is not a meaningful return.
;   - Manual prologue/epilogue wrapping an interrupt-disabled critical
;     section: PUSHF; PUSH BP; CLI ... POP BP; POPF; RET.
;   - BP is loaded from g_nJoyLoopDelay and used as a LOOP reload counter,
;     not as a frame pointer.
;   - Timing-critical IN/OUT polling of gameport port 0x201 (LOOP $ delays).
;
; Disassembly (180c:2349):
;   MOV DX,0x201
;   PUSHF
;   PUSH BP
;   CLI
;   MOV BP,word ptr [0x2e9b]   ; g_nJoyLoopDelay
;   MOV CX,0x190               ; 400 sample-attempt budget
;   MOV AX,CX
;   MOV CX,BP                  ; inner settle-delay reload
; L_a41a:
;   LOOP L_a41a               ; busy delay (LOOP $)
;   MOV CX,AX
;   IN AL,DX                  ; read port 0x201
;   TEST BL,AL
;   LOOPNZ L_a416             ; while bits still set, retry
;   JCXZ L_a425
;   MOV CX,0x190
;   XOR AL,AL
;   OUT DX,AL                 ; start the one-shot timers
;   XOR SI,SI                 ; Y count = 0
;   MOV DI,SI                 ; X count = 0
;   TEST BL,0x3               ; JS1 (bits 0-1) vs JS2 (bits 2-3) path
;   JZ L_a450
;   ... (JS1 path: 1-bit & 2-bit shift accumulate)
;   ... (JS2 path: 3-bit shift accumulate)
; ============================================================================

_gameport_read_axis	proc near
	mov	dx,201h		; 201h gameport I/O port (in/out dx), not DGROUP
	pushf
	push	bp
	cli
	mov	bp,word ptr [_g_nJoyLoopDelay]
	mov	cx,190h		; 190h sample budget 400
L_2356:
	mov	ax,cx
	mov	cx,bp
L_235a:
	loop	L_235a
	mov	cx,ax
	in	al,dx
	test	al,bl
	loopnz	L_2356
	jcxz	L_2365
L_2365:
	mov	cx,190h		; 190h accumulate budget 400
	xor	al,al
	out	dx,al
	xor	si,si
	mov	di,si
	test	bl,3h
	jz	L_2390
L_2374:
	mov	ax,cx
	mov	cx,bp
L_2378:
	loop	L_2378
	mov	cx,ax
	in	al,dx
	and	al,bl
	jz	L_238d
	shr	al,1h
	adc	si,0h
	shr	al,1h
	adc	di,0h
	loop	L_2374
L_238d:
	pop	bp
	popf
	ret
L_2390:
	mov	ax,cx
	mov	cx,bp
L_2394:
	loop	L_2394
	mov	cx,ax
	in	al,dx
	and	al,bl
	jz	L_238d
	shr	al,1h
	shr	al,1h
	shr	al,1h
	adc	si,0h
	shr	al,1h
	adc	di,0h
	loop	L_2390
	pop	bp
	popf
	ret
_gameport_read_axis	endp

; ============================================================================
; joystick_normalize_axis @ 180c:23b0 (linear 0x1a470, 55 bytes)
;
; Register-convention joystick-axis normalizer (near, RET): inputs and result
; live in registers, with no stack frame.
;   IN : AX = raw axis sample
;        BX = center value
;        CX = sensitivity scale (0 => skip scaling)
;   OUT: AX = signed clamped position (deadzone |x|<8 -> 0, clamp +/-0x7f)
; Computes (AX-BX) keeping sign (DI=1 if negative), takes the magnitude,
; scales by CX via 16x16->32 MUL and takes (DX:AX >> 8) into AX, clamps to
; 0x7f, applies an 8-count deadzone, then re-applies the saved sign.
;
; Register-IN/OUT calling convention with a non-standard prologue (PUSH DI
; only, no PUSH BP frame) and DX:AX MUL result handling.
;
; Disassembly (180c:23b0, linear 0x1a470, 55 bytes):
;   PUSH DI
;   SUB  AX,BX
;   OR   AX,AX
;   JGE  L_pos          ; signed >= 0
;   MOV  DI,1
;   NEG  AX
;   JMP  L_have_sign
; L_pos:
;   MOV  DI,0
; L_have_sign:
;   OR   CX,CX
;   JZ   L_no_scale
;   XOR  DX,DX
;   MUL  CX             ; DX:AX = mag * scale
;   MOV  AL,AH          ; AX = (DX:AX) >> 8
;   MOV  AH,DL
; L_no_scale:
;   CMP  AX,7Fh
;   JBE  L_no_clamp
;   MOV  AX,7Fh
; L_no_clamp:
;   CMP  AL,8
;   JNC  L_no_dead      ; >= 8 keep
;   XOR  AL,AL
; L_no_dead:
;   XOR  AH,AH
;   TEST DI,1
;   JZ   L_done
;   NEG  AX
; L_done:
;   POP  DI
;   RET
; ============================================================================

; Register-only leaf: no callees, no DGROUP globals referenced.
_joystick_normalize_axis	proc near
	push	di
	sub	ax,bx
	or	ax,ax
	jge	L_pos			; signed (AX-BX) >= 0
	mov	di,1
	neg	ax
	jmp	L_have_sign
L_pos:
	mov	di,0
L_have_sign:
	or	cx,cx
	jz	L_no_scale
	xor	dx,dx
	mul	cx			; DX:AX = magnitude * scale
	mov	al,ah			; AX = (DX:AX) >> 8
	mov	ah,dl
L_no_scale:
	cmp	ax,7Fh
	jbe	L_no_clamp
	mov	ax,7Fh
L_no_clamp:
	cmp	al,8
	jnc	L_no_dead		; >= 8: keep
	xor	al,al			; deadzone -> 0
L_no_dead:
	xor	ah,ah			; zero-extend low byte
	test	di,1
	jz	L_done
	neg	ax			; re-apply saved sign
L_done:
	pop	di
	ret
_joystick_normalize_axis	endp

; ============================================================================
; joystick_init @ 180c:23e7 (linear 0x1a4a7, 311 bytes)
;
; Gameport one-time calibration and detection.  Times the gameport monostable
; (port 0x201) against PIT channel 0 to derive g_nJoyLoopDelay, then calls
; gameport_read_axis twice to sample resting-center and sensitivity for each
; joystick axis, probes the button lines to set g_bJoystick0Installed /
; g_bJoystick1Installed, and returns the 2-bit installed bitmask (joy1<<1|joy0).
;
; Contains RCR [mem],1 instructions that use the carry flag from a preceding
; CMP to rotate a byte global (g_bJoyAxisTimeoutMask). gameport_read_axis is
; the register-convention callee (arg in BL, results returned in SI and DI).
;
; Two non-canonical encodings: the forced `db 086h,0c4h` XCHG AH,AL forms
; (offsets 0x1b, 0x38) and the 3-byte `cmp ax,000h` form (offset 0x56).
; ============================================================================

_joystick_init	proc far
	; offset 0x00
	push	si
	; offset 0x01
	push	di
	; offset 0x02
	cli
	; offset 0x03: MOV AL,0x36 (b0 36)
	mov	al,036h
	; offset 0x05: OUT 0x43,AL (e6 43)
	out	043h,al
	; offset 0x07: XOR AL,AL (32 c0)
	xor	al,al
	; offset 0x09: OUT 0x40,AL (e6 40)
	out	040h,al
	; offset 0x0b: OUT 0x40,AL (e6 40)
	out	040h,al
	; offset 0x0d: MOV DX,0x201 (ba 01 02)
	mov	dx,0201h		; 0201h gameport I/O port (in/out dx)
	; offset 0x10: MOV CX,0x3e8 (b9 e8 03)
	mov	cx,03e8h		; 03e8h calib loop count 1000
	; offset 0x13: OUT 0x43,AL (e6 43)
	out	043h,al
	; offset 0x15: IN AL,0x40 (e4 40)
	in	al,040h
	; offset 0x17: MOV AH,AL (8a e0)
	mov	ah,al
	; offset 0x19: IN AL,0x40 (e4 40)
	in	al,040h
	; offset 0x1b: XCHG AH,AL (86 c4) -- force reg=AL(0) rm=AH(4) form
	db	086h, 0c4h
	; offset 0x1d: MOV SI,AX (8b f0)
	mov	si,ax
	; offset 0x1f: loop body start (LOOP at 0x2c goes back here)
L_loop1:
	; offset 0x1f: MOV AX,AX (8b c0) -- delay
	mov	ax,ax
	; offset 0x21: MOV AX,AX (8b c0) -- delay
	mov	ax,ax
	; offset 0x23-0x26: NOP x4 -- delay
	nop
	nop
	nop
	nop
	; offset 0x27: MOV AX,AX (8b c0) -- delay
	mov	ax,ax
	; offset 0x29: IN AL,DX (ec)
	in	al,dx
	; offset 0x2a: TEST AL,AL (84 c0)
	test	al,al
	; offset 0x2c: LOOP L_loop1 (e2 f1 = -15)
	loop	L_loop1
	; offset 0x2e: MOV AL,0x6 (b0 06)
	mov	al,006h
	; offset 0x30: OUT 0x43,AL (e6 43)
	out	043h,al
	; offset 0x32: IN AL,0x40 (e4 40)
	in	al,040h
	; offset 0x34: MOV AH,AL (8a e0)
	mov	ah,al
	; offset 0x36: IN AL,0x40 (e4 40)
	in	al,040h
	; offset 0x38: XCHG AH,AL (86 c4) -- force reg=AL(0) rm=AH(4) form
	db	086h, 0c4h
	; offset 0x3a: MOV DI,AX (8b f8)
	mov	di,ax
	; offset 0x3c: MOV BX,[0x2c57] = g_nTimerPitDivisor (8b 1e 57 2c)
	mov	bx,word ptr [_g_nTimerPitDivisor]
	; offset 0x40: MOV AL,0x36 (b0 36)
	mov	al,036h
	; offset 0x42: OUT 0x43,AL (e6 43)
	out	043h,al
	; offset 0x44: MOV AL,BL (8a c3)
	mov	al,bl
	; offset 0x46: OUT 0x40,AL (e6 40)
	out	040h,al
	; offset 0x48: MOV AL,BH (8a c7)
	mov	al,bh
	; offset 0x4a: OUT 0x40,AL (e6 40)
	out	040h,al
	; offset 0x4c: STI (fb)
	sti
	; offset 0x4d: SUB SI,DI (2b f7)
	sub	si,di
	; offset 0x4f: XOR DX,DX (33 d2)
	xor	dx,dx
	; offset 0x51: MOV AX,0x6fcc (b8 cc 6f)
	mov	ax,06fcch
	; offset 0x54: DIV SI (f7 f6)
	div	si
	; offset 0x56: CMP AX,0x0 (3d 00 00) -- 3-byte imm16 form
	cmp	ax,000h
	; offset 0x59: JNZ L_2445 (75 03)
	jnz	L_2445
	; offset 0x5b: MOV AX,0x1 (b8 01 00)
	mov	ax,0001h
L_2445:
	; offset 0x5e: MOV [0x2e9b],AX = g_nJoyLoopDelay (a3 9b 2e)
	mov	word ptr [_g_nJoyLoopDelay],ax
	; offset 0x61: MOV BX,0x3 (bb 03 00)
	mov	bx,0003h
	; offset 0x64: CALL gameport_read_axis (e8 fb fe)
	call	near ptr _gameport_read_axis
	; offset 0x67: MOV AX,SI (8b c6) -- SI = result from gameport_read_axis
	mov	ax,si
	; offset 0x69: MOV [0x2e89],AX = g_nJoy0CenterX (a3 89 2e)
	mov	word ptr [_g_nJoy0CenterX],ax
	; offset 0x6c: CMP AX,0x190 (3d 90 01)
	cmp	ax,0190h		; axis-center bound (400)
	; offset 0x6f: RCR [0x2e88],1 = g_bJoyAxisTimeoutMask (d0 1e 88 2e)
	rcr	byte ptr [_g_bJoyAxisTimeoutMask],1
	; offset 0x73: MOV AX,DI (8b c7) -- DI = result from gameport_read_axis
	mov	ax,di
	; offset 0x75: MOV [0x2e8b],AX = g_nJoy0CenterY (a3 8b 2e)
	mov	word ptr [_g_nJoy0CenterY],ax
	; offset 0x78: CMP AX,0x190 (3d 90 01)
	cmp	ax,0190h		; axis-center bound (400)
	; offset 0x7b: RCR [0x2e88],1 (d0 1e 88 2e)
	rcr	byte ptr [_g_bJoyAxisTimeoutMask],1
	; offset 0x7f: MOV AL,[0x2e88] (a0 88 2e)
	mov	al,byte ptr [_g_bJoyAxisTimeoutMask]
	; offset 0x82: AND AL,0xc0 (24 c0)
	and	al,0c0h
	; offset 0x84: CMP AL,0xc0 (3c c0)
	cmp	al,0c0h
	; offset 0x86: JNZ L_2476 (75 07)
	jnz	L_2476
	; offset 0x88: MOV byte ptr [0x2e86],0x1 (c6 06 86 2e 01)
	mov	byte ptr [_g_bJoystick0Installed],001h
	; offset 0x8d: JMP L_247b (eb 05)
	jmp	short L_247b
L_2476:
	; offset 0x8f: MOV byte ptr [0x2e86],0x0 (c6 06 86 2e 00)
	mov	byte ptr [_g_bJoystick0Installed],000h
L_247b:
	; offset 0x94: OR SI,SI (0b f6)
	or	si,si
	; offset 0x96: JZ L_248b (74 0c)
	jz	L_248b
	; offset 0x98: MOV CX,SI (8b ce)
	mov	cx,si
	; offset 0x9a: MOV AX,0x7f00 (b8 00 7f)
	mov	ax,07f00h
	; offset 0x9d: XOR DX,DX (33 d2)
	xor	dx,dx
	; offset 0x9f: DIV CX (f7 f1)
	div	cx
	; offset 0xa1: MOV [0x2e91],AX = g_nJoy0SensX (a3 91 2e)
	mov	word ptr [_g_nJoy0SensX],ax
L_248b:
	; offset 0xa4: OR DI,DI (0b ff)
	or	di,di
	; offset 0xa6: JZ L_249b (74 0c)
	jz	L_249b
	; offset 0xa8: MOV CX,DI (8b cf)
	mov	cx,di
	; offset 0xaa: MOV AX,0x7f00 (b8 00 7f)
	mov	ax,07f00h
	; offset 0xad: XOR DX,DX (33 d2)
	xor	dx,dx
	; offset 0xaf: DIV CX (f7 f1)
	div	cx
	; offset 0xb1: MOV [0x2e93],AX = g_nJoy0SensY (a3 93 2e)
	mov	word ptr [_g_nJoy0SensY],ax
L_249b:
	; offset 0xb4: MOV BX,0xc (bb 0c 00)
	mov	bx,000ch
	; offset 0xb7: CALL gameport_read_axis (e8 a8 fe)
	call	near ptr _gameport_read_axis
	; offset 0xba: MOV AX,SI (8b c6)
	mov	ax,si
	; offset 0xbc: CMP AX,0x190 (3d 90 01) -- NOTE: CMP before MOV (differs from first call)
	cmp	ax,0190h		; axis-center bound (400)
	; offset 0xbf: MOV [0x2e8d],AX = g_nJoy1CenterX (a3 8d 2e)
	mov	word ptr [_g_nJoy1CenterX],ax
	; offset 0xc2: RCR [0x2e88],1 (d0 1e 88 2e)
	rcr	byte ptr [_g_bJoyAxisTimeoutMask],1
	; offset 0xc6: MOV AX,DI (8b c7)
	mov	ax,di
	; offset 0xc8: MOV [0x2e8f],AX = g_nJoy1CenterY (a3 8f 2e)
	mov	word ptr [_g_nJoy1CenterY],ax
	; offset 0xcb: CMP AX,0x190 (3d 90 01)
	cmp	ax,0190h		; axis-center bound (400)
	; offset 0xce: RCR [0x2e88],1 (d0 1e 88 2e)
	rcr	byte ptr [_g_bJoyAxisTimeoutMask],1
	; offset 0xd2: MOV AL,[0x2e88] (a0 88 2e)
	mov	al,byte ptr [_g_bJoyAxisTimeoutMask]
	; offset 0xd5: AND AL,0xc0 (24 c0)
	and	al,0c0h
	; offset 0xd7: CMP AL,0xc0 (3c c0)
	cmp	al,0c0h
	; offset 0xd9: JNZ L_24c9 (75 07)
	jnz	L_24c9
	; offset 0xdb: MOV byte ptr [0x2e87],0x1 (c6 06 87 2e 01)
	mov	byte ptr [_g_bJoystick1Installed],001h
	; offset 0xe0: JMP L_24ce (eb 05)
	jmp	short L_24ce
L_24c9:
	; offset 0xe2: MOV byte ptr [0x2e87],0x0 (c6 06 87 2e 00)
	mov	byte ptr [_g_bJoystick1Installed],000h
L_24ce:
	; offset 0xe7: OR SI,SI (0b f6)
	or	si,si
	; offset 0xe9: JZ L_24de (74 0c)
	jz	L_24de
	; offset 0xeb: MOV CX,SI (8b ce)
	mov	cx,si
	; offset 0xed: MOV AX,0x7f00 (b8 00 7f)
	mov	ax,07f00h
	; offset 0xf0: XOR DX,DX (33 d2)
	xor	dx,dx
	; offset 0xf2: DIV CX (f7 f1)
	div	cx
	; offset 0xf4: MOV [0x2e95],AX = g_nJoy1SensX (a3 95 2e)
	mov	word ptr [_g_nJoy1SensX],ax
L_24de:
	; offset 0xf7: OR DI,DI (0b ff)
	or	di,di
	; offset 0xf9: JZ L_24ee (74 0c)
	jz	L_24ee
	; offset 0xfb: MOV CX,DI (8b cf)
	mov	cx,di
	; offset 0xfd: MOV AX,0x7f00 (b8 00 7f)
	mov	ax,07f00h
	; offset 0x100: XOR DX,DX (33 d2)
	xor	dx,dx
	; offset 0x102: DIV CX (f7 f1)
	div	cx
	; offset 0x104: MOV [0x2e97],AX = g_nJoy1SensY (a3 97 2e)
	mov	word ptr [_g_nJoy1SensY],ax
L_24ee:
	; offset 0x107: MOV DX,0x201 (ba 01 02)
	mov	dx,0201h
	; offset 0x10a: OUT DX,AL (ee)
	out	dx,al
	; offset 0x10b: MOV CX,0x14 (b9 14 00)
	mov	cx,0014h
	; offset 0x10e: LOOP $ (e2 fe = loop to self, 20-iteration tight delay)
L_loop2:
	loop	L_loop2
	; offset 0x110: IN AL,DX (ec)
	in	al,dx
	; offset 0x111: TEST AL,0x3 (a8 03)
	test	al,003h
	; offset 0x113: JNZ L_2501 (75 05)
	jnz	L_2501
	; offset 0x115: MOV byte ptr [0x2e86],0x0 (c6 06 86 2e 00)
	mov	byte ptr [_g_bJoystick0Installed],000h
L_2501:
	; offset 0x11a: TEST AL,0xc (a8 0c)
	test	al,00ch
	; offset 0x11c: JNZ L_250a (75 05)
	jnz	L_250a
	; offset 0x11e: MOV byte ptr [0x2e87],0x0 (c6 06 87 2e 00)
	mov	byte ptr [_g_bJoystick1Installed],000h
L_250a:
	; offset 0x123: MOV CL,0x4 (b1 04)
	mov	cl,004h
	; offset 0x125: SHR [0x2e88],CL (d2 2e 88 2e)
	shr	byte ptr [_g_bJoyAxisTimeoutMask],cl
	; offset 0x129: XOR AX,AX (33 c0)
	xor	ax,ax
	; offset 0x12b: MOV AL,[0x2e87] (a0 87 2e)
	mov	al,byte ptr [_g_bJoystick1Installed]
	; offset 0x12e: SHL AL,0x1 (d0 e0)
	shl	al,001h
	; offset 0x130: OR AL,[0x2e86] (0a 06 86 2e)
	or	al,byte ptr [_g_bJoystick0Installed]
	; offset 0x134: POP DI (5f)
	pop	di
	; offset 0x135: POP SI (5e)
	pop	si
	; offset 0x136: RETF (cb)
	retf

_joystick_init	endp

; ============================================================================
; joystick_read_position @ 180c:251e (linear 0x1a5de, 120 bytes)
;
; Couples to two register-convention helpers, both intra-unit above:
;   - gameport_read_axis takes its axis bitmask in BL (no stack args) and
;     returns the two axis counts in DI (X) and SI (Y) -- AX is not a return.
;     joystick_read_position MOVes BX=3 (JS1) or BX=0xc (JS2) before the CALL
;     and then consumes the SI/DI results directly.
;   - joystick_normalize_axis takes the raw count in AX, the center in BX and
;     the sensitivity in CX (all registers, no stack args), returning the
;     normalised value in AX. joystick_read_position MOVes AX=SI / AX=DI and
;     loads BX/CX from the calibration globals before each CALL.
;
; Disassembly (180c:251e):
;   PUSH BP / MOV BP,SP / PUSH SI / PUSH DI
;   MOV BX,[BP+6]               ; which
;   CMP BX,0 / JNZ js1_path
;   ... joystick 0 path (g_bJoystick0Installed, g_nJoy0Center{X,Y}/Sens{X,Y})
;   ... joystick 1 path (g_bJoystick1Installed, g_nJoy1Center{X,Y}/Sens{X,Y})
;   store: [out_y]=AX (normalised DI), [out_x]=g_nJoyReadScratchX
; ============================================================================

_joystick_read_position	proc far
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	bx,word ptr [bp+6h]		; which
	cmp	bx,0h
	jnz	L_2559
	xor	ah,ah
	mov	al,[_g_bJoystick0Installed]
	or	al,al
	jz	L_2592
	mov	bx,3h				; JS1 axis bitmask
	call	_gameport_read_axis		; -> DI=X, SI=Y
	mov	bx,word ptr [_g_nJoy0CenterX]
	mov	cx,word ptr [_g_nJoy0SensX]
	mov	ax,si
	call	_joystick_normalize_axis
	mov	[_g_nJoyReadScratchX],ax
	mov	bx,word ptr [_g_nJoy0CenterY]
	mov	cx,word ptr [_g_nJoy0SensY]
	mov	ax,di
	call	_joystick_normalize_axis
	jmp	L_2585
L_2559:
	xor	ah,ah
	mov	al,[_g_bJoystick1Installed]
	or	al,al
	jz	L_2592
	mov	bx,0ch				; JS2 axis bitmask
	call	_gameport_read_axis		; -> DI=X, SI=Y
	mov	bx,word ptr [_g_nJoy1CenterX]
	mov	cx,word ptr [_g_nJoy1SensX]
	mov	ax,si
	call	_joystick_normalize_axis
	mov	[_g_nJoyReadScratchX],ax
	mov	bx,word ptr [_g_nJoy1CenterY]
	mov	cx,word ptr [_g_nJoy1SensY]
	mov	ax,di
	call	_joystick_normalize_axis
L_2585:
	mov	si,word ptr [bp+0ah]		; out_y
	mov	di,word ptr [bp+8h]		; out_x
	mov	word ptr [si],ax
	mov	ax,[_g_nJoyReadScratchX]
	mov	word ptr [di],ax
L_2592:
	pop	di
	pop	si
	pop	bp
	retf
_joystick_read_position	endp

; ============================================================================
; joystick_read_direction @ 180c:2596 (linear 0x1a656, 89 bytes)
;
; The call to joystick_read_position uses the intra-segment VROOMM pattern:
; PUSH CS; CALL near (a 4-byte "call far via near PUSH-CS trick"). The
; direction accumulator is AX (16-bit OR AX,N), not DL.
;
; Disassembly (180c:2596):
;   PUSH BP / MOV BP,SP
;   MOV AX,[BP+6]             ; which
;   OR AX,AX / JZ joy0
;   MOV AL,[g_bJoystick1Installed]
;   JMP test_installed
; joy0:
;   MOV AL,[g_bJoystick0Installed]
; test_installed:
;   OR AL,AL / JZ ret0
;   push g_nJoyDirScratchY, g_nJoyDirScratchX, which
;   PUSH CS / CALL near joystick_read_position
;   ADD SP,6
;   XOR AX,AX
;   MOV BX,[g_nJoyDirScratchX]
;   CMP BX,-30 / JGE; OR AX,4; JMP
;   CMP BX,30 / JL; OR AX,8
;   MOV BX,[g_nJoyDirScratchY]
;   CMP BX,-30 / JGE; OR AX,1; JMP
;   CMP BX,30 / JL; OR AX,2
; ret0:
;   POP BP / RETF
; ============================================================================

_joystick_read_direction	proc far
	push	bp
	mov	bp,sp
	mov	ax,word ptr [bp+6h]		; which
	or	ax,ax
	jz	L_25a5
	mov	al,[_g_bJoystick1Installed]
	jmp	L_25a8
L_25a5:
	mov	al,[_g_bJoystick0Installed]
L_25a8:
	or	al,al
	jz	L_25ed				; not installed -> return 0 (AL=0)
	mov	ax,offset _g_nJoyDirScratchY
	push	ax
	mov	ax,offset _g_nJoyDirScratchX
	push	ax
	mov	ax,word ptr [bp+6h]		; which
	push	ax
	push	cs
	call	near ptr _joystick_read_position	; near call (PUSH CS sets up RETF)
	add	sp,6
	xor	ax,ax
	mov	bx,word ptr [_g_nJoyDirScratchX]
	cmp	bx,-1eh				; -30
	jge	L_25cf
	or	ax,4
	jmp	L_25d7
L_25cf:
	cmp	bx,1eh				; +30
	jl	L_25d7
	or	ax,8
L_25d7:
	mov	bx,word ptr [_g_nJoyDirScratchY]
	cmp	bx,-1eh
	jge	L_25e5
	or	ax,1
	jmp	L_25ed
L_25e5:
	cmp	bx,1eh
	jl	L_25ed
	or	ax,2
L_25ed:
	pop	bp
	retf
_joystick_read_direction	endp

; ============================================================================
; joystick_button_pressed @ 180c:25ef (linear 0x1a6af, 26 bytes)
;
; Equivalent C:
;
;   int joystick_button_pressed(int button) {
;       unsigned char bVar1 = inportb(0x201);
;       return (unsigned int)((bVar1 >> (((unsigned char)button & 3) + 4) & 1) ^ 1);
;   }
;
; The original uses a byte-width "SHR AL,CL" variable-count shift on AL.
;
; Disassembly (180c:25ef):
;   PUSH  BP
;   MOV   BP,SP
;   MOV   CX,word ptr [BP+0x6]  ; button (int)
;   AND   CX,0x3                 ; button & 3
;   MOV   DX,0x201
;   IN    AL,DX                  ; bVar1 = inportb(0x201)
;   ADD   CL,0x4                 ; shift = (button & 3) + 4
;   SHR   AL,CL                  ; byte-width shift on AL
;   AND   AL,0x1
;   XOR   AH,AH
;   XOR   AL,0x1
;   POP   BP
;   RETF
; ============================================================================

; int joystick_button_pressed(int button)
_joystick_button_pressed	proc far
	push	bp
	mov	bp,sp
	mov	cx,word ptr [bp+6]	; button
	and	cx,3
	mov	dx,0201h
	in	al,dx			; bVar1 = inportb(0x201)
	add	cl,4			; shift = (button & 3) + 4
	shr	al,cl			; byte-width shift
	and	al,1
	xor	ah,ah
	xor	al,1
	pop	bp
	retf
_joystick_button_pressed	endp

; ============================================================================
; joystick_poll_axis @ 180c:2609 (linear 0x1a6c9, 48 bytes)
;
; Polls one gameport axis-pair and normalizes the selected sample.
;
;   IN : [BP+6] = axis index
;   Builds BX = 1 << axis (the gameport port bit), calls gameport_read_axis
;   (X count -> DI, Y count -> SI). For an odd axis it selects the X count
;   (MOV SI,DI); for an even axis it keeps the Y count already in SI. It then
;   indexes the per-axis center (g_nJoy0CenterX[]) and sensitivity
;   (g_nJoy0SensX[]) tables by axis*2 into BX/CX, puts the chosen raw sample
;   in AX, and calls joystick_normalize_axis to map it to a logical position.
;
; Glues two register-IN/OUT helpers (gameport_read_axis,
; joystick_normalize_axis) that take and return their arguments in registers,
; with no stack ABI. Ends with an STI (re-enabling interrupts the reader's CLI
; critical section left disabled).
;
; Disassembly (180c:2609, linear 0x1a6c9, 48 bytes):
;   PUSH BP
;   MOV  BP,SP
;   PUSH SI
;   PUSH DI
;   MOV  BX,1
;   MOV  CX,[BP+6]            ; axis
;   SHL  BX,CL               ; BX = 1 << axis
;   CALL gameport_read_axis  ; near; X count -> DI, Y count -> SI
;   MOV  CX,[BP+6]
;   TEST CL,1
;   JZ   L_a6e3              ; even axis: keep Y count in SI
;   MOV  SI,DI              ; odd axis: select X count
; L_a6e3:
;   MOV  DI,CX
;   SHL  DI,1               ; DI = axis * 2
;   MOV  BX,[DI+g_nJoy0CenterX]
;   MOV  CX,[DI+g_nJoy0SensX]
;   MOV  AX,SI
;   CALL joystick_normalize_axis ; near; (AX,BX,CX) in
;   STI
;   POP  DI
;   POP  SI
;   POP  BP
;   RETF
; ============================================================================

_joystick_poll_axis	proc far
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	bx,1h
	mov	cx,word ptr [bp+6h]
	shl	bx,cl
	call	_gameport_read_axis
	mov	cx,word ptr [bp+6h]
	test	cl,1h
	jz	L_a6e3
	mov	si,di
L_a6e3:
	mov	di,cx
	shl	di,1h
	mov	bx,word ptr [di+_g_nJoy0CenterX]
	mov	cx,word ptr [di+_g_nJoy0SensX]
	mov	ax,si
	call	_joystick_normalize_axis
	sti
	pop	di
	pop	si
	pop	bp
	retf
_joystick_poll_axis	endp

S180C_TEXT	ends
	end
