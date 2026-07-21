;; LZW.ASM -- the hand-written LZW decode module.
;; Members: lzw_decompress + lzw_decode_step + lzw_get_next_code.
;;
;; lzw_decode_step:
;;
;; One step of the LZW decode loop. Pulls a code from the bit-stream,
;; expands the LZW dictionary entry back into the codec output buffer,
;; and handles:
;;   - The initial "need seed code" path (g_bLzwNeedSeedCode)
;;   - The suspended-output resume path (g_bLzwOutputSuspended)
;;   - RESET codes (0x100) that reinitialize the dictionary
;;   - The 10-unrolled backward-walk loop building the decoded byte sequence
;;   - The emit loop (g_bCurStreamOpMode bit 0x40 = read vs seek mode)
;;   - The chunk-boundary suspend that saves state and increments ring-buf
;;
;; Near/far: ends in RET (C3), so proc near.
;; All callees are in seg 180c (same segment) -> near calls.
;; DGROUP globals -> extrn; callees -> extrn near (same-segment).

	.286

	; --- DGROUP global references ---
	extrn	_g_pCurCodecScratch:dword	; DGROUP+0x5eea (uchar far *)  4B
	extrn	_g_bLzwOutputSuspended:byte	; DGROUP+0x5efa (uchar)        1B
	extrn	_g_bLzwNeedSeedCode:byte	; DGROUP+0x5efb (uchar)        1B
	extrn	_g_wCodecBytesRemaining:word	; DGROUP+0x5e1e (ushort)       2B
	extrn	_g_pStreamReadDst:dword		; DGROUP+0x5eee (uchar far *)  4B
	extrn	_g_bCurStreamOpMode:byte	; DGROUP+0x5e1d (uchar)        1B
	extrn	_g_wLzwPrevCode:word		; DGROUP+0x5f06 (ushort)       2B
	extrn	_g_wLzwNewCode:word		; DGROUP+0x5f04 (ushort)       2B
	extrn	_g_wLzwLastByte:word		; DGROUP+0x5f08 (ushort)       2B
	extrn	_g_wLzwNextCode:word		; DGROUP+0x5f0c (ushort)       2B
	extrn	_g_wLzwResetWidthPending:word	; DGROUP+0x5f0a (ushort)       2B
	extrn	_g_pCurStreamDesc:word		; DGROUP+0x5ef7 (uchar *)      2B
	extrn	_g_pCurStreamRingBuf:word	; DGROUP+0x5ef5 (uchar *)      2B

	extrn	_g_wLzwMaxCode:word		; DGROUP+0x5f0e (ushort)
	extrn	_g_wLzwInBitPos:word		; DGROUP+0x5efe (ushort)
	extrn	_g_wLzwInBufBitsTotal:word	; DGROUP+0x5efc (ushort)
	extrn	_g_wLzwCodeBits:word		; DGROUP+0x5f10 (ushort)

	; --- near callees (same segment 180c) ---
	extrn	_codec_emit_byte:near		; 180c:6112 (called by lzw_decompress)
	extrn	_codec_raw_block_read:near	; 180c:5f15 (called by lzw_get_next_code)

	; --- the module's own LZW decode-side _DATA, DGROUP 0x3214..0x322a ---
	_DATA	segment word public 'DATA'
	public	_g_lzwBitBuf
	public	_g_lzwExtractMask
	public	_g_pLzwEmitPos
_g_lzwBitBuf		db 12 dup (0ch)		; DGROUP+0x3214 (12B) per-code bit-width table
_g_lzwExtractMask	db 00h,01h,03h,07h,0fh,1fh,3fh,7fh,0ffh	; DGROUP+0x3220 (9B) right-fill mask ramp
_g_pLzwEmitPos		dw 0			; DGROUP+0x3229 (2B) uchar * (runtime-written)
	_DATA	ends
	_BSS	segment word public 'BSS'
	_BSS	ends
	DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_lzw_decompress
	public	_lzw_decode_step
	public	_lzw_get_next_code

