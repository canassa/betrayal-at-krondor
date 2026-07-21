;; BLITRLE.ASM -- KRONDOR.EXE RLE-sprite scanline decoder (segment 180c).
;; Single member: blit_rle_sprite (180c:6853, linear 0x1e913, 243 bytes).
;;
; Decodes one scanline of an RLE-compressed sprite from the stream source cursor
; (g_pCurStreamSrcCursor) into the screen buffer at g_pRleScanlineDst.
; Stream is byte-RLE: high bit set = fill run (repeat pixel), high bit clear = literal run.
; The 0x40 flag in g_bCurStreamOpMode selects a normal (word-aligned STOS) decode path.
;
; A LODSB/STOSB RLE blitter sitting between C codec functions in this segment.
; Built from x86 string primitives with explicit ES:DI / DS:SI conventions:
;   - LODSB/STOSB/MOVSB with explicit ES:DI / DS:SI conventions
;   - REP STOSW / REP MOVSW / REP STOSB / REP MOVSB compound string ops
;   - SHL/SHR by 1 on AL (byte) then MOV CL,AL (byte-width var shift pattern)
;   - SS-segment-override MOV SS:[g_pStreamReadDst] and MOV DI,SS:[g_pRleScanlineDst]
;     used after ES is reloaded from SS (the SS: prefix forces DGROUP access when ES != DS)
;   - TEST DI, imm16 form (f7 c7 01 00) for odd-address detection
;   - Near RET (near proc, intra-segment call convention for seg-180c)
;
; Branch targets -> intra-module labels; DGROUP globals -> extrn.
;
; Disassembly (180c:6853, linear 0x1e913, 243 bytes):
;   off  0: 55 56 57                PUSH BP; PUSH SI; PUSH DI
;   off  3: 2b c9                   SUB CX,CX
;   off  5: 8b d9                   MOV BX,CX
;   off  7: 8b 36 f7 5e             MOV SI,[g_pCurStreamDesc]
;   off 11: 8a 4c 1a                MOV CL,[SI+1ah]
;   off 14: a1 f5 5e                MOV AX,[g_pCurStreamRingBuf]
;   off 17: 03 c1                   ADD AX,CX
;   off 19: a3 2c 32                MOV [g_pRleScanlineDst],AX
;   off 22: 8b 44 0e                MOV AX,[SI+0eh]
;   off 25: 8b 54 10                MOV DX,[SI+10h]
;   off 28: 2b 44 0a                SUB AX,[SI+0ah]
;   off 31: 1b 54 0c                SBB DX,[SI+0ch]
;   off 34: bd ff ff                MOV BP,0ffffh
;   off 37: 75 02                   JNZ L_687c
;   off 39: 8b e8                   MOV BP,AX
;   off 41: c4 3e ee 5e             LES DI,[g_pStreamReadDst]
;   off 45: 8b 16 1e 5e             MOV DX,[g_wCodecBytesRemaining]
;   off 49: a0 1d 5e                MOV AL,[g_bCurStreamOpMode]
;   off 52: c5 36 18 5e             LDS SI,[g_pCurStreamSrcCursor]
;   off 56: a8 40                   TEST AL,40h
;   off 58: 74 4d                   JZ L_68dc
;  [normal (fill+literal) path: 0x40 flag set]
;   off 60: 2b c9                   SUB CX,CX
;   off 62: 3b dd                   CMP BX,BP
;   off 64: 74 42                   JZ L_68d7
;   off 66: ac                      LODSB
;   off 67: d0 e0                   SHL AL,1
;   off 69: 73 20                   JNC L_68ba
;   off 71: d0 e8                   SHR AL,1
;   off 73: 8a c8                   MOV CL,AL
;   off 75: ac                      LODSB
;   off 76: 83 c3 02                ADD BX,2
;   off 79: 2b d1                   SUB DX,CX
;   off 81: 72 4d                   JC L_68f3
;   off 83: 8a e0                   MOV AH,AL
;   off 85: f7 c7 01 00             TEST DI,1        (word form, imm16=1)
;   off 89: 74 02                   JZ L_68b0
;   off 91: aa                      STOSB
;   off 92: 49                      DEC CX
;   off 93: d1 e9                   SHR CX,1
;   off 95: f3 ab                   REP STOSW
;   off 97: d1 d1                   RCL CX,1
;   off 99: f3 aa                   REP STOSB
;   off101: eb d5                   JMP L_688f
;   off103: d0 e8                   SHR AL,1       (literal run path)
;   off105: 8a c8                   MOV CL,AL
;   off107: 03 d9                   ADD BX,CX
;   off109: 43                      INC BX
;   off110: 2b d1                   SUB DX,CX
;   off112: 72 6b                   JC L_6930
;   off114: f7 c7 01 00             TEST DI,1        (word form, imm16=1)
;   off118: 74 02                   JZ L_68cd
;   off120: a4                      MOVSB
;   off121: 49                      DEC CX
;   off122: d1 e9                   SHR CX,1
;   off124: f3 a5                   REP MOVSW
;   off126: d1 d1                   RCL CX,1
;   off128: f3 a4                   REP MOVSB
;   off130: eb b8                   JMP L_688f
;   off132: 8b e9                   MOV BP,CX      (L_68d7)
;   off134: eb 2c                   JMP L_6907
;   off136: 90                      NOP
;  [flip path: 0x40 flag clear]
;   off137: 2b c9                   SUB CX,CX
;   off139: 3b dd                   CMP BX,BP
;   off141: 74 f5                   JZ L_68d7
;   off143: ac                      LODSB
;   off144: d0 e0                   SHL AL,1
;   off146: 73 3c                   JNC L_6923
;   off148: d0 e8                   SHR AL,1
;   off150: 8a c8                   MOV CL,AL
;   off152: ac                      LODSB
;   off153: 83 c3 02                ADD BX,2
;   off156: 2b d1                   SUB DX,CX
;   off158: 73 e9                   JNC L_68dc
;   off160: 03 d1                   ADD DX,CX      (L_68f3 for flip path)
;   off162: 8c d5                   MOV BP,SS
;   off164: 8e c5                   MOV ES,BP
;   off166: 36 89 3e ee 5e          MOV word ptr SS:[_g_pStreamReadDst],DI
;   off171: 36 8b 3e 2c 32          MOV DI,word ptr SS:[_g_pRleScanlineDst]
;   off176: 8b e9                   MOV BP,CX
;   off178: f3 aa                   REP STOSB
;   off180: 8c d0                   MOV AX,SS
;   off182: 8e d8                   MOV DS,AX
;   off184: 8b 36 f7 5e             MOV SI,[_g_pCurStreamDesc]
;   off188: 8b c5                   MOV AX,BP
;   off190: 00 44 1a                ADD [SI+1ah],AL
;   off193: 89 16 1e 5e             MOV [_g_wCodecBytesRemaining],DX
;   off197: 01 5c 0a                ADD [SI+0ah],BX
;   off200: 83 54 0c 00             ADC word ptr [SI+0ch],0
;   off204: 5f 5e 5d                POP DI; POP SI; POP BP
;   off207: c3                      RET
;   off208: d0 e8                   SHR AL,1       (L_6923, literal no-clip)
;   off210: 8a c8                   MOV CL,AL
;   off212: 03 d9                   ADD BX,CX
;   off214: 43                      INC BX
;   off215: 03 f1                   ADD SI,CX
;   off217: 2b d1                   SUB DX,CX
;   off219: 73 ac                   JNC L_68dc
;   off221: 03 d1                   ADD DX,CX      (L_6930)
;   off223: 8c d5                   MOV BP,SS
;   off225: 8e c5                   MOV ES,BP
;   off227: 36 89 3e ee 5e          MOV word ptr SS:[_g_pStreamReadDst],DI
;   off232: 36 8b 3e 2c 32          MOV DI,word ptr SS:[_g_pRleScanlineDst]
;   off237: 8b e9                   MOV BP,CX
;   off239: f3 a4                   REP MOVSB
;   off241: eb c1                   JMP L_6907

	.286

	; DGROUP globals
	extrn	_g_pCurStreamDesc:word		; DGROUP+0x5ef7 (2B) uchar *
	extrn	_g_pCurStreamRingBuf:word	; DGROUP+0x5ef5 (2B) uchar *
	extrn	_g_pStreamReadDst:dword	; DGROUP+0x5eee (4B) uchar far *
	extrn	_g_wCodecBytesRemaining:word	; DGROUP+0x5e1e (2B) ushort
	extrn	_g_bCurStreamOpMode:byte	; DGROUP+0x5e1d (1B) uchar
	extrn	_g_pCurStreamSrcCursor:dword	; DGROUP+0x5e18 (4B) uchar far *

	; medium-model group: DGROUP resolves DS-relative extrns
	; --- the module's own _DATA, DGROUP 0x322c ---
