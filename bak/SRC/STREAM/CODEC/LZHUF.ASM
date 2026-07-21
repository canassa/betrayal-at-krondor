;; =============================================================================
;; lzhuf.asm  --  KRONDOR.EXE Okumura/Yoshizaki LZHUF compression module.
;;
;; -----------------------------------------------------------------------------
;; MODULE MAP  (LZHUF.C function  ->  name)
;; -----------------------------------------------------------------------------
;;   InitTree         lzh_init_huffman_freq_tables
;;   InsertNode       lzss_insert_node
;;   DeleteNode       lzss_delete_node
;;   GetBit           lzh_get_bit
;;   GetByte          lzh_get_byte
;;   Putcode/PutBits  lzh_put_bits
;;   StartHuff        lzh_start_huff
;;   reconst()        lzh_update_huff                (tree rebuild body)
;;   update() entry   lzh_huff_update_leaf           (external entry)
;;   update() sift    lzh_update_huff_sift_up        (shared tail + RET)
;;   EncodeChar       lzh_encode_char
;;   EncodePosition   lzh_encode_position
;;   EncodeEnd        lzh_encode_end
;;   DecodeChar +     lzh_decode_char                (DecodeChar +
;;     DecodePosition                                            DecodePosition
;;                                                               head, folded)
;;   Encode           lzh_encode
;;   Decode entry     lzh_decode
;;   (ring write)     lzh_ring_buffer_write
;;   (match emit)     lzh_decode_match_emit          (shared RET)
;;
;; =============================================================================
;; MODULE NOTES
;; =============================================================================
;; Built from Okumura/Yoshizaki LZHUF.C, heavily modified from the reference.
;; Reference constants are unchanged: N=0x1000, NIL=0x1000, F=60=0x3c,
;; THRESHOLD=2, N_CHAR=0x13a, T=0x273, R=0x272, MAX_FREQ=0x8000. Modifications:
;;   * I/O replaced: getc(infile) -> stream_getc; putc(...) -> stream_putc; the
;;     decoder's output sink -> codec_emit_byte.
;;   * Arrays became FAR POINTERS in DGROUP: lson/rson/dad/freq/son/prnt/text_buf
;;     are far-ptr slots. StartHuff carves freq/prnt/son out of one heap scratch
;;     block (+0x103b/+0x1523/+0x1c7d).
;;   * getlen/putlen are BYTES, not the reference's ints.
;;   * Encode/Decode are RESUMABLE state machines (init flags; resume-in-match
;;     flag; 32-bit byte budgets). The space-fill loops are `rep stosb`.
;;   * reconst's two memmoves are merged into one indexed copy loop.
;;
;; THREE HAND-ASM POINTS:
;; (a) GetBit is hand-written, not compiler output: the while-loop is a single
;;     CMP+fall-through (one 8-bit refill always covers a 1-bit need); getbuf|= is
;;     memory-direct; getlen-=1 is a SUB byte,1 (not DEC); the return is an
;;     unfolded `xor ax,ax / cmp si,0 / jge / inc ax`.
;; (b) update -> reconst is a CALL flattened to a JMP: reconst keeps its full
;;     frame (sub sp,6 .. pop bp) but ends with a JMP where its RET belongs,
;;     jumping to the shared sift tail.
;; (c) Decode -> DecodePosition is likewise flattened: DecodePosition keeps a
;;     full frame but exits with a JMP to the post-call continuation.
;;
;; DECODEPOSITION FOLD:
;; DecodePosition was folded into the decode cluster by the same CALL->JMP
;; flattening: its entry frame (PUSH BP) and head live INSIDE lzh_decode_char's
;; body, and its tail (the bit-accumulate loop + the exit JMP to
;; lzh_decode_match_emit) follows. lzh_decode_char spans the whole of it; there
;; is no separate DecodePosition function -- its tail is a basic block of
;; lzh_decode_char. This unit emits the entire lzh_decode_char body (head +
;; DecodePosition fold + tail).
;; =============================================================================

	.286

; --- DGROUP globals (far ptrs = dword; near ptrs / words / bytes as marked) ---
; The module's LZH/LZSS state block is emitted from this obj's _BSS below. TASM
; allocates _BSS in file order; the symbols are declared ascending -- do not
; reorder.
	extrn	_g_pCurStreamRingBuf:word	; uchar * (near, DS-relative)
	extrn	_g_pCurStreamDesc:word		; near ptr -> stream descriptor

; --- the module's own LZH bit-I/O state + static Huffman tables: _DATA ---
	_DATA	segment word public 'DATA'
	public	_g_lzh_bit_buf, _g_lzh_bit_count, _g_lzhPutBuf, _g_lzhPutLen
	public	_g_lzhPLen, _g_lzhPCode, _g_lzhDCode, _g_lzhDLen
_g_lzh_bit_buf		dw	0	; ushort (getbuf)
_g_lzh_bit_count	db	0	; uchar  (getlen)
_g_lzhPutBuf		dw	0	; ushort (putbuf)
_g_lzhPutLen		db	0	; uchar  (putlen)
_g_lzhPLen	label byte		; p_len[]
	db	03h,04h,04h,04h,05h,05h,05h,05h,05h,05h,05h,05h,06h,06h,06h,06h
	db	06h,06h,06h,06h,06h,06h,06h,06h,07h,07h,07h,07h,07h,07h,07h,07h
	db	07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h
	db	08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h
_g_lzhPCode	label byte		; p_code[]
	db	00h,20h,30h,40h,50h,58h,60h,68h,70h,78h,80h,88h,90h,94h,98h,9ch
	db	0a0h,0a4h,0a8h,0ach,0b0h,0b4h,0b8h,0bch,0c0h,0c2h,0c4h,0c6h,0c8h,0cah,0cch,0ceh
	db	0d0h,0d2h,0d4h,0d6h,0d8h,0dah,0dch,0deh,0e0h,0e2h,0e4h,0e6h,0e8h,0eah,0ech,0eeh
	db	0f0h,0f1h,0f2h,0f3h,0f4h,0f5h,0f6h,0f7h,0f8h,0f9h,0fah,0fbh,0fch,0fdh,0feh,0ffh
_g_lzhDCode	label byte		; d_code[]
	db	00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
	db	00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
	db	01h,01h,01h,01h,01h,01h,01h,01h,01h,01h,01h,01h,01h,01h,01h,01h
	db	02h,02h,02h,02h,02h,02h,02h,02h,02h,02h,02h,02h,02h,02h,02h,02h
	db	03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h
	db	04h,04h,04h,04h,04h,04h,04h,04h,05h,05h,05h,05h,05h,05h,05h,05h
	db	06h,06h,06h,06h,06h,06h,06h,06h,07h,07h,07h,07h,07h,07h,07h,07h
	db	08h,08h,08h,08h,08h,08h,08h,08h,09h,09h,09h,09h,09h,09h,09h,09h
	db	0ah,0ah,0ah,0ah,0ah,0ah,0ah,0ah,0bh,0bh,0bh,0bh,0bh,0bh,0bh,0bh
	db	0ch,0ch,0ch,0ch,0dh,0dh,0dh,0dh,0eh,0eh,0eh,0eh,0fh,0fh,0fh,0fh
	db	10h,10h,10h,10h,11h,11h,11h,11h,12h,12h,12h,12h,13h,13h,13h,13h
	db	14h,14h,14h,14h,15h,15h,15h,15h,16h,16h,16h,16h,17h,17h,17h,17h
	db	18h,18h,19h,19h,1ah,1ah,1bh,1bh,1ch,1ch,1dh,1dh,1eh,1eh,1fh,1fh
	db	20h,20h,21h,21h,22h,22h,23h,23h,24h,24h,25h,25h,26h,26h,27h,27h
	db	28h,28h,29h,29h,2ah,2ah,2bh,2bh,2ch,2ch,2dh,2dh,2eh,2eh,2fh,2fh
	db	30h,31h,32h,33h,34h,35h,36h,37h,38h,39h,3ah,3bh,3ch,3dh,3eh,3fh
_g_lzhDLen	label byte		; d_len[]
	db	03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h
	db	03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h,03h
	db	04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h
	db	04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h
	db	04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h,04h
	db	05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h
	db	05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h
	db	05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h
	db	05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h,05h
	db	06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h
	db	06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h
	db	06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h,06h
	db	07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h
	db	07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h
	db	07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h,07h
	db	08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h,08h
	_DATA	ends