;; lzw_decompress -- the LZW decode ENTRY.
;; One routine with lzw_decode_step: this seeds the first code, then falls
;; through (JMP) into lzw_decode_step's body at L_65ca; lzw_decode_step in turn
;; JNZ-branches back here. Both live in one module so the intra-routine
;; transfers resolve at assemble time. codec_emit_byte is a same-segment extrn
;; near call; lzw_get_next_code is intra-module.
_lzw_decompress	proc near
	mov	byte ptr [_g_bLzwNeedSeedCode], 0
	mov	bp, es
	call	_lzw_get_next_code
	mov	word ptr [_g_wLzwPrevCode], ax
	mov	word ptr [_g_wLzwLastByte], ax
	push	ax
	call	_codec_emit_byte
	add	sp, 2
	mov	es, bp
	jmp	short L_65ca		; falls into lzw_decode_step body
_lzw_decompress	endp

	; Inter-proc pad byte (NOP). The lzw_decode_step public is the PUSH BP below.
	nop

_lzw_decode_step	proc near
	push	bp
	push	si
	push	di
	mov	ax, word ptr [_g_pCurCodecScratch+2]	; segment half of far ptr
	add	ax, 0372h		; 372h huge-ptr seg normalize (0x372<<4=scratch+0x3720), not DGROUP
	mov	es, ax
	cmp	byte ptr [_g_bLzwOutputSuspended], 0h
	jz	L_65c3			; if not suspended -> check NeedSeedCode
	mov	cx, word ptr [_g_wCodecBytesRemaining]
	inc	cx
	mov	bp, es
	les	di, [_g_pStreamReadDst]
	mov	al, [_g_bCurStreamOpMode]
	mov	si, word ptr [_g_pLzwEmitPos]
	mov	byte ptr [_g_bLzwOutputSuspended], 0h
	mov	dx, ds
	mov	ds, bp
	mov	bx, 2h
	test	al, 40h
	jz	L_65c0
	jmp	L_66c7
L_65c0:
	jmp	L_671a
L_65c3:
	cmp	byte ptr [_g_bLzwNeedSeedCode], 0h
	jnz	_lzw_decompress
L_65ca:
	mov	bp, es
	call	_lzw_get_next_code
	mov	es, bp
	cmp	ax, 0h
	jl	L_65fb
	cmp	ax, 0100h		; 100h LZW RESET sentinel, scalar cmp
	jnz	L_65ff
	; --- RESET CODE 0x100 path ---
	mov	bp, es
	les	di, [_g_pCurCodecScratch]	; loads ES:DI from far ptr
	mov	ax, di
	mov	cx, 0100h		; 100h rep stosw count: 256 dict entries
	rep	stosw			; fill 0x100 words in ES:[DI] with AX
	inc	ax
	mov	[_g_wLzwResetWidthPending], ax
	xchg	ah, al
	mov	[_g_wLzwNextCode], ax
	call	_lzw_get_next_code
	mov	es, bp
	cmp	ax, 0h
	jge	L_65ff
L_65fb:
	pop	di
	pop	si
	pop	bp
	ret
L_65ff:
	sub	di, di
	mov	si, ax
	mov	[_g_wLzwNewCode], ax
	cmp	ax, word ptr [_g_wLzwNextCode]
	jl	L_6614
	; if new_code >= next_code: self-referring code - emit last_byte first
	mov	ax, [_g_wLzwLastByte]
	stosb				; store AL in ES:[DI], increment DI
	mov	si, word ptr [_g_wLzwPrevCode]
L_6614:
	mov	dx, ds			; save current DS
	mov	ax, word ptr [_g_pCurCodecScratch+2]	; segment half
	mov	ds, ax			; DS = codec scratch segment
	mov	cx, 0100h		; 100h literal-code boundary, SI<0x100 ends walk
	mov	bx, 2720h		; 2720h suffix-table off in scratch seg DS
	; --- backward walk loop: unroll 10 iterations then loop ---
