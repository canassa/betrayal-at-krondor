; ============================================================================
; FARPTR.ASM -- KRONDOR.EXE hand-written far-pointer runtime (segment 180c).
;
; Eleven register-convention/near-leaf helpers, contiguous in the image
; (180c:2722..2954). One TASM module: the game's far-pointer primitive library
; -- the DX:AX-in/DX:AX-out normalize/arithmetic/copy core every other
; far-pointer-touching routine in the game (bak_load_chunk et al.) ultimately
; calls through, plus the fmemmove self-modifying dispatcher that calls FIVE of
; the other members directly:
;
;   _normalize_far_ptr          (180c:2722 / 0x1a7e2) DX:AX -> DX:AX. Reduces
;                                the offset to 0..15, folding the overflow
;                                paragraphs into the segment.
;   _normalize_far_ptr_flatten  (180c:2734 / 0x1a7f4) DX:AX -> DX:AX (or
;                                AX with DX=0). Normalizes via
;                                normalize_far_ptr, then flattens the pointer
;                                into a single near offset, backing off one
;                                64K bank if the normalized segment's high
;                                nibble is set.
;   _far_ptr_add_offset         (180c:2751 / 0x1a811) DX:AX + CX:BX (signed
;                                byte offset in BX, sign-extended via CX) ->
;                                DX:AX. No callees.
;   _far_ptr_sub_offset         (180c:2765 / 0x1a825) inverse of
;                                far_ptr_add_offset; subtracts CX:BX from
;                                AX:DX and re-normalizes via
;                                normalize_far_ptr.
;   _memcpy_far_backward        (180c:2780 / 0x1a840) descending
;                                DS:SI->ES:DI byte copy (CX bytes), word-core
;                                REP MOVSW with leading/trailing odd-byte
;                                handling. No callees.
;   _memcpy_far_forward         (180c:2797 / 0x1a857) ascending
;                                DS:SI->ES:DI byte copy (CX bytes), same
;                                word-core shape. No callees.
;   _fmemmove                   (180c:27ae / 0x1a86e) Borland-RTL-style far
;                                memmove. Self-modifies two CS-resident
;                                function-pointer slots (the 4-byte island
;                                immediately ahead of its entry) to select
;                                normalize_far_ptr vs normalize_far_ptr_flatten
;                                and memcpy_far_forward vs memcpy_far_backward
;                                per overlap direction, chunking the copy at
;                                0x7d00 bytes and calling far_ptr_add_offset
;                                to bias the pointers for the backward case.
;   _fmemcpy_far                (180c:2887 / 0x1a947) far memcpy: normalizes
;                                both pointers via normalize_far_ptr, then a
;                                word-core REP MOVSW copy.
;   _memset_far                 (180c:28c1 / 0x1a981) far memset: chunked
;                                (0x7d00/pass) word-core REP STOSW fill, one
;                                normalize_far_ptr call per chunk.
;   _far_ptr_cmp                (180c:291b / 0x1a9db) canonical (normalized)
;                                far-pointer comparison: two normalize_far_ptr
;                                calls, then an unsigned seg:off compare.
;   _normalize_far_ptr_thunk    (180c:2947 / 0x1aa07) the __cdecl ->
;                                register-convention bridge: loads the
;                                (offset,segment) stack args into AX/DX and
;                                CALLs normalize_far_ptr.
;
; Calling convention: every member is DX:AX-in/DX:AX-out register convention
; (no stack args for the far pointer), or (fmemmove/fmemcpy_far/memset_far/
; far_ptr_cmp/normalize_far_ptr_thunk) a C-callable far wrapper whose BODY
; issues register-convention near CALLs to the register-convention leaves.
; Members use REP MOVSW/MOVSB/STOSW string cores, RCR/RCL carry-chained bit
; tricks, and fmemmove's self-modifying CS-resident dispatch slots.
;
; All eleven live in one module: fmemmove's self-modify slots are a 4-byte
; CS-resident data island that sits physically BETWEEN memcpy_far_forward's
; last byte and fmemmove's entry point (CS:0x27aa/0x27ac), and fmemmove's body
; issues intra-segment near CALLs to normalize_far_ptr,
; normalize_far_ptr_flatten, memcpy_far_forward, memcpy_far_backward, and
; far_ptr_add_offset. The remaining five members (fmemcpy_far, memset_far,
; far_ptr_cmp, far_ptr_sub_offset, and the thunk) all near-CALL
; normalize_far_ptr in turn.
;
; Absolute relocated so it survives the relink:
;   * CS:0x27aa/0x27ac -> labels `g_slot_step`/`g_slot_copy` in this segment
;     (4 bytes: the self-modify function-pointer slots). They sit physically
;     FIRST in _fmemmove's block, immediately before its entry point, just
;     ahead of 180c:27ae. All patch values use `offset <symbol>`.
; The five intra-unit near calls (_normalize_far_ptr,
; _normalize_far_ptr_flatten, _memcpy_far_forward, _memcpy_far_backward,
; _far_ptr_add_offset) resolve locally within S180C_TEXT. No DGROUP globals
; are referenced by any member.
; ============================================================================

	.286

	; medium-model group, so DGROUP resolves (no member references a DGROUP
	; global; declared for ASSUME/DGROUP consistency).