; --- the module's own LZH/LZSS state block: _BSS ---
	_BSS	segment word public 'BSS'
	public	_g_wLzhEncPaused, _g_nLzhEncEmitIdx, _g_wLzhEncCurChar
	public	_g_nLzhEncLookaheadLen, _g_wLzhEncR, _g_wLzhEncS, _g_nLzhEncLastMatchLen
	public	_g_wLzhDecPaused, _g_wLzhDecMatchBack, _g_nLzhDecMatchLen
	public	_g_nLzhDecMatchIdx, _g_wLzhDecR, _g_dwLzhDecBytesOut, _g_dwLzhDecBytesTarget
	public	_g_nLzssMatchLength, _g_pLzssLson, _g_pLzssRson, _g_nLzssMatchPosition
	public	_g_wLzhEncInitialized, _g_pLzhSon, _g_nLzhEncLastBitCount, _g_pLzssDad
	public	_g_pLzhFreq, _g_pLzhParent, _g_pLzssTextBuf, _g_wLzhEncLastBitVal
	public	_g_wLzhDecInitialized
_g_wLzhEncPaused	dw	?	; ushort
_g_nLzhEncEmitIdx	dw	?	; short
_g_wLzhEncCurChar	dw	?	; ushort
_g_nLzhEncLookaheadLen	dw	?	; short
_g_wLzhEncR	dw	?	; ushort
_g_wLzhEncS	dw	?	; ushort
_g_nLzhEncLastMatchLen	dw	?	; short
_g_wLzhDecPaused	dw	?	; ushort (mid-match suspend)
_g_wLzhDecMatchBack	dw	?	; ushort (match source offset)
_g_nLzhDecMatchLen	dw	?	; short (remaining match length)
_g_nLzhDecMatchIdx	dw	?	; short (index within match)
_g_wLzhDecR	dw	?	; ushort (ring write cursor)
_g_dwLzhDecBytesOut	dd	?	; dword (bytes emitted)
_g_dwLzhDecBytesTarget	dd	?	; dword
_g_nLzssMatchLength	dw	?	; short (match_length)
_g_pLzssLson	dd	?	; ushort far * (lson)
_g_pLzssRson	dd	?	; ushort far * (rson)
_g_nLzssMatchPosition	dw	?	; short (match_position)
_g_wLzhEncInitialized	dw	?	; ushort
_g_pLzhSon	dd	?	; ushort far * (son)
_g_nLzhEncLastBitCount	dw	?	; short
_g_pLzssDad	dd	?	; ushort far * (dad)
_g_pLzhFreq	dd	?	; ushort far * (freq)
_g_pLzhParent	dd	?	; ushort far * (prnt)
_g_pLzssTextBuf	dd	?	; uchar far * (text_buf)
_g_wLzhEncLastBitVal	dw	?	; ushort
_g_wLzhDecInitialized	dw	?	; ushort (one-time init flag)
	_BSS	ends
	DGROUP	group _DATA, _BSS

; --- external callees (all NEAR; far-call translated to near) ---
	extrn	_stream_getc:near		; getc(infile)
	extrn	_stream_putc:near		; putc(...)
	extrn	_codec_emit_byte:near		; decoder output sink
	extrn	__freemem:far			; _freemem (cdecl16far body). Double
						; underscore = the C symbol, not the CRT's far _freemem.

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

; All members PUBLIC so the linker can resolve the cross-TU calls into this module.
	public	_lzh_init_huffman_freq_tables
	public	_lzss_insert_node
	public	_lzss_delete_node
	public	_lzh_get_bit
	public	_lzh_get_byte
	public	_lzh_put_bits
	public	_lzh_start_huff
	public	_lzh_huff_update_leaf
	public	_lzh_encode_char
	public	_lzh_encode_position
	public	_lzh_encode_end
	public	_lzh_decode_char
	public	_lzh_encode
	public	_lzh_decode
	public	_lzh_ring_buffer_write
	public	_lzh_decode_match_emit

;==============================================================================
; InitTree -- lzh_init_huffman_freq_tables
;------------------------------------------------------------------------------
; LZHUF.C InitTree(), with the Dynamix far-pointer-array rewrite:
;   void InitTree(void) {
;       int i;
;       for (i = N+1; i <= N+256; i++) rson[i] = NIL;   // tree roots
;       for (i = 0;   i <  N;        i++) dad[i]  = NIL; // node parents
;       /* lson[] is cleared per-node in InsertNode */
;   }
; (N = NIL = 0x1000; rson = g_pLzssRson, dad = g_pLzssDad.)
;==============================================================================
_lzh_init_huffman_freq_tables	proc near
	push	si
	mov	si,1001h			; i = N+1  1001h LZSS loop start N+1=4097
	jmp	short L_f7bf
L_f7af:
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
	mov	word ptr es:[bx],1000h		; rson[i]=NIL  1000h N=NIL sentinel 4096
	inc	si
L_f7bf:
	cmp	si,1100h			; i<=N+256  1100h loop bound N+256=4352
	jle	L_f7af
	xor	si,si				; i = 0
	jmp	short L_f7d9
L_f7c9:
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	word ptr es:[bx],1000h		; dad[i]=NIL  1000h N=NIL sentinel 4096
	inc	si
L_f7d9:
	cmp	si,1000h			; i<N  1000h loop bound N=4096
	jl	L_f7c9
	pop	si
	ret
_lzh_init_huffman_freq_tables	endp

;==============================================================================
; InsertNode -- lzss_insert_node
;------------------------------------------------------------------------------
; LZHUF.C InsertNode(int r): insert node r into the LZSS binary-search trie,
; tracking the longest match in g_nLzssMatchLength / g_nLzssMatchPosition.  The
; source's duplicated ((r-p)&(N-1))-1 expression is compiled twice, at the two
; pos= sites.
;==============================================================================
_lzss_insert_node	proc near
	push	bp
	mov	bp,sp
	sub	sp,6h
	push	si
	push	di
	mov	cx,1h
	mov	ax,word ptr [_g_pLzssTextBuf+2]	; seg half of text_buf
	mov	dx,word ptr [_g_pLzssTextBuf]	; off half of text_buf
	add	dx,word ptr [bp+4h]		; + r
	mov	word ptr [bp-2h],ax		; [bp-2] = seg half
	mov	word ptr [bp-4h],dx		; [bp-4] = off half
	les	bx,[bp-4h]
	mov	al,byte ptr es:[bx]
	mov	ah,0h
	add	ax,1001h			; 1001h search-key bias N+1
	mov	si,ax				; si = text_buf[r] + 0x1001 (search key)
	mov	dx,word ptr [bp+4h]
	shl	dx,1h
	les	bx,[_g_pLzssLson]
	add	bx,dx
	mov	ax,1000h			; 1000h NIL sentinel 4096
	mov	word ptr es:[bx],ax		; lson[r] = NIL
	les	bx,[_g_pLzssRson]
	add	bx,dx
	mov	word ptr es:[bx],ax		; rson[r] = NIL
	mov	word ptr [_g_nLzssMatchLength],0h
L_7769:						; trie walk from node SI
	or	cx,cx
	jl	L_7799				; cmp < 0 -> Lson branch
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
	cmp	word ptr es:[bx],1000h		; 1000h NIL sentinel 4096
	jz	L_7783				; rson[SI] == NIL -> insert right
	mov	si,word ptr es:[bx]		; SI = rson[SI]
	jmp	short L_7797
L_7783:
	mov	ax,word ptr [bp+4h]
	mov	word ptr es:[bx],ax		; rson[SI] = r
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	word ptr es:[bx],si		; dad[r] = SI
	jmp	L_78fa
L_7797:
	jmp	short L_77c3
L_7799:
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssLson]
	add	bx,ax
	cmp	word ptr es:[bx],1000h		; 1000h NIL sentinel 4096
	jz	L_77af				; lson[SI] == NIL -> insert left
	mov	si,word ptr es:[bx]		; SI = lson[SI]
	jmp	short L_77c3