L_6621:
	cmp	si, cx
	jl	L_669c			; if SI < 0x100, done with backward walk
	mov	al, byte ptr [bx+si]	; suffix char from suffix table
	stosb
	shl	si, 1h
	mov	si, word ptr [si]	; prefix[SI] lookup
	cmp	si, cx
	jl	L_669c
	mov	al, byte ptr [bx+si]
	stosb
	shl	si, 1h
	mov	si, word ptr [si]
	cmp	si, cx
	jl	L_669c
	mov	al, byte ptr [bx+si]
	stosb
	shl	si, 1h
	mov	si, word ptr [si]
	cmp	si, cx
	jl	L_669c
	mov	al, byte ptr [bx+si]
	stosb
	shl	si, 1h
	mov	si, word ptr [si]
	cmp	si, cx
	jl	L_669c
	mov	al, byte ptr [bx+si]
	stosb
	shl	si, 1h
	mov	si, word ptr [si]
	cmp	si, cx
	jl	L_669c
	mov	al, byte ptr [bx+si]
	stosb
	shl	si, 1h
	mov	si, word ptr [si]
	cmp	si, cx
	jl	L_669c
	mov	al, byte ptr [bx+si]
	stosb
	shl	si, 1h
	mov	si, word ptr [si]
	cmp	si, cx
	jl	L_669c
	mov	al, byte ptr [bx+si]
	stosb
	shl	si, 1h
	mov	si, word ptr [si]
	cmp	si, cx
	jl	L_669c
	mov	al, byte ptr [bx+si]
	stosb
	shl	si, 1h
	mov	si, word ptr [si]
	cmp	si, cx
	jl	L_669c
	mov	al, byte ptr [bx+si]
	stosb
	shl	si, 1h
	mov	si, word ptr [si]
	cmp	si, cx
	jl	L_669c
	mov	al, byte ptr [bx+si]
	stosb
	shl	si, 1h
	mov	si, word ptr [si]
	jmp	L_6621
L_669c:
	mov	al, byte ptr [bx+si]	; final entry < 0x100
	stosb				; store final byte
	mov	ds, dx			; restore DS
	mov	ah, 0h
	mov	[_g_wLzwLastByte], ax
	mov	cx, word ptr [_g_wCodecBytesRemaining]
	inc	cx
	mov	si, di
	dec	si
	mov	bp, es
	les	di, [_g_pStreamReadDst]
	mov	al, [_g_bCurStreamOpMode]
	mov	dx, ds
	mov	ds, bp
	mov	bx, 2h
	test	al, 40h
	jz	L_6715
	; --- emit loop: read mode (bit 0x40 set), emit from backward-walk buffer ---
L_66c2:
	lodsb				; DS:SI -> AL, SI++
	dec	cx
	jz	L_6720			; if count exhausted -> chunk boundary
	stosb				; store to ES:[DI]
L_66c7:
	sub	si, bx			; SI -= 2, step back 2 in the buffer
	jl	L_6749			; if SI < 0 -> emit loop done, update table
	lodsb
	dec	cx
	jz	L_6720
	stosb
	sub	si, bx
	jl	L_6749
	lodsb
	dec	cx
	jz	L_6720
	stosb
	sub	si, bx
	jl	L_6749
	lodsb
	dec	cx
	jz	L_6720
	stosb
	sub	si, bx
	jl	L_6749
	lodsb
	dec	cx
	jz	L_6720
	stosb
	sub	si, bx
	jl	L_6749
	lodsb
	dec	cx
	jz	L_6720
	stosb
	sub	si, bx
	jl	L_6749
	lodsb
	dec	cx
	jz	L_6720
	stosb
	sub	si, bx
	jl	L_6749
	lodsb
	dec	cx
	jz	L_6720
	stosb
	sub	si, bx
	jl	L_6749
	lodsb
	dec	cx
	jz	L_6720
	stosb
	sub	si, bx
	jl	L_6749
	jmp	L_66c2
L_6715:
	lodsb				; seek mode: no STOSB, just advance
	dec	cx
	jz	L_6720
	inc	di
L_671a:
	sub	si, bx
	jl	L_6749
	jmp	L_6715