_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_normalize_far_ptr, _normalize_far_ptr_flatten
	public	_far_ptr_add_offset, _far_ptr_sub_offset
	public	_memcpy_far_backward, _memcpy_far_forward
	public	_fmemmove, _fmemcpy_far, _memset_far
	public	_far_ptr_cmp, _normalize_far_ptr_thunk

; ----------------------------------------------------------------------------
; void far *normalize_far_ptr(void far *ptr)   -- register convention
; in/out: DX:AX (DX=segment, AX=offset), no stack args, no callees.
; Reduces the offset to 0..15 and folds the overflow paragraphs into the
; segment:  new offset = AX & 0xf ;  new segment = DX + (AX >> 4)
;
; Original disasm (180c:2722):
;   PUSH CX
;   MOV  CX,AX
;   AND  AX,0xf
;   SHR  CX,0x1   (x4)  -> CX = AX >> 4
;   ADD  DX,CX
;   POP  CX
;   RET
; ----------------------------------------------------------------------------
_normalize_far_ptr proc near
	push	cx
	mov	cx,ax
	and	ax,0fh
	shr	cx,1
	shr	cx,1
	shr	cx,1
	shr	cx,1
	add	dx,cx
	pop	cx
	ret
_normalize_far_ptr endp

; ----------------------------------------------------------------------------
; normalize_far_ptr_flatten (180c:2734, linear 0x1a7f4)
; Register-convention near helper (RET): normalizes the far pointer in DX:AX
; (segment in DX, offset in AX) via normalize_far_ptr, then FLATTENS it into a
; single near offset in AX. If the normalized segment's high nibble is set
; (DH & 0xf0), it instead backs the pointer off by one 64K bank
; (AX += 0xfff0; DX -= 0xfff) and returns DX:AX unchanged-shape. Otherwise it
; folds the segment into the offset: AX += DX<<4, DX = 0. Args/results in
; registers (DX:AX in, AX[:DX] out).
;
; Disassembly (180c:2734, linear 0x1a7f4):
;   180c:2734: CALL  normalize_far_ptr   ; far->normalized far ptr in DX:AX
;   180c:2737: TEST  DH,0xf0
;   180c:273a: JZ    0x1a804 (flatten)
;   180c:273c: ADD   AX,0xfff0
;   180c:273f: SUB   DX,0xfff
;   180c:2743: RET
;   180c:2744: SHL   DX,1                ; (flatten) DX <<= 4
;   180c:2746: SHL   DX,1
;   180c:2748: SHL   DX,1
;   180c:274a: SHL   DX,1
;   180c:274c: ADD   AX,DX               ; fold segment into offset
;   180c:274e: SUB   DX,DX               ; DX = 0
;   180c:2750: RET
; ----------------------------------------------------------------------------
_normalize_far_ptr_flatten proc near
	call	_normalize_far_ptr
	test	dh,0f0h
	jz	flatten
	add	ax,0fff0h
	sub	dx,0fffh                ; 0fffh seg bank-adjust (64K), paired add ax,0fff0h
	ret
