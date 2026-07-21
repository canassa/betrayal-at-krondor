;; DECOMP.ASM -- the decompression module (segment 149f, 370 bytes).
;;
;; One hand-written TASM translation unit holding the game's two asset codecs
;; and their shared disk-refill pump.  These functions were authored in
;; assembly in 1992: the pump borrows its callers' stack frame and returns its
;; results in registers (SI, CX), and the codecs drive LODSB/MOVSW/STOSB/LOOP
;; and ES:SI->ES:DI string copies directly -- none of which C can express.
;;
;;   decomp_stream_refill  (149f:0002) - file-scope input-buffer pump (static;
;;                          called only by its two siblings via PUSH CS/CALL near)
;;   decomp_lzss           (149f:0030) - LZSS decompressor  (public; CALLF from
;;                          resblit_load_asset_table)
;;   decomp_rle            (149f:010a) - byte-RLE decompressor (public; ditto)
;;
;; Shared caller frame borrowed by decomp_stream_refill ([BP+N] of the codec):
;;   [BP+06h] = dst (4-byte far pointer)   [BP+0eh] = buf_size
;;   [BP+0ah] = remaining (dec'd in place) [BP+10h] = bakfile (FILE *)
;;   [BP+0ch] = buf_ptr (reloaded into SI)
;;
;; Intra-unit calls: the codecs reach decomp_stream_refill (a FAR/RETF proc
;; defined earlier in this TU) with PUSH CS + CALL NEAR PTR -- the 4-byte
;; `0e e8` backward near-call form the unit-image gate verifies.

	.286

	extrn	_bak_fread:far			; 1000:0751  __cdecl file read

_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

; WORD-aligned: the original word-aligns this module (SYSLOWIO.C ends at the odd
; load-module byte 0x49f1, so TLINK emits one 0x00 pad to start us at the even 0x49f2);
; a BYTE-aligned _TEXT drops that pad and shifts the whole resident tail by -1.
S149F_TEXT	segment word public use16 'CODE'
	assume	cs:S149F_TEXT, ds:DGROUP

	public	_decomp_lzss
	public	_decomp_rle

;; ===========================================================================
;; decomp_stream_refill (149f:0002) -- input-buffer refill pump
;;
;; No stack frame of its own; reads the CALLER's frame.  Returns SI=buf_ptr,
;; CX=size for the caller's string-instruction loop.  size = min(buf_size,
;; remaining); remaining -= size; bak_fread(buf_ptr, size, 1, bakfile).
;; ===========================================================================
_decomp_stream_refill	proc far
	push	bx
	push	dx
	push	es
	mov	cx,word ptr [bp+0eh]	; CX = buf_size (chunk size)
	mov	bx,word ptr [bp+0ah]	; BX = remaining
	cmp	cx,bx
	jbe	short use_cx		; buf_size <= remaining: keep CX
	mov	cx,bx			; else size = remaining
use_cx:
	sub	word ptr [bp+0ah],cx	; remaining -= size
	push	cx			; save size
	mov	ax,word ptr [bp+10h]	; AX = bakfile
	mov	bx,word ptr [bp+0ch]	; BX = buf_ptr
	push	ax			; bak_fread arg4: stream
	push	1			; bak_fread arg3: count = 1
	push	cx			; bak_fread arg2: size
	push	bx			; bak_fread arg1: ptr
	call	_bak_fread
	add	sp,8			; __cdecl caller cleanup (4 args)
	pop	cx			; CX = size (for the caller)
	pop	es
	pop	dx
	pop	bx
	mov	si,word ptr [bp+0ch]	; SI = buf_ptr (for the caller)
	retf
_decomp_stream_refill	endp

;; ===========================================================================
;; decomp_lzss (149f:0030) -- LZSS decompressor
;;
;; Output via ES:DI (LES from [BP+6]).  Reads a flag byte into a bit buffer
;; (AH=0xff sentinel empties after 8 bits); per bit: 1=literal, 0=back-ref
;; (3-byte record: 16-bit ES-relative offset + length; copies length+5 bytes
;; from earlier output via REP ES:MOVSW).  A fast path (>=0x1e buffered) skips
;; per-byte refill checks; a slow path checks refill before every read.
;; ===========================================================================
_decomp_lzss	proc far
	push	bp
	mov	bp,sp
	push	si
	push	di
	push	es
	xor	dx,dx
	les	di,dword ptr [bp+06h]	; ES:DI = dst (far output pointer)
	push	cs
	call	near ptr _decomp_stream_refill
				; returns: SI = buf_ptr, CX = bytes read