L_77af:
	mov	ax,word ptr [bp+4h]
	mov	word ptr es:[bx],ax		; lson[SI] = r
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	word ptr es:[bx],si		; dad[r] = SI
	jmp	L_78fa
L_77c3:
	mov	di,1h				; i = 1
	jmp	short L_77e4
L_77c8:						; compare text_buf[r+i] vs text_buf[SI+i]
	les	bx,[bp-4h]
	mov	cl,byte ptr es:[bx+di]
	mov	ch,0h
	les	bx,[_g_pLzssTextBuf]
	add	bx,si
	add	bx,di
	mov	dl,byte ptr es:[bx]
	mov	dh,0h
	sub	cx,dx
	or	cx,cx
	jnz	L_77e9				; mismatch -> exit compare loop
	inc	di
L_77e4:
	cmp	di,3ch				; while i < F (60)
	jl	L_77c8
L_77e9:
	cmp	di,2h
	jle	L_782a				; match length <= THRESHOLD -> loop
	cmp	di,word ptr [_g_nLzssMatchLength]
	jle	L_7809
	mov	ax,word ptr [bp+4h]		; new best: pos = ((r-SI)&(N-1))-1
	sub	ax,si
	and	ax,0fffh
	dec	ax
	mov	[_g_nLzssMatchPosition],ax
	mov	word ptr [_g_nLzssMatchLength],di
	cmp	di,3ch
	jge	L_782d				; i >= F -> replace node
L_7809:
	cmp	di,word ptr [_g_nLzssMatchLength]
	jnz	L_782a
	mov	ax,word ptr [bp+4h]		; tie: same ((r-SI)&(N-1))-1 computed AGAIN
	sub	ax,si
	and	ax,0fffh
	dec	ax
	mov	word ptr [bp-6h],ax
	cmp	ax,word ptr [_g_nLzssMatchPosition]
	jc	L_7824				; prefer numerically smaller position
	jmp	L_7769
L_7824:
	mov	ax,word ptr [bp-6h]
	mov	[_g_nLzssMatchPosition],ax
L_782a:
	jmp	L_7769
L_782d:						; replace SI in the trie with r (full match)
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	bx,word ptr [bp+4h]
	shl	bx,1h
	add	bx,word ptr [_g_pLzssDad]
	mov	word ptr es:[bx],ax		; dad[r] = dad[SI]
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssLson]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	bx,word ptr [bp+4h]
	shl	bx,1h
	add	bx,word ptr [_g_pLzssLson]
	mov	word ptr es:[bx],ax		; lson[r] = lson[SI]
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	bx,word ptr [bp+4h]
	shl	bx,1h
	add	bx,word ptr [_g_pLzssRson]
	mov	word ptr es:[bx],ax		; rson[r] = rson[SI]
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssLson]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	ax,word ptr [bp+4h]
	mov	word ptr es:[bx],ax		; dad[lson[SI]] = r
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	ax,word ptr [bp+4h]
	mov	word ptr es:[bx],ax		; dad[rson[SI]] = r
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
	cmp	word ptr es:[bx],si
	jnz	L_78d0
	mov	ax,word ptr [bp+4h]
	mov	word ptr es:[bx],ax		; rson[dad[SI]] = r
	jmp	short L_78eb
L_78d0:
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	shl	ax,1h
	les	bx,[_g_pLzssLson]
	add	bx,ax
	mov	ax,word ptr [bp+4h]
	mov	word ptr es:[bx],ax		; lson[dad[SI]] = r
L_78eb:
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	word ptr es:[bx],1000h		; dad[SI]=NIL  1000h NIL sentinel 4096
L_78fa:
	pop	di
	pop	si
	mov	sp,bp
	pop	bp
	ret
_lzss_insert_node	endp

;==============================================================================
; DeleteNode -- lzss_delete_node
;------------------------------------------------------------------------------
; LZHUF.C DeleteNode(int p): remove node p from the trie via the standard
; three-case BST delete (rson==NIL splice lson; lson==NIL splice rson; else
; walk rson to the in-order successor q, detach, and wire q into p's slot).
; No callees.
;==============================================================================
_lzss_delete_node	proc near
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	di,word ptr [bp+4h]
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	cmp	word ptr es:[bx],1000h		; 1000h NIL sentinel 4096
	jnz	L_791c
	jmp	L_7a81				; dad[p] == NIL -> not in tree
L_791c:
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
	cmp	word ptr es:[bx],1000h		; 1000h NIL sentinel 4096
	jnz	L_793d
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzssLson]
	add	bx,ax
	mov	si,word ptr es:[bx]		; rson[p]==NIL -> q = lson[p]
	jmp	L_7a30
L_793d:
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzssLson]
	add	bx,ax
	cmp	word ptr es:[bx],1000h		; 1000h NIL sentinel 4096
	jnz	L_795e
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
	mov	si,word ptr es:[bx]		; lson[p]==NIL -> q = rson[p]
	jmp	L_7a30
L_795e:
	mov	si,word ptr es:[bx]		; q = lson[p]
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
	cmp	word ptr es:[bx],1000h		; 1000h NIL sentinel 4096
	jnz	L_7975
	jmp	L_7a00
L_7975:
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
L_797f:
	mov	si,word ptr es:[bx]		; walk rson to leftmost-in-right successor
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
	cmp	word ptr es:[bx],1000h		; 1000h NIL sentinel 4096
	jnz	L_797f
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssLson]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	dx,si
	shl	dx,1h
	les	bx,[_g_pLzssDad]
	add	bx,dx
	mov	dx,word ptr es:[bx]
	shl	dx,1h
	les	bx,[_g_pLzssRson]
	add	bx,dx
	mov	word ptr es:[bx],ax		; rson[dad[q]] = lson[q]
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	dx,si
	shl	dx,1h
	les	bx,[_g_pLzssLson]
	add	bx,dx
	mov	dx,word ptr es:[bx]
	shl	dx,1h
	les	bx,[_g_pLzssDad]
	add	bx,dx
	mov	word ptr es:[bx],ax		; dad[lson[q]] = dad[q]
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzssLson]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	bx,si
	shl	bx,1h
	add	bx,word ptr [_g_pLzssLson]
	mov	word ptr es:[bx],ax		; lson[q] = lson[p]
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	word ptr es:[bx],si		; dad[lson[p]] = q
L_7a00:
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	bx,si
	shl	bx,1h
	add	bx,word ptr [_g_pLzssRson]
	mov	word ptr es:[bx],ax		; rson[q] = rson[p]
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	word ptr es:[bx],si		; dad[rson[p]] = q
L_7a30:
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	bx,si
	shl	bx,1h
	add	bx,word ptr [_g_pLzssDad]
	mov	word ptr es:[bx],ax		; dad[q] = dad[p]
	shl	ax,1h
	les	bx,[_g_pLzssRson]
	add	bx,ax
	cmp	word ptr es:[bx],di
	jnz	L_7a5a
	mov	word ptr es:[bx],si		; rson[dad[p]] = q
	jmp	short L_7a72
L_7a5a:
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	shl	ax,1h
	les	bx,[_g_pLzssLson]
	add	bx,ax
	mov	word ptr es:[bx],si		; lson[dad[p]] = q
L_7a72:
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzssDad]
	add	bx,ax
	mov	word ptr es:[bx],1000h		; dad[p]=NIL  1000h NIL sentinel 4096
L_7a81:
	pop	di
	pop	si
	pop	bp
	ret
_lzss_delete_node	endp

;==============================================================================
; GetBit -- lzh_get_bit   *** HAND-ASM ***
;------------------------------------------------------------------------------
; LZHUF.C GetBit() (reference):
;   int GetBit(void) {
;       unsigned i;
;       while (getlen <= 8) {
;           if ((i = getc(infile)) < 0) i = 0;
;           getbuf |= i << (8 - getlen);  getlen += 8;
;       }
;       i = getbuf;  getbuf <<= 1;  getlen--;
;       return (i & 0x8000) >> 15 != 0;   // (sign bit out)
;   }
; HAND-WRITTEN: the while-loop is a single CMP+fall-through (one 8-bit refill
; always covers a 1-bit need); getbuf|= is memory-direct; getlen-=1 is a
; SUB byte,1 (not DEC); the return is an unfolded
; `xor ax,ax / cmp si,0 / jge / inc ax`.
;==============================================================================
_lzh_get_bit	proc near
	push	si
	cmp	byte ptr [_g_lzh_bit_count],8h
	ja	L_7aa3				; getlen > 8 -> already have a bit
	call	_stream_getc
	mov	ah,0h
	mov	cl,8h
	sub	cl,byte ptr [_g_lzh_bit_count]
	shl	ax,cl
	or	word ptr [_g_lzh_bit_buf],ax	; getbuf |= i << (8-getlen)   (mem-direct)
	add	byte ptr [_g_lzh_bit_count],8h	; getlen += 8