flatten:
	shl	dx,1
	shl	dx,1
	shl	dx,1
	shl	dx,1
	add	ax,dx
	sub	dx,dx
	ret
_normalize_far_ptr_flatten endp

; ----------------------------------------------------------------------------
; far_ptr_add_offset -- register-convention far-pointer arithmetic helper at
; 180c:2751 (linear 0x1a811). Result in DX:AX. Inputs arrive in registers
; (AX/BX/CX/DX), not on the stack. No callees.
;
; Disassembly (180c:2751 - 180c:2764), RET -> near:
;   ADD AX,BX
;   SBB BX,BX
;   AND BX,0x1000
;   ADD DX,BX
;   MOV BX,CX
;   MOV CL,0x5
;   CLC
;   RCR BX,CL
;   ADD DX,BX
;   RET
; ----------------------------------------------------------------------------
_far_ptr_add_offset proc near
	add	ax, bx
	sbb	bx, bx
	and	bx, 1000h
	add	dx, bx
	mov	bx, cx
	mov	cl, 5
	clc
	rcr	bx, cl
	add	dx, bx
	ret
_far_ptr_add_offset endp

; ----------------------------------------------------------------------------
; far_ptr_sub_offset -- register-convention far-pointer arithmetic helper at
; 180c:2765 (linear 0x1a825). Inverse of far_ptr_add_offset (180c:2751):
; subtracts a signed byte offset from a far pointer and re-normalizes via
; normalize_far_ptr. Inputs arrive in registers (AX:DX = far ptr, BX = low
; offset word, CX = high offset word), not on the stack. Result returned in
; DX:AX (normalized).
;
; Disassembly (180c:2765 - 180c:277f), RET -> near:
;   NEG BX
;   ADD AX,BX
;   SBB BX,BX
;   NOT BX
;   AND BX,0x1000
;   SUB DX,BX
;   CALL normalize_far_ptr   ; near, same segment (E8 disp16)
;   MOV BX,CX
;   MOV CL,0x5
;   CLC
;   RCR BX,CL
;   SUB DX,BX
;   RET
; ----------------------------------------------------------------------------
_far_ptr_sub_offset proc near
	neg	bx
	add	ax, bx
	sbb	bx, bx
	not	bx
	and	bx, 1000h
	sub	dx, bx
	call	_normalize_far_ptr
	mov	bx, cx
	mov	cl, 5
	clc
	rcr	bx, cl
	sub	dx, bx
	ret
_far_ptr_sub_offset endp

; ----------------------------------------------------------------------------
; memcpy_far_backward -- register-convention block-copy helper (near, RET):
; copies CX bytes from DS:SI to ES:DI using a word-aligned MOVSW core,
; handling an odd DI start and the trailing/leading odd byte. Args/results
; live in registers (CX=count, DS:SI=src, ES:DI=dst). No callees.
;
; Disassembly (180c:2780, linear 0x1a840):
;   180c:2780: JCXZ  0x1a854          ; CX==0 -> tail REP MOVSB (no-op)
;   180c:2782: TEST  DI,0x1
;   180c:2786: JNZ   0x1a84a          ; DI odd -> skip the leading MOVSB
;   180c:2788: MOVSB ES:DI,SI         ; even DI: copy one byte first
;   180c:2789: DEC   CX
;   180c:278a: DEC   SI               ; (JNZ target) back up both pointers
;   180c:278b: DEC   DI
;   180c:278c: SHR   CX,0x1
;   180c:278e: MOVSW.REP ES:DI,SI     ; REP MOVSW word core
;   180c:2790: RCL   CX,0x1           ; recover the odd-byte carry into CX
;   180c:2792: INC   SI
;   180c:2793: INC   DI
;   180c:2794: MOVSB.REP ES:DI,SI     ; (JCXZ target) REP MOVSB final byte
;   180c:2796: RET
; ----------------------------------------------------------------------------
_memcpy_far_backward proc near
	jcxz	done            ; CX==0 -> tail REP MOVSB (count 0 = no-op)
	test	di,1
	jnz	odd_di          ; DI odd -> skip the single leading MOVSB
	movsb                   ; even DI: copy one byte to realign
	dec	cx