; LAB_003f -- top of main (outer) loop: fetch next flag byte from input
LAB_003f:
	lodsb				; AL = *SI++  (flag byte)
	mov	ah,0ffh
	mov	dx,ax			; DX = 0xff00|(flag_byte) -- bit buffer + sentinel
	dec	cx
	cmp	cx,01eh			; is at least 30 bytes remaining?
	jle	LAB_009e		; no -> slow path with per-byte refill checks

	; fast path: CX >= 30, no refill needed for next 8 bits
	cmp	al,0ffh			; flag == 0xff -> all 8 bits literal?
	jnz	LAB_0057		; no -> fast bit loop
	; FAST COPY: 4 MOVSW (8 bytes), then loop
	movsw				; *DI++ = *SI++  (word)
	movsw
	movsw
	movsw
	sub	cx,8
	jmp	short LAB_003f

; LAB_0057 -- fast bit loop (CX >= 0x1e, no per-byte refill checks)
LAB_0057:
	or	dh,dh			; any bits left in sentinel?
	jz	LAB_003f		; no -> fetch next flag byte
	shr	dx,1			; shift low bit into carry
	jnc	LAB_0062		; carry=0 -> back-reference
	movsb				; literal: *DI++ = *SI++
	loop	LAB_0057		; --CX != 0 -> loop

; LAB_0062 -- back-reference, fast path (buffer has >= 3 bytes)
LAB_0062:
	mov	bx,si			; save SI in BX
	mov	ax,cx			; save CX in AX
	xor	ch,ch
	mov	cl,byte ptr [si+2]	; length byte (3rd back-ref byte)
	mov	si,word ptr [si]	; back-ref near offset (in ES segment)
	add	cx,5
	shr	cx,1
	db	0f3h, 026h, 0a5h	; REP ES:MOVSW -- copy CX words: ES:SI -> ES:DI
	jnc	LAB_0079
	db	026h, 0a4h		; ES:MOVSB -- copy odd byte: ES:SI -> ES:DI
LAB_0079:
	mov	si,bx			; restore SI
	mov	cx,ax			; restore CX
	add	si,3			; advance past 3 back-ref record bytes
	sub	cx,3
	jmp	short LAB_0057

; LAB_0085 -- slow path: check refill, then read next flag byte
LAB_0085:
	or	cx,cx
	ja	LAB_0093		; CX > 0: buffer has data, skip refill
	cmp	word ptr [bp+0ah],0	; remaining == 0?
	jz	LAB_0105		; yes -> done
	push	cs
	call	near ptr _decomp_stream_refill

; LAB_0093 -- have byte: read flag byte after refill
LAB_0093:
	lodsb				; AL = *SI++
	dec	cx
	mov	ah,0ffh
	mov	dx,ax			; DX = 0xff00|(flag_byte)
	cmp	cx,01eh
	jge	LAB_0057		; fast path if enough in buffer

; LAB_009e -- slow bit loop top (CX < 0x1e)
LAB_009e:
	or	dh,dh			; any bits left in sentinel?
	jz	LAB_0085		; no -> refill check + re-read flag byte
	shr	dx,1			; shift low bit into carry
	jnc	LAB_00b9		; carry=0 -> back-reference slow

; LAB_00a6 -- literal, slow path
LAB_00a6:
	or	cx,cx
	ja	LAB_00b4		; CX > 0: have byte
	cmp	word ptr [bp+0ah],0	; remaining == 0?
	jz	LAB_0105
	push	cs
	call	near ptr _decomp_stream_refill
LAB_00b4:
	lodsb				; AL = *SI++
	dec	cx
	stosb				; *DI++ = AL
	jmp	short LAB_009e

; LAB_00b9 -- back-reference slow path: read lo_byte
LAB_00b9:
	or	cx,cx
	ja	LAB_00c7		; CX > 0
	cmp	word ptr [bp+0ah],0
	jz	LAB_0105
	push	cs
	call	near ptr _decomp_stream_refill
LAB_00c7:
	lodsb
	dec	cx
	mov	bl,al			; save lo_byte in BL

; LAB_00cb -- read hi_byte
LAB_00cb:
	or	cx,cx
	ja	LAB_00d9		; CX > 0
	cmp	word ptr [bp+0ah],0
	jz	LAB_0105
	push	cs
	call	near ptr _decomp_stream_refill