L_7aa3:
	mov	si,word ptr [_g_lzh_bit_buf]
	shl	word ptr [_g_lzh_bit_buf],1h	; getbuf <<= 1
	sub	byte ptr [_g_lzh_bit_count],1h	; getlen-- (as SUB byte,1, not DEC)
	xor	ax,ax
	cmp	si,0h
	jge	L_7ab8
	inc	ax				; return sign(getbuf-before-shift)
L_7ab8:
	pop	si
	ret
_lzh_get_bit	endp

;==============================================================================
; GetByte -- lzh_get_byte
;------------------------------------------------------------------------------
; LZHUF.C GetByte() (modified):
;   int GetByte(void) {
;       unsigned short i;
;       while (getlen <= 8) {
;           getbuf |= (unsigned char)getc(infile) << (8 - getlen);
;           getlen += 8;
;       }
;       i = getbuf;  getbuf <<= 8;  getlen += 0xf8 (-8);  return i >> 8;
;   }
; GetBit's structural twin. The getlen+=8 statement here uses the AL round-trip,
; where GetBit's hand-asm uses the memory-direct form.
;==============================================================================
_lzh_get_byte	proc near
	push	bp
	mov	bp,sp
	push	si
	jmp	short L_fb99
L_fb80:
	call	_stream_getc
	mov	ah,0h
	mov	cl,8h
	sub	cl,byte ptr [_g_lzh_bit_count]
	shl	ax,cl
	or	word ptr [_g_lzh_bit_buf],ax
	mov	al,[_g_lzh_bit_count]		; getlen += 8 via AL round-trip
	add	al,8h
	mov	[_g_lzh_bit_count],al
L_fb99:
	cmp	byte ptr [_g_lzh_bit_count],8h
	jbe	L_fb80				; the REAL while-loop back edge
	mov	si,word ptr [_g_lzh_bit_buf]
	mov	cl,8h
	shl	word ptr [_g_lzh_bit_buf],cl	; getbuf <<= 8
	mov	al,[_g_lzh_bit_count]
	add	al,0f8h				; getlen -= 8
	mov	[_g_lzh_bit_count],al
	mov	ax,si
	mov	cl,8h
	shr	ax,cl				; return getbuf_old >> 8
	jmp	short L_fbba
L_fbba:
	pop	si
	pop	bp
	ret
_lzh_get_byte	endp

;==============================================================================
; PutBits/Putcode -- lzh_put_bits
;------------------------------------------------------------------------------
; LZHUF.C Putcode(int l, unsigned c): emit l MSB-first bits of c through the
; byte sink (stream_putc), holding a 16-bit shift register putbuf/putlen.
;==============================================================================
_lzh_put_bits	proc near
	push	bp
	mov	bp,sp
	push	si
	mov	si,word ptr [bp+6h]		; si = c (bits)
	mov	ax,si
	mov	cl,byte ptr [_g_lzhPutLen]
	shr	ax,cl
	or	word ptr [_g_lzhPutBuf],ax	; putbuf |= c >> putlen
	mov	al,[_g_lzhPutLen]
	add	al,byte ptr [bp+4h]		; putlen += l
	mov	[_g_lzhPutLen],al
	cmp	al,8h
	jc	L_7b5f
	mov	ax,[_g_lzhPutBuf]		; flush high byte
	mov	cl,8h
	shr	ax,cl
	push	ax
	call	_stream_putc
	add	sp,2h
	mov	al,[_g_lzhPutLen]
	add	al,0f8h				; putlen -= 8
	mov	[_g_lzhPutLen],al
	cmp	al,8h
	jc	L_7b59
	push	word ptr [_g_lzhPutBuf]		; flush low byte
	call	_stream_putc
	add	sp,2h
	mov	al,[_g_lzhPutLen]
	add	al,0f8h				; putlen -= 8
	mov	[_g_lzhPutLen],al
	mov	cl,byte ptr [bp+4h]
	sub	cl,byte ptr [_g_lzhPutLen]
	mov	ax,si
	shl	ax,cl
	mov	[_g_lzhPutBuf],ax		; putbuf = c << (l - putlen)
	jmp	short L_7b5f
L_7b59:
	mov	cl,8h
	shl	word ptr [_g_lzhPutBuf],cl	; putbuf <<= 8
L_7b5f:
	pop	si
	pop	bp
	ret
_lzh_put_bits	endp

;==============================================================================
; StartHuff -- lzh_start_huff
;------------------------------------------------------------------------------
; LZHUF.C StartHuff(): build the initial adaptive-Huffman tree.  Dynamix carves
; freq/prnt/son out of one heap scratch block (off +0x103b/+0x1523/+0x1c7d);
; freq[N_CHAR] leaves = 1, then N_CHAR internal nodes by summing pairs, son[] and
; prnt[] wired accordingly; freq[T]=0xffff sentinel, prnt[R]=0.
;==============================================================================
_lzh_start_huff	proc near
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	bx,word ptr [_g_pCurStreamDesc]	; freq = scratch + 0x103b
	mov	ax,word ptr [bx+4h]
	mov	dx,word ptr [bx+2h]
	add	dx,103bh			; 103bh freq[] disp into heap pScratch off-half
	mov	word ptr [_g_pLzhFreq+2],ax
	mov	word ptr [_g_pLzhFreq],dx
	mov	bx,word ptr [_g_pCurStreamDesc]	; prnt = scratch + 0x1523
	mov	ax,word ptr [bx+4h]
	mov	dx,word ptr [bx+2h]
	add	dx,1523h			; 1523h prnt[] disp into heap pScratch (freq+0x4e8=(T+1)*2)
	mov	word ptr [_g_pLzhParent+2],ax
	mov	word ptr [_g_pLzhParent],dx
	mov	bx,word ptr [_g_pCurStreamDesc]	; son = scratch + 0x1c7d
	mov	ax,word ptr [bx+4h]
	mov	dx,word ptr [bx+2h]
	add	dx,1c7dh			; 1c7dh son[] disp into heap pScratch (prnt+0x75a=(T+N_CHAR)*2)
	mov	word ptr [_g_pLzhSon+2],ax
	mov	word ptr [_g_pLzhSon],dx
	xor	si,si				; for i in [0, N_CHAR)
	jmp	short L_7bdc
L_7baa:
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzhFreq]
	add	bx,ax
	mov	word ptr es:[bx],1h		; freq[i] = 1
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzhSon]
	add	bx,ax
	mov	ax,si
	add	ax,273h				; 273h T=627 node-index base
	mov	word ptr es:[bx],ax		; son[i] = i + T
	mov	ax,si
	add	ax,273h				; 273h T=627 node-index base
	shl	ax,1h
	les	bx,[_g_pLzhParent]
	add	bx,ax
	mov	word ptr es:[bx],si		; prnt[i+T] = i
	inc	si
L_7bdc:
	cmp	si,13ah				; 13ah loop bound N_CHAR=314
	jl	L_7baa
	xor	si,si				; i=0, j=N_CHAR; build internal nodes
	mov	di,13ah				; 13ah j=N_CHAR=314 node-index
	jmp	short L_7c3e
L_7be9:
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzhFreq]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	dx,si
	inc	dx
	shl	dx,1h
	les	bx,[_g_pLzhFreq]
	add	bx,dx
	add	ax,word ptr es:[bx]
	mov	dx,di
	shl	dx,1h
	les	bx,[_g_pLzhFreq]
	add	bx,dx
	mov	word ptr es:[bx],ax		; freq[j] = freq[i] + freq[i+1]
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzhSon]
	add	bx,ax
	mov	word ptr es:[bx],si		; son[j] = i
	mov	ax,si
	inc	ax
	shl	ax,1h
	les	bx,[_g_pLzhParent]
	add	bx,ax
	mov	ax,di
	mov	word ptr es:[bx],ax		; prnt[i+1] = j
	mov	dx,si
	shl	dx,1h
	les	bx,[_g_pLzhParent]
	add	bx,dx
	mov	word ptr es:[bx],ax		; prnt[i] = j
	inc	si
	inc	si
	inc	di