odd_di:
	dec	si
	dec	di
	shr	cx,1
	rep	movsw           ; word core
	rcl	cx,1            ; recover odd-byte carry back into CX
	inc	si
	inc	di
done:
	rep	movsb           ; final byte (CX is 0 or 1 here)
	ret
_memcpy_far_backward endp

; ----------------------------------------------------------------------------
; memcpy_far_forward -- register-convention forward memcpy helper (DF=0 path).
;   in:  ES:DI = dest, DS:SI = src, CX = byte count
; Aligns the first byte if DI is odd, copies the bulk as words, then a
; trailing byte. NEAR proc (listing ends RET). No callees, no DGROUP globals.
;
; Disassembly (180c:2797):
;   JCXZ  end          ; nothing to copy
;   TEST  DI,1
;   JZ    bulk         ; dest already word-aligned
;   MOVSB              ; copy one byte to align
;   DEC   CX
; bulk:
;   SHR   CX,1         ; CX = word count, carry = odd-byte flag
;   REP MOVSW
;   RCL   CX,1         ; CX = 1 if an odd trailing byte remains, else 0
;   REP MOVSB
; end:
;   RET
; ----------------------------------------------------------------------------
_memcpy_far_forward proc near
	jcxz	mcff_end                ; JCXZ 0x1000:a869 (RET)
	test	di,1
	jz	mcff_bulk               ; JZ 0x1000:a861 (SHR CX,1)
	movsb                           ; MOVSB ES:DI,SI
	dec	cx
mcff_bulk:
	shr	cx,1                    ; SHR CX,0x1
	rep	movsw                   ; MOVSW.REP ES:DI,SI
	rcl	cx,1                    ; RCL CX,0x1
	rep	movsb                   ; MOVSB.REP ES:DI,SI
mcff_end:
	ret
_memcpy_far_forward endp

; --- the 4-byte self-modify dispatch-slot island (was CS:0x27aa / CS:0x27ac)
; Two CS-resident function-pointer slots that live in the 4 bytes immediately
; BEFORE fmemmove's entry. Patched at the top of fmemmove to select the
; pointer-stepping helper (normalize_far_ptr forward vs
; normalize_far_ptr_flatten) and the block-copy direction (memcpy_far_forward
; vs memcpy_far_backward), then invoked via CALL word ptr CS:[slot]. Sits
; physically HERE -- between _memcpy_far_forward and _fmemmove -- just ahead of
; 180c:27ae. The static image is zeroed; the slots are always overwritten
; before their first read by fmemmove's own "default (forward) patch" at entry.
; The runtime patch stores (below) both use `offset <symbol>`.
g_slot_step  dw  0
g_slot_copy  dw  0

; ----------------------------------------------------------------------------
; fmemmove (180c:27ae, linear 0x1a86e)
; Borland-RTL-style far memmove primitive. Far (RETF); returns the original
; dst in DX:AX (memmove convention; the lone game caller ignores the result).
;
; SELF-MODIFYING dispatch via g_slot_step/g_slot_copy above (see the island
; comment). Overlap test (dst vs src, normalized) decides forward (default,
; patched to normalize_far_ptr + memcpy_far_forward) vs backward (STD,
; patched to normalize_far_ptr_flatten + memcpy_far_backward). The copy runs
; in <=0x7d00-byte chunks; pointers are re-normalized each chunk.
;
; Ground-truth disassembly: 180c:27ae..2886 (see reference/listing.asm).
; ----------------------------------------------------------------------------
_fmemmove proc far
	push	bp
	mov	bp,sp
	sub	sp,4
	push	si
	push	di
	push	ds
	; default (forward) patch
	mov	word ptr cs:[g_slot_step],offset _normalize_far_ptr
	mov	word ptr cs:[g_slot_copy],offset _memcpy_far_forward
	; normalize dst, save original dst for the DX:AX return
	mov	ax,word ptr [bp+6]
	mov	dx,word ptr [bp+8]
	mov	word ptr [bp-4],ax
	mov	word ptr [bp-2],dx
	call	_normalize_far_ptr
	mov	word ptr [bp+6],ax
	mov	word ptr [bp+8],dx
	; normalize src
	mov	ax,word ptr [bp+0ah]
	mov	dx,word ptr [bp+0ch]
	call	_normalize_far_ptr
	; compare normalized dst (in [bp+6]/[bp+8]) vs src (DX:AX)
	cmp	dx,word ptr [bp+8]
	ja	load_ptrs           ; src seg > dst seg -> forward copy
	jc	setup_back          ; src seg < dst seg -> backward copy
	cmp	ax,word ptr [bp+6]
	ja	load_ptrs           ; src off > dst off -> forward
	jc	setup_back          ; src off < dst off -> backward
	jmp	ret_dst             ; equal -> nothing to do