_DATA	segment word public 'DATA'
	public	_g_pRleScanlineDst
_g_pRleScanlineDst	dw 0		; DGROUP+0x322c (2B) uchar * (runtime-written)
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_blit_rle_sprite

; int blit_rle_sprite(void)  -- near (RET), no args, 243 bytes
; Returns the pending-count (AX = BP via the shared L_6907 epilogue); the
; sole caller codec_rle_read forwards it as its own return value.
_blit_rle_sprite	proc near
	push	bp
	push	si
	push	di
	sub	cx,cx
	mov	bx,cx
	mov	si,word ptr [_g_pCurStreamDesc]
	mov	cl,byte ptr [si+1ah]
	mov	ax,[_g_pCurStreamRingBuf]
	add	ax,cx
	mov	[_g_pRleScanlineDst],ax
	mov	ax,word ptr [si+0eh]
	mov	dx,word ptr [si+10h]
	sub	ax,word ptr [si+0ah]
	sbb	dx,word ptr [si+0ch]
	mov	bp,0ffffh
	jnz	L_687c
	mov	bp,ax
L_687c:
	les	di,[_g_pStreamReadDst]
	mov	dx,[_g_wCodecBytesRemaining]
	mov	al,[_g_bCurStreamOpMode]
	lds	si,[_g_pCurStreamSrcCursor]
	test	al,40h
	jz	L_68dc
	; --- 0x40 path: normal (fill+copy) decode ---