L_7c3e:
	cmp	di,272h				; 272h loop bound R=626
	jle	L_7be9
	les	bx,[_g_pLzhFreq]
	mov	word ptr es:[bx+4e6h],0ffffh	; freq[T] = 0xffff sentinel
	les	bx,[_g_pLzhParent]
	mov	word ptr es:[bx+4e4h],0h	; prnt[R] = 0
	pop	di
	pop	si
	pop	bp
	ret
_lzh_start_huff	endp

;==============================================================================
; update() + reconst()  --  THE HAND-FLATTENED CLUSTER
;------------------------------------------------------------------------------
; LZHUF.C update(int c):
;   void update(int c) {
;       if (freq[R] == MAX_FREQ) reconst();   // overflow: rebuild the tree
;       c = prnt[c + T];                       // both paths converge here
;       do { ++freq[c]; ...swap up... } while ((c = prnt[c]) != 0);
;   }
; LZHUF.C reconst(): collect leaves, halve freqs, rebuild N_CHAR internal nodes
; (insert-sort), reconnect prnt[].  Dynamix MERGED reconst's two memmoves into
; one indexed down-counter copy loop (L_7d20).
;
; THE FLATTENING: this is ONE function with exactly ONE RET (at L_7eee), in
; three blocks:
;   * reconst's BODY sits FIRST with its OWN frame (sub sp,6) -- and ends with a
;     JMP to the sift tail where its RET belongs.
;   * the ENTRY is the MIDDLE block (the only external label): checks
;     freq[R]==MAX_FREQ, then JNZ sift / JMP reconst -- the CALL->JMP edit.
;   * the SIFT tail has NO prologue; it reads c at [BP+4] and locals at
;     [BP-2]/[BP-4] off the ENTRY's frame (valid on the reconst path only because
;     reconst's `pop bp` restored it), and holds the single RET.
;==============================================================================
_lzh_update_huff:				; reconst() body
	push	bp
	mov	bp,sp
	sub	sp,6h
	push	si
	push	di
	xor	cx,cx
	xor	si,si
	jmp	short L_7cb6
L_7c6c:
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzhSon]
	add	bx,ax
	cmp	word ptr es:[bx],273h		; 273h T=627 leaf/node test
	jl	L_7cb5
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzhFreq]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	inc	ax
	shr	ax,1h
	mov	dx,cx
	shl	dx,1h
	les	bx,[_g_pLzhFreq]
	add	bx,dx
	mov	word ptr es:[bx],ax		; freq[j] = (freq[i]+1)/2
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzhSon]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	dx,cx
	shl	dx,1h
	les	bx,[_g_pLzhSon]
	add	bx,dx
	mov	word ptr es:[bx],ax		; son[j] = son[i]
	inc	cx
L_7cb5:
	inc	si
L_7cb6:
	cmp	si,273h				; 273h loop bound T=627
	jl	L_7c6c
	xor	si,si
	mov	cx,13ah				; 13ah j=N_CHAR=314
	jmp	L_7d8b
L_7cc4:
	mov	ax,si
	inc	ax
	mov	di,ax
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzhFreq]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	dx,di
	shl	dx,1h
	les	bx,[_g_pLzhFreq]
	add	bx,dx
	add	ax,word ptr es:[bx]
	mov	dx,cx
	shl	dx,1h
	les	bx,[_g_pLzhFreq]
	add	bx,dx
	mov	word ptr es:[bx],ax
	mov	word ptr [bp-4h],ax
	mov	ax,cx
	dec	ax
	mov	di,ax
	jmp	short L_7cfb
L_7cfa:
	dec	di
L_7cfb:
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzhFreq]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	cmp	ax,word ptr [bp-4h]
	ja	L_7cfa
	inc	di
	mov	ax,cx
	sub	ax,di
	shl	ax,1h
	mov	word ptr [bp-6h],ax
	mov	ax,word ptr [bp-6h]
	dec	ax
	mov	word ptr [bp-2h],ax
	jmp	short L_7d65
L_7d20:						; MERGED memmove: freq[] and son[] in one loop
	mov	ax,di
	add	ax,word ptr [bp-2h]
	shl	ax,1h
	les	bx,[_g_pLzhFreq]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	dx,di
	add	dx,word ptr [bp-2h]
	inc	dx
	shl	dx,1h
	les	bx,[_g_pLzhFreq]
	add	bx,dx
	mov	word ptr es:[bx],ax
	mov	ax,di
	add	ax,word ptr [bp-2h]
	shl	ax,1h
	les	bx,[_g_pLzhSon]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	dx,di
	add	dx,word ptr [bp-2h]
	inc	dx
	shl	dx,1h
	les	bx,[_g_pLzhSon]
	add	bx,dx
	mov	word ptr es:[bx],ax
	dec	word ptr [bp-2h]
L_7d65:
	cmp	word ptr [bp-2h],0h
	jge	L_7d20
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzhFreq]
	add	bx,ax
	mov	ax,word ptr [bp-4h]
	mov	word ptr es:[bx],ax
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzhSon]
	add	bx,ax
	mov	word ptr es:[bx],si
	inc	si
	inc	si
	inc	cx
L_7d8b:
	cmp	cx,273h				; 273h loop bound T=627
	jge	L_7d94
	jmp	L_7cc4
L_7d94:
	xor	si,si
	jmp	short L_7dd9
L_7d98:
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzhSon]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	di,ax
	cmp	ax,273h				; 273h node-index test T=627
	jl	L_7dbb
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzhParent]
	add	bx,ax
	mov	word ptr es:[bx],si
	jmp	short L_7dd8
L_7dbb:
	mov	ax,di
	inc	ax
	shl	ax,1h
	les	bx,[_g_pLzhParent]
	add	bx,ax
	mov	ax,si
	mov	word ptr es:[bx],ax
	mov	dx,di
	shl	dx,1h
	les	bx,[_g_pLzhParent]
	add	bx,dx
	mov	word ptr es:[bx],ax
L_7dd8:
	inc	si
L_7dd9:
	cmp	si,273h				; 273h loop bound T=627
	jl	L_7d98
	pop	di
	pop	si
	mov	sp,bp
	pop	bp
	jmp	short _lzh_update_huff_sift_up	; reconst's RET replaced by JMP
	nop					; assembler relaxation pad
_lzh_huff_update_leaf:				; update() ENTRY (the only external entry)
	push	bp
	mov	bp,sp
	sub	sp,4h
	push	si
	push	di
	les	bx,[_g_pLzhFreq]
	cmp	word ptr es:[bx+4e4h],8000h	; if (freq[R] == MAX_FREQ)
	jnz	_lzh_update_huff_sift_up
	jmp	_lzh_update_huff		; CALL reconst flattened to JMP
_lzh_update_huff_sift_up:			; update()'s post-if body (shared tail)
	mov	ax,word ptr [bp+4h]
	add	ax,273h				; 273h T=627 node-index base
	shl	ax,1h
	les	bx,[_g_pLzhParent]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	word ptr [bp+4h],ax		; c = prnt[c + T]
L_7e13:
	mov	ax,word ptr [bp+4h]
	shl	ax,1h
	les	bx,[_g_pLzhFreq]
	add	bx,ax
	inc	word ptr es:[bx]		; ++freq[c]
	mov	ax,word ptr es:[bx]
	mov	word ptr [bp-2h],ax
	mov	si,word ptr [bp+4h]
	inc	si
	add	bx,2h
	mov	ax,word ptr es:[bx]
	cmp	ax,word ptr [bp-2h]
	jc	L_7e39
	jmp	L_7ed6