setup_back:
	std
	mov	word ptr cs:[g_slot_step],offset _normalize_far_ptr_flatten
	mov	word ptr cs:[g_slot_copy],offset _memcpy_far_backward
	; bias both pointers to the last byte (n-1) for a descending copy
	mov	ax,word ptr [bp+6]
	mov	dx,word ptr [bp+8]
	mov	bx,word ptr [bp+0eh]
	mov	cx,word ptr [bp+10h]
	sub	bx,1
	sbb	cx,0
	js	ret_dst             ; n == 0
	push	cx
	push	bx
	call	_far_ptr_add_offset
	mov	word ptr [bp+6],ax
	mov	word ptr [bp+8],dx
	mov	ax,word ptr [bp+0ah]
	mov	dx,word ptr [bp+0ch]
	pop	bx
	pop	cx
	call	_far_ptr_add_offset
load_ptrs:
	mov	ds,dx
	mov	si,ax
	mov	es,word ptr [bp+8]
	mov	di,word ptr [bp+6]

do_copy:
	sub	cx,cx
	mov	bx,7d00h
	cmp	word ptr [bp+10h],cx
	jnz	chunk               ; n high word != 0 -> full chunk
	mov	ax,word ptr [bp+0eh]
	cmp	ax,cx
	jz	ret_dst             ; n == 0
	cmp	ax,bx
	jg	chunk               ; n > 0x7d00 -> full chunk
	mov	bx,ax               ; else chunk = remaining n
chunk:
	mov	cx,bx
	; step src: AX=SI, DX=DS -> helper -> SI,DS
	mov	ax,si
	mov	dx,ds
	call	word ptr cs:[g_slot_step]
	mov	si,ax
	mov	ds,dx
	; step dst: AX=DI, DX=ES -> helper -> DI,ES
	mov	ax,di
	mov	dx,es
	call	word ptr cs:[g_slot_step]
	mov	di,ax
	mov	es,dx
	; copy CX bytes via the patched direction helper
	call	word ptr cs:[g_slot_copy]
	sub	ax,ax
	sub	word ptr [bp+0eh],bx
	sbb	word ptr [bp+10h],ax
	jmp	do_copy

ret_dst:
	mov	dx,word ptr [bp-2]
	mov	ax,word ptr [bp-4]
	cld
	pop	ds
	pop	di
	pop	si
	mov	sp,bp
	pop	bp
	retf
_fmemmove endp

; ----------------------------------------------------------------------------
; fmemcpy_far  (KRONDOR.EXE 180c:2887)
;
; Far memcpy: copies `count` bytes from far src pointer to far dst pointer.
; Both far pointers are normalized via normalize_far_ptr (register convention:
; DX:AX in/out, near call) before the copy. No-op when count == 0.
;
; Copy strategy:
;   1. If dst offset is odd, copy one byte to align, then decrement count.
;   2. SHR CX,1 to get word count; REP MOVSW to copy words.
;   3. RCL CX,1 to recover the trailing odd byte bit; REP MOVSB for it.
;
; Signature:
;   void fmemcpy_far(ulong dst, ulong src, uint count)
;     [BP+06] = dst offset
;     [BP+08] = dst segment
;     [BP+0A] = src offset
;     [BP+0C] = src segment
;     [BP+0E] = count
;
; normalize_far_ptr uses a register calling convention (DX:AX in/out, near
; call). RETF -> proc far; CALL to normalize_far_ptr -> intra-unit near.
; ----------------------------------------------------------------------------
_fmemcpy_far	proc far
	push	bp
	mov	bp,sp
	mov	cx,word ptr [bp+0Eh]	; CX = count
	jcxz	L_exit			; count == 0 -> skip everything
	push	si
	push	di
	push	ds
	mov	ax,word ptr [bp+0Ah]	; src offset
	mov	dx,word ptr [bp+0Ch]	; src segment
	call	_normalize_far_ptr	; DX:AX = normalize(src_seg:src_off)
	mov	ds,dx			; DS = normalized src segment
	mov	si,ax			; SI = normalized src offset
	mov	ax,word ptr [bp+6]	; dst offset
	mov	dx,word ptr [bp+8]	; dst segment
	call	_normalize_far_ptr	; DX:AX = normalize(dst_seg:dst_off)
	mov	es,dx			; ES = normalized dst segment
	mov	di,ax			; DI = normalized dst offset
	test	di,1			; is dst offset odd?
	jnc	L_shr			; if even, skip align byte
	movsb				; copy one byte to align to word boundary
	dec	cx			; count--