L_688f:
	sub	cx,cx
	cmp	bx,bp
	jz	L_68d7
	lodsb
	shl	al,1
	jnc	L_68ba
	; fill run: high bit was set -> count in CL, fill pixel in AL
	shr	al,1
	mov	cl,al
	lodsb
	add	bx,2
	sub	dx,cx
	jc	L_68f3
	mov	ah,al
	test	di,1			; db 0f7h,0c7h,001h,000h -- word-form TEST DI,imm16
	jz	L_68b0
	stosb
	dec	cx
L_68b0:
	shr	cx,1
	rep	stosw
	rcl	cx,1
	rep	stosb
	jmp	short L_688f
	; literal run: high bit was clear -> count in CL, copy pixels from SI
L_68ba:
	shr	al,1
	mov	cl,al
	add	bx,cx
	inc	bx
	sub	dx,cx
	jc	L_6930
	test	di,1			; db 0f7h,0c7h,001h,000h -- word-form TEST DI,imm16
	jz	L_68cd
	movsb
	dec	cx
L_68cd:
	shr	cx,1
	rep	movsw
	rcl	cx,1
	rep	movsb
	jmp	short L_688f
	; end of scanline (BX==BP)
L_68d7:
	mov	bp,cx
	jmp	short L_6907
	nop				; 90 -- padding between the two paths
	; --- 0x40 flag clear path: flip decode ---
L_68dc:
	sub	cx,cx
	cmp	bx,bp
	jz	L_68d7
	lodsb
	shl	al,1
	jnc	L_6923
	; fill run (flip path)
	shr	al,1
	mov	cl,al
	lodsb
	add	bx,2
	sub	dx,cx
	jnc	L_68dc
	; --- clipped fill: write partial run to scanline buffer ---
	; L_68f3: also jumped to from normal path JC at off=81 (fill overflow in 0x40 path)
L_68f3:
	add	dx,cx
	mov	bp,ss
	mov	es,bp
	mov	word ptr ss:[_g_pStreamReadDst],di	; SS: override (ES already changed)
	mov	di,word ptr ss:[_g_pRleScanlineDst]	; SS: override
	mov	bp,cx
	rep	stosb
	; --- epilogue ---
L_6907:
	mov	ax,ss
	mov	ds,ax
	mov	si,word ptr [_g_pCurStreamDesc]
	mov	ax,bp
	add	byte ptr [si+1ah],al
	mov	[_g_wCodecBytesRemaining],dx
	add	word ptr [si+0ah],bx
	adc	word ptr [si+0ch],0
	pop	di
	pop	si
	pop	bp
	ret
	; literal run (flip path): skip pixels in src, advance BX
L_6923:
	shr	al,1
	mov	cl,al
	add	bx,cx
	inc	bx
	add	si,cx
	sub	dx,cx
	jnc	L_68dc
	; --- clipped literal: copy partial run to scanline buffer ---
L_6930:
	add	dx,cx
	mov	bp,ss
	mov	es,bp
	mov	word ptr ss:[_g_pStreamReadDst],di	; SS: override (ES already changed)
	mov	di,word ptr ss:[_g_pRleScanlineDst]	; SS: override
	mov	bp,cx
	rep	movsb
	jmp	short L_6907

_blit_rle_sprite	endp

S180C_TEXT	ends

	end