L_7e39:
	inc	si
	add	bx,2h
	mov	ax,word ptr es:[bx]
	cmp	ax,word ptr [bp-2h]
	jc	L_7e39
	dec	si
	sub	bx,2h
	mov	ax,word ptr es:[bx]
	mov	dx,word ptr [bp+4h]
	shl	dx,1h
	les	bx,[_g_pLzhFreq]
	add	bx,dx
	mov	word ptr es:[bx],ax
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzhFreq]
	add	bx,ax
	mov	ax,word ptr [bp-2h]
	mov	word ptr es:[bx],ax
	mov	ax,word ptr [bp+4h]
	shl	ax,1h
	les	bx,[_g_pLzhSon]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	word ptr [bp-4h],ax
	mov	ax,word ptr [bp-4h]
	shl	ax,1h
	les	bx,[_g_pLzhParent]
	add	bx,ax
	mov	word ptr es:[bx],si
	cmp	word ptr [bp-4h],273h		; 273h node-index test T=627
	jge	L_7e96
	add	bx,2h
	mov	word ptr es:[bx],si
L_7e96:
	mov	ax,si
	shl	ax,1h
	les	bx,[_g_pLzhSon]
	add	bx,ax
	mov	di,word ptr es:[bx]
	mov	ax,word ptr [bp-4h]
	mov	word ptr es:[bx],ax
	mov	ax,di
	shl	ax,1h
	les	bx,[_g_pLzhParent]
	add	bx,ax
	mov	ax,word ptr [bp+4h]
	mov	word ptr es:[bx],ax
	cmp	di,273h				; 273h node-index test T=627
	jge	L_7ec5
	add	bx,2h
	mov	word ptr es:[bx],ax
L_7ec5:
	mov	ax,word ptr [bp+4h]
	shl	ax,1h
	les	bx,[_g_pLzhSon]
	add	bx,ax
	mov	word ptr es:[bx],di
	mov	word ptr [bp+4h],si
L_7ed6:
	mov	ax,word ptr [bp+4h]
	shl	ax,1h
	les	bx,[_g_pLzhParent]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	word ptr [bp+4h],ax		; c = prnt[c]
	or	ax,ax
	jz	L_7eee
	jmp	L_7e13				; while (c != 0)
L_7eee:
	pop	di
	pop	si
	mov	sp,bp
	pop	bp
	ret					; THE single RET of update()+reconst()

;==============================================================================
; EncodeChar -- lzh_encode_char
;------------------------------------------------------------------------------
; LZHUF.C EncodeChar(unsigned c): walk the Huffman tree leaf->root accumulating
; the code LSB-first, emit it via Putcode, then update() the tree.
;==============================================================================
_lzh_encode_char	proc near
	push	bp
	mov	bp,sp
	dec	sp				; sub sp,2 as two DEC SP (minimal frame)
	dec	sp
	push	si
	push	di
	xor	si,si				; code = 0
	mov	ax,word ptr [bp+4h]
	add	ax,273h				; c+T  273h T=627 node-index base
	shl	ax,1h
	les	bx,[_g_pLzhParent]
	add	bx,ax
	mov	ax,word ptr es:[bx]		; k = prnt[c + T]
	mov	word ptr [bp-2h],ax
	xor	di,di				; len = 0
L_7f13:
	shr	si,1h				; code >>= 1
	test	word ptr [bp-2h],1h
	jz	L_7f20
	add	si,8000h			; code |= 0x8000 if (k & 1)
L_7f20:
	inc	di				; len++
	mov	ax,word ptr [bp-2h]
	shl	ax,1h
	les	bx,[_g_pLzhParent]
	add	bx,ax
	mov	ax,word ptr es:[bx]
	mov	word ptr [bp-2h],ax		; k = prnt[k]
	cmp	ax,272h				; 272h R=626 root index
	jnz	L_7f13				; while (k != R)
	push	si
	push	di
	call	_lzh_put_bits			; Putcode(len, code)
	add	sp,4h
	mov	word ptr [_g_wLzhEncLastBitVal],si
	mov	word ptr [_g_nLzhEncLastBitCount],di
	push	word ptr [bp+4h]
	call	_lzh_huff_update_leaf		; update(c)
	add	sp,2h
	pop	di
	pop	si
	mov	sp,bp
	pop	bp
	ret
_lzh_encode_char	endp

;==============================================================================
; EncodePosition -- lzh_encode_position
;------------------------------------------------------------------------------
; LZHUF.C EncodePosition(unsigned c): split the 12-bit distance into a 6-bit
; prefix (c>>6, coded via p_code[]/p_len[]) and a 6-bit raw suffix (c&0x3f),
; emitted MSB-aligned through Putcode.
;==============================================================================
_lzh_encode_position	proc near
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	di,word ptr [bp+4h]		; di = c (position)
	mov	ax,di
	mov	cl,6h
	shr	ax,cl				; prefix = c >> 6
	mov	si,ax
	mov	al,byte ptr [si+_g_lzhPCode]	; p_code[prefix]
	mov	ah,0h
	mov	cl,8h
	shl	ax,cl				; << 8 (bits arg)
	push	ax
	mov	al,byte ptr [si+_g_lzhPLen]	; p_len[prefix] (nbits arg)
	mov	ah,0h
	push	ax
	call	_lzh_put_bits			; Putcode(p_len[prefix], p_code[prefix]<<8)
	add	sp,4h
	mov	ax,di
	and	ax,3fh				; suffix = c & 0x3f
	mov	cl,0ah
	shl	ax,cl				; << 10 (bits arg)
	push	ax
	mov	ax,6h				; nbits = 6
	push	ax
	call	_lzh_put_bits			; Putcode(6, (c & 0x3f) << 10)
	add	sp,4h
	pop	di
	pop	si
	pop	bp
	ret
_lzh_encode_position	endp

;==============================================================================
; EncodeEnd -- lzh_encode_end
;------------------------------------------------------------------------------
; LZHUF.C EncodeEnd() (modified): flush putbuf's residual high byte, then free
; the three LZSS tree arrays.
;   void EncodeEnd(void) {
;       if (putlen) putc(putbuf >> 8);
;       free(lson); free(rson); free(dad);   // -> _freemem(...)
;   }
;==============================================================================
_lzh_encode_end	proc near
	cmp	byte ptr [_g_lzhPutLen],0h
	jz	L_006b
	mov	ax,[_g_lzhPutBuf]
	mov	cl,8h
	shr	ax,cl
	push	ax
	call	_stream_putc			; putc(putbuf >> 8)
	add	sp,2h
L_006b:
	push	word ptr [_g_pLzssLson+2]	; free(lson)
	push	word ptr [_g_pLzssLson]
	call	__freemem
	add	sp,4h
	push	word ptr [_g_pLzssRson+2]	; free(rson)
	push	word ptr [_g_pLzssRson]
	call	__freemem
	add	sp,4h
	push	word ptr [_g_pLzssDad+2]	; free(dad)
	push	word ptr [_g_pLzssDad]
	call	__freemem
	add	sp,4h
	ret
_lzh_encode_end	endp