LAB_00d9:
	lodsb
	dec	cx
	mov	bh,al			; save hi_byte in BH  (BX = hi:lo back-ref offset)

; LAB_00db -- read length byte
LAB_00db:
	or	cx,cx
	ja	LAB_00eb		; CX > 0
	cmp	word ptr [bp+0ah],0
	jz	LAB_0105
	push	cs
	call	near ptr _decomp_stream_refill
LAB_00eb:
	lodsb
	dec	cx
	push	si			; save SI (input ptr)
	push	cx			; save CX (remaining in buffer)
	mov	cl,al			; length byte
	xor	ch,ch
	add	cx,5
	mov	si,bx			; SI = back-ref near offset (BH:BL = ES-relative offset)
	shr	cx,1
	db	0f3h, 026h, 0a5h	; REP ES:MOVSW -- copy words: ES:SI -> ES:DI
	jnc	LAB_0101
	db	026h, 0a4h		; ES:MOVSB -- copy odd byte
LAB_0101:
	pop	cx			; restore CX
	pop	si			; restore SI
	jmp	short LAB_009e

LAB_0105:
	pop	es
	pop	di
	pop	si
	pop	bp
	retf
_decomp_lzss	endp

;; ===========================================================================
;; decomp_rle (149f:010a) -- byte-RLE decompressor
;;
;; Output via ES:DI.  Reads a token byte: low 7 bits = count (0 ends stream),
;; high bit selects mode.  Clear = literal run (copy `count` bytes verbatim);
;; set = repeat run (read one byte, emit it `count` times).
;; ===========================================================================
_decomp_rle	proc far
	push	bp
	mov	bp,sp
	push	si
	push	di
	push	es
	les	di,dword ptr [bp+06h]	; ES:DI = dst (far output pointer)
	push	cs
	call	near ptr _decomp_stream_refill
				; SI = buf_ptr, CX = bytes read
	jmp	L_main_loop_top

; --- repeat mode: high bit was set; BX = count ---
L_repeat_mode:
	or	cx,cx
	ja	L_got_fill_byte		; CX > 0: can read fill byte
	cmp	word ptr [bp+0ah],0	; refill_count == 0?
	jz	L_done
	push	cs
	call	near ptr _decomp_stream_refill
L_got_fill_byte:
	lodsb				; AL = fill byte; SI++
	dec	cx
	xchg	bx,cx			; CX = count, BX = remaining
	rep stosb			; write AL `count` times to ES:DI
	xchg	bx,cx			; restore CX = remaining

; --- main loop top: read next token ---
L_main_loop_top:
	or	cx,cx
	ja	L_read_token		; CX > 0: buffer has bytes
	cmp	word ptr [bp+0ah],0	; refill_count == 0?
	jz	L_done
	push	cs
	call	near ptr _decomp_stream_refill
L_read_token:
	lodsb				; AL = token byte; SI++
	dec	cx
	mov	bl,al
	and	bx,7fh			; BX = count (low 7 bits)
	jz	L_done			; count == 0 -> end of stream
	test	al,80h
	jnz	L_repeat_mode		; high bit -> repeat run

; --- literal mode ---
	cmp	cx,bx
	jl	L_lit_slow		; slow path if buffer has < count bytes
	; fast path: enough bytes in buffer for the whole run
	mov	dx,bx			; DX = count
	xchg	bx,cx			; CX = count, BX = prev CX
	rep movsb			; copy count bytes SI -> ES:DI
	xchg	bx,cx			; CX = remaining in buffer
	sub	cx,dx			; CX -= count
	jmp	L_main_loop_top

; --- literal slow path: buffer runs short, one byte at a time ---
L_lit_slow:
	or	cx,cx
	ja	L_lit_slow_have_byte	; CX > 0
	cmp	word ptr [bp+0ah],0	; refill_count == 0?
	jz	L_done
	push	cs
	call	near ptr _decomp_stream_refill
L_lit_slow_have_byte:
	lodsb				; read next literal byte
	dec	cx
	stosb				; write to ES:DI
	dec	bx			; BX = remaining count
	jnz	L_lit_slow
	jmp	L_main_loop_top

L_done:
	pop	es
	pop	di
	pop	si
	pop	bp
	retf
_decomp_rle	endp

S149F_TEXT	ends
	end