L_shr:					; 180c:28b4
	shr	cx,1			; CX = word count
	rep	movsw			; copy words
	rcl	cx,1			; CX = trailing odd byte (0 or 1)
	rep	movsb			; copy remaining byte (if any)
	pop	ds
	pop	di
	pop	si
L_exit:					; 180c:28bf  (JCXZ target)
	pop	bp
	retf
_fmemcpy_far	endp

; ----------------------------------------------------------------------------
; memset_far  (KRONDOR.EXE 180c:28c1)
;
; Far memset: fill `count` (count_lo:count_hi) bytes at far ptr offset:segment
; with byte `value`. Hand-asm: word-aligned STOSW.REP fill, chunked at 0x7D00
; bytes per pass, with a register-convention CALL to normalize_far_ptr to keep
; the working offset from wrapping the segment.
;
;   void memset_far(uint offset, uint segment, uchar value, uint count_lo, uint count_hi)
;     [BP+6]=offset [BP+8]=segment [BP+0Ah]=value [BP+0Ch]=count_lo [BP+0Eh]=count_hi
;
; Loads the dest far ptr into DX:AX and CALLs the register-convention
; normalize_far_ptr (180c:2722), then uses STOSB/STOSW.REP/RCL/JP.
; normalize_far_ptr reads its far pointer from DX:AX, not the stack: calling it
; via a stack (__cdecl) convention leaves DX:AX stale, so the helper returns a
; garbage pointer and the fill can land at 0:0 and wipe the IVT.
; ----------------------------------------------------------------------------
_memset_far	proc far
	push	bp
	mov	bp,sp
	push	si
	push	di
	cld
	mov	di,word ptr [bp+6]	; DI = offset
	mov	ax,word ptr [bp+8]
	mov	es,ax			; ES = segment
	mov	ax,word ptr [bp+0Ah]
	mov	ah,al			; AX = value:value (byte -> word)
	mov	si,ax			; SI = value word
L_chunk:				; 180c:28d6 -- top of the per-0x7D00 chunk loop
	sub	bx,bx
	mov	cx,7D00h		; max bytes this pass
	cmp	word ptr [bp+0Eh],bx	; count_hi == 0 ?
	jnz	L_clamp
	mov	ax,word ptr [bp+0Ch]	; count_lo
	cmp	ax,bx
	jz	L_done			; count_lo == 0 (and hi == 0) -> done
	cmp	ax,cx
	jg	L_clamp			; count_lo > 0x7D00 -> clamp to 0x7D00
	mov	cx,ax			; CX = count_lo
L_clamp:				; 180c:28ed
	mov	bx,cx			; BX = bytes filled this pass
	mov	ax,di
	mov	dx,es
	call	_normalize_far_ptr	; DX:AX = normalize(seg:off)
	mov	di,ax			; DI = normalized offset
	mov	es,dx			; ES = normalized segment
	mov	ax,si			; AX = value word
	cmp	cx,0Ah
	jl	L_tail			; small count -> byte fill only
	or	di,di
	jp	L_words			; (faithful: JP) skip the align byte
	stosb				; align: store one byte
	dec	cx