;==============================================================================
; DecodeChar + DecodePosition  --  lzh_decode_char
;------------------------------------------------------------------------------
; LZHUF.C DecodeChar(): descend the Huffman tree by GetBit until a leaf, then
; update(c) and return the symbol.  DecodePosition(): GetByte the 6-bit prefix,
; look up d_code[]/d_len[], GetBit the remaining bits, return the 12-bit
; distance.  Both were FOLDED into the resumable decode cluster:
;   * DecodeChar rides _lzh_decode's frame (no PUSH BP); after the leaf it
;     update()s and JMPs to lzh_ring_buffer_write.
;   * DecodePosition (HEAD) DOES keep a full compiled frame (PUSH BP..), and its
;     TAIL exits with a JMP to lzh_decode_match_emit -- the Decode->DecodePosition
;     CALL->JMP flatten (see the DecodePosition fold note above). The tail is a
;     basic block of THIS member's body, not an orphan.
;==============================================================================
_lzh_decode_char:				; DecodeChar (rides _lzh_decode's frame)
	les	bx,[_g_pLzhSon]
	mov	di,word ptr es:[bx+4e4h]
	jmp	L_7ffc
L_7fe7:
	call	_lzh_get_bit
	mov	bx,ax
	add	bx,di
	shl	bx,1h
	add	bx,word ptr [_g_pLzhSon]
	mov	ax,word ptr [_g_pLzhSon+2]
	mov	es,ax
	mov	di,word ptr es:[bx]
L_7ffc:
	cmp	di,273h				; 273h loop bound T=627
	jc	L_7fe7				; while (di < T) descend
	sub	di,273h				; di-=T  273h T=627, decoded symbol = node-T
	push	di
	call	_lzh_huff_update_leaf		; update(c)
	add	sp,2h
	jmp	L_82f8				; -> lzh_ring_buffer_write (emit literal)

L_decodepos:					; DecodePosition (HEAD: keeps a frame)
	push	bp
	mov	bp,sp
	dec	sp
	dec	sp
	push	si
	push	di
	call	_lzh_get_byte
	mov	si,ax
	mov	al,_g_lzhDCode[si]		; d_code[GetByte()]
	mov	ah,0h
	mov	cl,6h
	shl	ax,cl
	mov	word ptr [bp-2h],ax		; high bits = d_code[i] << 6
	mov	al,_g_lzhDLen[si]		; d_len[i]
	mov	ah,0h
	mov	di,ax
	dec	di
	dec	di
	jmp	L_8040
; --- DecodePosition TAIL (see the header) ---
L_8035:
	call	_lzh_get_bit
	mov	dx,si
	shl	dx,1h
	add	dx,ax
	mov	si,dx				; i = (i << 1) + GetBit()
L_8040:
	mov	ax,di
	dec	di
	or	ax,ax
	jnz	L_8035				; for the low bits
	mov	ax,si
	and	ax,3fh				; suffix = i & 0x3f
	push	ax
	mov	ax,word ptr [bp-2h]
	pop	dx
	or	ax,dx				; distance = high | suffix
	jmp	L_8055
L_8055:
	pop	di
	pop	si
	mov	sp,bp
	pop	bp
	jmp	_lzh_decode_match_emit		; CALL->JMP flatten to match emit

;==============================================================================
; Encode -- lzh_encode
;------------------------------------------------------------------------------
; LZHUF.C Encode() (rewritten resumable): fill the LZSS window, find matches via
; InsertNode/DeleteNode, emit symbols via EncodeChar/EncodePosition, supporting
; mid-stream suspend/resume (g_wLzhEncPaused).  Contains the `rep stosb` memset
; intrinsic with a PUSH DI/POP DI live-guard and an unreachable if/else-lowering
; branch.
;==============================================================================
_lzh_encode	proc near
	push	bp
	mov	bp,sp
	sub	sp,4h
	push	si
	push	di
	mov	bx,word ptr [_g_pCurStreamDesc]
	mov	al,byte ptr [bx+1bh]
	mov	ah,0h
	mov	word ptr [bp-2h],ax		; local_2 = desc[0x1b] (write index)
	mov	bx,word ptr [_g_pCurStreamDesc]
	mov	al,byte ptr [bx+1ah]
	mov	ah,0h
	mov	di,ax				; uVar4 = desc[0x1a] (input end)
	mov	si,word ptr [_g_pCurStreamRingBuf]
	mov	ax,word ptr [bp-2h]
	mov	word ptr [bp-4h],ax		; local_4 = local_2
	cmp	word ptr [_g_wLzhEncInitialized],0h
	jz	L_8090
	jmp	L_814a
L_8090:
	cmp	word ptr [_g_wLzhEncPaused],0h
	jnz	L_80c6
	call	_lzh_start_huff
	call	_lzh_init_huffman_freq_tables
	mov	word ptr [_g_wLzhEncS],0h
	mov	word ptr [_g_wLzhEncR],0fc4h	; fc4h ring init r=N-F=4036
	push	di				; rep stosb memset, DI live-guarded
	les	di,[_g_pLzssTextBuf]
	add	di,word ptr [_g_nLzhEncEmitIdx]
	mov	cx,word ptr [_g_wLzhEncR]
	sub	cx,word ptr [_g_nLzhEncEmitIdx]
	mov	al,20h
	cld
	rep	stosb				; fill text_buf with ' '
	pop	di
	mov	word ptr [_g_nLzhEncLookaheadLen],0h
L_80c6:
	mov	word ptr [_g_wLzhEncPaused],0h
	jmp	short L_80ed
L_80ce:
	mov	bx,word ptr [bp-4h]
	mov	al,byte ptr [bx+si]
	les	bx,[_g_pLzssTextBuf]
	add	bx,word ptr [_g_wLzhEncR]
	add	bx,word ptr [_g_nLzhEncLookaheadLen]
	mov	byte ptr es:[bx],al
	inc	word ptr [bp-4h]
	and	word ptr [bp-4h],7fh
	inc	word ptr [_g_nLzhEncLookaheadLen]
L_80ed:
	cmp	word ptr [_g_nLzhEncLookaheadLen],3ch
	jge	L_80f9
	cmp	word ptr [bp-4h],di
	jnz	L_80ce
L_80f9:
	cmp	word ptr [bp-4h],di
	jnz	L_8119
	cmp	word ptr [bp+4h],0h
	jnz	L_8119
	mov	word ptr [_g_wLzhEncPaused],1h	; suspend (input exhausted, no flush)
	mov	bx,word ptr [_g_pCurStreamDesc]
	mov	al,byte ptr [bp-4h]
	mov	byte ptr [bx+1bh],al
	xor	ax,ax
	jmp	L_829b
L_8119:
	mov	word ptr [_g_nLzhEncEmitIdx],1h	; prime trie: InsertNode(R-1..R-F)
	jmp	short L_8133
L_8121:
	mov	ax,[_g_wLzhEncR]
	sub	ax,word ptr [_g_nLzhEncEmitIdx]
	push	ax
	call	_lzss_insert_node
	add	sp,2h
	inc	word ptr [_g_nLzhEncEmitIdx]
L_8133:
	cmp	word ptr [_g_nLzhEncEmitIdx],3ch
	jle	L_8121
	push	word ptr [_g_wLzhEncR]
	call	_lzss_insert_node		; InsertNode(R)
	add	sp,2h
	mov	word ptr [_g_wLzhEncInitialized],1h
L_814a:
	cmp	word ptr [_g_wLzhEncPaused],0h
	jnz	L_81a6
	mov	ax,[_g_nLzssMatchLength]
	cmp	ax,word ptr [_g_nLzhEncLookaheadLen]
	jle	L_8160
	mov	ax,[_g_nLzhEncLookaheadLen]
	mov	[_g_nLzssMatchLength],ax		; clamp match_length to lookahead
L_8160:
	cmp	word ptr [_g_nLzssMatchLength],2h
	jg	L_8183
	mov	word ptr [_g_nLzssMatchLength],1h	; match < 3: emit literal
	les	bx,[_g_pLzssTextBuf]
	add	bx,word ptr [_g_wLzhEncR]
	mov	al,byte ptr es:[bx]
	mov	ah,0h
	push	ax
	call	_lzh_encode_char
	add	sp,2h
	jmp	short L_819a
L_8183:
	mov	ax,[_g_nLzssMatchLength]	; match >= 3: length code + position
	add	ax,0fdh
	push	ax
	call	_lzh_encode_char
	add	sp,2h
	push	word ptr [_g_nLzssMatchPosition]
	call	_lzh_encode_position
	add	sp,2h
L_819a:
	mov	ax,[_g_nLzssMatchLength]
	mov	[_g_nLzhEncLastMatchLen],ax
	mov	word ptr [_g_nLzhEncEmitIdx],0h
L_81a6:
	mov	word ptr [_g_wLzhEncPaused],0h
	jmp	short L_8214
L_81ae:
	mov	bx,word ptr [bp-4h]
	mov	al,byte ptr [bx+si]
	mov	ah,0h
	mov	[_g_wLzhEncCurChar],ax
	inc	word ptr [bp-4h]
	and	word ptr [bp-4h],7fh
	push	word ptr [_g_wLzhEncS]
	call	_lzss_delete_node
	add	sp,2h
	les	bx,[_g_pLzssTextBuf]
	add	bx,word ptr [_g_wLzhEncS]
	mov	al,byte ptr [_g_wLzhEncCurChar]
	mov	byte ptr es:[bx],al
	cmp	word ptr [_g_wLzhEncS],3bh
	jge	L_81f2
	mov	bx,word ptr [_g_wLzhEncS]	; mirror first F-1 bytes to text_buf+N
	mov	es,word ptr [_g_pLzssTextBuf+2]
	add	bx,word ptr [_g_pLzssTextBuf]
	mov	al,byte ptr [_g_wLzhEncCurChar]
	mov	byte ptr es:[bx+1000h],al
L_81f2:
	inc	word ptr [_g_wLzhEncS]
	and	word ptr [_g_wLzhEncS],0fffh
	inc	word ptr [_g_wLzhEncR]
	and	word ptr [_g_wLzhEncR],0fffh
	push	word ptr [_g_wLzhEncR]
	call	_lzss_insert_node
	add	sp,2h
	inc	word ptr [_g_nLzhEncEmitIdx]
L_8214:
	mov	ax,[_g_nLzhEncEmitIdx]
	cmp	ax,word ptr [_g_nLzhEncLastMatchLen]
	jge	L_8224
	cmp	word ptr [bp-4h],di
	jz	L_8224
	jmp	short L_81ae
L_8224:
	cmp	word ptr [bp-4h],di
	jnz	L_8273
	cmp	word ptr [bp+4h],0h
	jnz	L_8273
	mov	word ptr [_g_wLzhEncPaused],1h	; suspend
	mov	bx,word ptr [_g_pCurStreamDesc]
	mov	al,byte ptr [bp-4h]
	mov	byte ptr [bx+1bh],al
	xor	ax,ax
	jmp	short L_829b
	db	0ebh, 02eh			; unreachable if/else-lowering branch
L_8245:
	push	word ptr [_g_wLzhEncS]		; drain loop (no more input)
	call	_lzss_delete_node
	add	sp,2h
	mov	ax,[_g_wLzhEncS]
	inc	ax
	and	ax,0fffh
	mov	[_g_wLzhEncS],ax
	mov	ax,[_g_wLzhEncR]
	inc	ax
	and	ax,0fffh
	mov	[_g_wLzhEncR],ax
	dec	word ptr [_g_nLzhEncLookaheadLen]
	jz	L_8273
	push	word ptr [_g_wLzhEncR]
	call	_lzss_insert_node
	add	sp,2h
L_8273:
	mov	ax,[_g_nLzhEncEmitIdx]
	inc	word ptr [_g_nLzhEncEmitIdx]
	cmp	ax,word ptr [_g_nLzhEncLastMatchLen]
	jl	L_8245
	cmp	word ptr [_g_nLzhEncLookaheadLen],0h
	jle	L_828a
	jmp	L_814a
L_828a:
	call	_lzh_encode_end
	mov	bx,word ptr [_g_pCurStreamDesc]
	mov	al,byte ptr [bp-4h]
	mov	byte ptr [bx+1bh],al
	xor	ax,ax
	jmp	short L_829b
L_829b:
	pop	di
	pop	si
	mov	sp,bp
	pop	bp
	ret
_lzh_encode	endp

;==============================================================================
; Decode -- lzh_decode (+ ring write + match emit)
;------------------------------------------------------------------------------
; LZHUF.C Decode() (rewritten resumable): PUSH SI,DI establishes the frame shared
; by the WHOLE decode cluster (DecodeChar/DecodePosition ride it).  The only RET
; of the cluster is the shared epilogue at the tail of match_emit.  The
; Decode->DecodePosition CALL->JMP flatten lives here.
;==============================================================================
_lzh_decode:
	push	si				; the cluster's shared frame
	push	di
	cmp	word ptr [_g_wLzhDecInitialized],0h
	jz	L_82ad
	jmp	L_83cc
L_82ad:
	mov	word ptr [_g_wLzhDecPaused],0h
	call	_lzh_start_huff
	les	di,[_g_pLzssTextBuf]
	mov	cx,0fc4h			; fc4h rep count N-F=4036 text_buf fill
	mov	al,20h
	cld
	rep	stosb				; constant-length memset (DI dead, no guard)
	mov	word ptr [_g_wLzhDecR],0fc4h	; fc4h ring init r=N-F=4036
	mov	word ptr [_g_dwLzhDecBytesOut+2],0h
	mov	word ptr [_g_dwLzhDecBytesOut],0h
	mov	bx,[_g_pCurStreamDesc]
	mov	ax,[bx+14h]
	mov	dx,[bx+12h]
	mov	word ptr [_g_dwLzhDecBytesTarget+2],ax
	mov	word ptr [_g_dwLzhDecBytesTarget],dx
	mov	word ptr [_g_wLzhDecInitialized],1h
	jmp	L_83cc
L_82ee:
	cmp	word ptr [_g_wLzhDecPaused],0h
	jnz	L_8331
	jmp	_lzh_decode_char		; fetch next DecodeChar symbol
_lzh_ring_buffer_write:
L_82f8:
	cmp	di,100h				; 100h literal/match split 256
	jge	L_8331
	push	di
	call	_codec_emit_byte
	add	sp,2h
	mov	si,ax
	les	bx,[_g_pLzssTextBuf]
	add	bx,word ptr [_g_wLzhDecR]
	mov	ax,di
	mov	byte ptr es:[bx],al		; ring[R] = literal
	inc	word ptr [_g_wLzhDecR]
	and	word ptr [_g_wLzhDecR],0fffh
	add	word ptr [_g_dwLzhDecBytesOut],1h
	adc	word ptr [_g_dwLzhDecBytesOut+2],0h
	or	si,si
	jnz	L_8331
	xor	ax,ax
	jmp	L_83e8
L_8331:
	cmp	di,100h				; 100h literal/match split 256
	jge	L_8341
	cmp	word ptr [_g_wLzhDecPaused],0h
	jnz	L_8341
	jmp	L_83cc
L_8341:
	cmp	word ptr [_g_wLzhDecPaused],0h
	jnz	L_8368
	jmp	L_decodepos			; DecodePosition, then fall into match emit
_lzh_decode_match_emit:
	mov	dx,word ptr [_g_wLzhDecR]
	sub	dx,ax
	dec	dx
	and	dx,0fffh
	mov	word ptr [_g_wLzhDecMatchBack],dx
	mov	ax,di
	add	ax,0ff03h
	mov	[_g_nLzhDecMatchLen],ax
	mov	word ptr [_g_nLzhDecMatchIdx],0h
L_8368:
	mov	word ptr [_g_wLzhDecPaused],0h
	jmp	L_83c3
L_8370:
	mov	ax,[_g_wLzhDecMatchBack]
	add	ax,word ptr [_g_nLzhDecMatchIdx]
	and	ax,0fffh
	les	bx,[_g_pLzssTextBuf]
	add	bx,ax
	mov	al,byte ptr es:[bx]
	mov	ah,0h
	mov	di,ax
	push	di
	call	_codec_emit_byte
	add	sp,2h
	mov	si,ax
	les	bx,[_g_pLzssTextBuf]
	add	bx,word ptr [_g_wLzhDecR]
	mov	ax,di
	mov	byte ptr es:[bx],al
	inc	word ptr [_g_wLzhDecR]
	and	word ptr [_g_wLzhDecR],0fffh
	add	word ptr [_g_dwLzhDecBytesOut],1h
	adc	word ptr [_g_dwLzhDecBytesOut+2],0h
	inc	word ptr [_g_nLzhDecMatchIdx]
	or	si,si
	jnz	L_83c3
	mov	word ptr [_g_wLzhDecPaused],1h
	xor	ax,ax
	jmp	L_83e8
L_83c3:
	mov	ax,[_g_nLzhDecMatchIdx]
	cmp	ax,word ptr [_g_nLzhDecMatchLen]
	jl	L_8370
L_83cc:
	mov	ax,word ptr [_g_dwLzhDecBytesOut+2]
	cmp	ax,word ptr [_g_dwLzhDecBytesTarget+2]
	jge	L_83d8
	jmp	L_82ee
L_83d8:
	jnz	L_83e6
	mov	ax,word ptr [_g_dwLzhDecBytesOut]
	cmp	ax,word ptr [_g_dwLzhDecBytesTarget]
	jnc	L_83e6
	jmp	L_82ee
L_83e6:
	xor	ax,ax
L_83e8:
	pop	di
	pop	si
	ret					; the decode cluster's single shared RET

S180C_TEXT	ends

	end