L_6720:
	mov	ds, dx			; chunk boundary hit: save state
	mov	word ptr [_g_pStreamReadDst], di
	mov	word ptr [_g_pLzwEmitPos], si
	mov	si, word ptr [_g_pCurStreamDesc]
	mov	bl, byte ptr [si+1ah]
	inc	word ptr [si+1ah]
	sub	bh, bh
	mov	si, word ptr [_g_pCurStreamRingBuf]
	mov	byte ptr [bx+si], al
	sub	ax, ax
	mov	[_g_wCodecBytesRemaining], ax
	inc	ax
	mov	byte ptr [_g_bLzwOutputSuspended], al
	pop	di
	pop	si
	pop	bp
	ret
	; --- update dictionary table path ---
L_6749:
	mov	ax, ds
	mov	es, ax
	mov	ds, dx			; restore DS to DGROUP
	dec	cx
	mov	word ptr [_g_wCodecBytesRemaining], cx
	mov	word ptr [_g_pStreamReadDst], di
	mov	ax, [_g_wLzwNextCode]
	cmp	ax, 1000h		; 1000h max dict size 4096, scalar cmp
	jge	L_6783			; if NextCode >= 0x1000 -> skip table update
	mov	di, ax
	shl	di, 1h
	mov	ax, [_g_wLzwPrevCode]
	mov	bx, es
	mov	bp, es
	sub	bx, 0372h		; 372h huge-ptr seg normalize (scratch seg - 0x372), not DGROUP
	mov	es, bx
	stosw				; store AX = g_wLzwPrevCode into ES:[DI]
	shr	di, 1h
	mov	ax, di
	mov	[_g_wLzwNextCode], ax
	add	di, 271fh		; 271fh suffix-table off in scratch seg ES (=scratch+0x2720 off-by-1)
	mov	ax, [_g_wLzwLastByte]
	stosb				; store suffix byte into suffix table
	mov	es, bp
L_6783:
	mov	ax, [_g_wLzwNewCode]
	mov	[_g_wLzwPrevCode], ax
	jmp	L_65ca
_lzw_decode_step	endp

;; lzw_get_next_code
;;
;; Variable-width LZW code reader. Reads the next LZW code from a bit-cursor
;; over a byte buffer refilled via codec_raw_block_read. The code width grows
;; from 9 up to 12 bits as the dictionary fills. Returns the next code, or
;; 0xFFFF on buffer-read failure.
;;
;; The variable shifts are word-width (`d3 e8` SHR AX,CL / `d3 e0` SHL AX,CL).
;; The inner bit-extraction path (L_67a5) is a LODSB-driven pointer walk over
;; g_lzwBitBuf plus 8-bit register arithmetic on CH (bit offset: `AND CH,7`,
;; `SUB CH,8`, `NEG CH`) and BL (bits remaining: `SUB BL,CH`, `CMP BL,8`),
;; ending in a g_lzwExtractMask[BL] table lookup.
;; DGROUP globals -> extrn by name; codec_raw_block_read -> near call.
;;
;; Near/far convention: this function ends in RET (C3), so proc near.
;; codec_raw_block_read is also in seg 180c -> near call.
_lzw_get_next_code	proc near
	mov ax, [_g_wLzwNextCode]
	cmp ax, word ptr [_g_wLzwMaxCode]
	jg L_67ef			; if NextCode > MaxCode -> widen
	cmp word ptr [_g_wLzwResetWidthPending], 0h
	jnz L_6810			; if reset pending -> do reset
	mov ax, [_g_wLzwInBitPos]
	cmp ax, word ptr [_g_wLzwInBufBitsTotal]
	jge L_6822			; if bit cursor >= bits in buf -> refill

	; --- inner bit-extraction path (L_67a5) ---