L_words:				; 180c:2907
	shr	cx,1
	rep	stosw			; fill words
	rcl	cl,1			; CL = trailing odd byte (0/1)
L_tail:					; 180c:290d
	rep	stosb			; fill remaining byte(s)
	sub	word ptr [bp+0Ch],bx	; count_lo -= bytes filled
	sbb	word ptr [bp+0Eh],cx	; count_hi -= borrow
	jmp	L_chunk
L_done:					; 180c:2917
	pop	di
	pop	si
	pop	bp
	retf
_memset_far	endp

; ----------------------------------------------------------------------------
; far_ptr_cmp  (KRONDOR.EXE 180c:291b)
;
; int far_ptr_cmp(void far *a, void far *b)
;
; Compares two far pointers in canonical (normalized) order.  Each pointer is
; passed through normalize_far_ptr (180c:2722) -- a register-convention
; helper that takes the far pointer in DX:AX and returns the normalized far
; pointer (seg + off>>4):(off & 0xf) in DX:AX, with NO stack args.  The two
; normalized 32-bit linear values are then compared unsigned (segment word
; first, then offset word): returns 1 if a > b, -1 if a < b, 0 if equal.
;
; The body performs two register-convention CALLs (MOV AX,[BP+N];
; MOV DX,[BP+M]; CALL normalize_far_ptr) -- normalize_far_ptr reads its args
; from AX/DX, not the stack.
; ----------------------------------------------------------------------------
_far_ptr_cmp proc far
	push	bp
	mov	bp,sp
	mov	ax,word ptr [bp+6]	; a.offset
	mov	dx,word ptr [bp+8]	; a.segment
	call	_normalize_far_ptr	; DX:AX = normalize(a)
	mov	bx,ax			; BX = a.off (normalized)
	mov	cx,dx			; CX = a.seg (normalized)
	mov	ax,word ptr [bp+0ah]	; b.offset
	mov	dx,word ptr [bp+0ch]	; b.segment
	call	_normalize_far_ptr	; DX:AX = normalize(b)
	cmp	cx,dx			; a.seg vs b.seg
	jc	L_below			; a < b
	ja	L_above			; a > b
	cmp	bx,ax			; a.off vs b.off
	ja	L_above			; a > b
L_below:
	sbb	ax,ax			; CF -> AX = -1 (a<b) else 0 (equal)
	pop	bp
	retf
L_above:
	mov	ax,1
	pop	bp
	retf
_far_ptr_cmp endp

; ----------------------------------------------------------------------------
; normalize_far_ptr_thunk  (KRONDOR.EXE 180c:2947)
;
; The __cdecl -> register-convention BRIDGE for normalize_far_ptr.
; normalize_far_ptr (180c:2722) is a register-convention helper: it takes the
; far pointer in DX:AX and returns the normalized far pointer in DX:AX, with
; NO stack args. C cannot express that call, so this thunk loads the
; (offset, segment) stack args into AX/DX, calls the register helper, and
; returns the normalized far pointer in DX:AX.
;
; The body is a register-convention near CALL to a sibling in the SAME code
; segment. The E8 near call must carry a SELF-RELATIVE FIXUPP: TASM records the
; EXTRN near call that way. Borland C++ 2.0's inline assembler instead records
; the external near reference as a SEGMENT-RELATIVE (offset) FIXUPP; the linker
; then writes the callee's absolute offset into the E8 displacement field, and
; the CPU (which treats E8 as self-relative) lands at next_ip+offset -- inside
; an unrelated function -> wild jump -> INT 6, taking down the far-ptr-normalize
; path used by every bak_load_chunk.
;
; Disassembly (180c:2947):
;   PUSH BP / MOV BP,SP / MOV AX,[BP+6] / MOV DX,[BP+8] / CALL near 2722 /
;   POP BP / RETF
; ----------------------------------------------------------------------------
_normalize_far_ptr_thunk proc far
	push	bp
	mov	bp,sp
	mov	ax,word ptr [bp+6]      ; offset
	mov	dx,word ptr [bp+8]      ; segment
	call	_normalize_far_ptr      ; DX:AX = normalize(DX:AX)
	pop	bp
	retf
_normalize_far_ptr_thunk endp

S180C_TEXT	ends
	end