L_67a5:
	mov si, offset _g_lzwBitBuf
	mov bx, word ptr [_g_wLzwCodeBits]
	mov ch, al			; CH = low byte of g_wLzwInBitPos
	mov dx, ax			; DX = g_wLzwInBitPos
	add ax, bx			; AX = InBitPos + CodeBits = new InBitPos
	mov [_g_wLzwInBitPos], ax
	shr dx, 1h			; DX = InBitPos >> 1
	shr dx, 1h			; DX = InBitPos >> 2
	shr dx, 1h			; DX = InBitPos >> 3 = byte index
	add si, dx			; SI = &g_lzwBitBuf[byte_idx]
	and ch, 7h			; CH = bit offset within byte
	lodsb				; AL = g_lzwBitBuf[byte_idx], SI++
	mov cl, ch			; CL = bit offset
	shr ax, cl			; shift right by bit offset
	mov dx, ax			; save partial result
	sub ch, 8h			; CH = bit_offset - 8, usually negative
	neg ch				; CH = 8 - bit_offset = bits remaining in byte
	sub bl, ch			; BL = CodeBits - (8 - bit_offset)
	cmp bl, 8h			; enough bits left for another full byte?
	jl L_67e0			; if BL < 8, skip the second LODSB
	lodsb				; AL = next byte, SI++
	mov cl, ch
	shl ax, cl			; shift left by CH = bits remaining
	or dx, ax			; merge into partial result
	add ch, 8h
	sub bl, 8h
L_67e0:
	sub ax, ax			; AX = 0
	; BX = remaining bits = mask index into g_lzwExtractMask
	mov al, byte ptr [bx + _g_lzwExtractMask]
	and al, byte ptr [si]		; mask the last partial byte at SI
	mov cl, ch
	shl ax, cl			; shift masked byte into position
	or ax, dx			; combine with earlier bits
	ret				; return the assembled code

	; --- code-width widening path (jumped to if NextCode > MaxCode) ---
L_67ef:
	mov cx, word ptr [_g_wLzwCodeBits]
	inc cx
	mov word ptr [_g_wLzwCodeBits], cx
	mov ax, 1000h		; 01000h 12-bit MaxCode ceiling -> g_wLzwMaxCode
	cmp cl, 0ch			; if CodeBits == 12, keep 0x1000
	jz L_6806
	mov ax, 1h
	shl ax, cl			; AX = 1 << CodeBits
	dec ax				; AX = (1 << CodeBits) - 1 = new MaxCode
L_6806:
	mov [_g_wLzwMaxCode], ax
	cmp word ptr [_g_wLzwResetWidthPending], 0h
	jz L_6822			; if no reset pending -> refill buffer

	; --- reset code-width path ---
L_6810:
	mov ax, 9h
	mov [_g_wLzwCodeBits], ax
	mov ax, 1ffh		; 01ffh 9-bit MaxCode 2^9-1 -> g_wLzwMaxCode
	mov [_g_wLzwMaxCode], ax
	mov word ptr [_g_wLzwResetWidthPending], 0h

	; --- buffer refill path ---
L_6822:
	mov si, word ptr [_g_wLzwCodeBits]	; arg: bits per code
	push si
	mov ax, offset _g_lzwBitBuf	; arg: dest buffer
	push ax
	call _codec_raw_block_read
	add sp, 4h			; cdecl cleanup: 2 args * 2 bytes each
	sub bx, bx			; BX = 0
	cmp ax, bx			; AX = bytes read; 0 or negative = failure
	jle L_684c			; if AX <= 0 -> return 0xffff error
	mov word ptr [_g_wLzwInBitPos], bx	; reset bit cursor to 0
	shl ax, 1h			; AX = bytes_read * 2
	shl ax, 1h			; AX = bytes_read * 4
	shl ax, 1h			; AX = bytes_read * 8 = total bits
	dec si				; SI = CodeBits - 1
	sub ax, si			; AX = bits_total - (CodeBits-1) = usable bits
	mov [_g_wLzwInBufBitsTotal], ax
	mov ax, bx			; AX = 0 = starting InBitPos
	jmp L_67a5			; go extract the first code

	; --- error / end-of-stream path ---
L_684c:
	mov [_g_wLzwInBufBitsTotal], ax	; store 0 or negative
	mov ax, 0ffffh			; return sentinel: EOF/error
	ret
_lzw_get_next_code	endp

S180C_TEXT	ends
	end
