;; PALBLEND.ASM -- palette blend colour-lookup module (seg 168f).
;; Single member: palette_blend_lookup (168f:000c, 213 bytes).
;;
;; Blends two palette colours and returns the nearest matching palette index.
;; Averages the RGB triplets for palette[idx_a] and palette[idx_b] from the
;; far buffer g_pAaPaletteBuf (seg:off far ptr stored at DGROUP+0x4c46),
;; then linearly scans entries 0x10..0xe6 for the slot with the smallest
;; sum-of-absolute-differences below an adaptive threshold.
;; Returns the matching index, or -1 if best match total error > 0x27.
;;
;; The SAD inner loop uses a carry-flag abs -- `sub al,es:[si]; jnc; neg al`,
;; reusing the SUB's borrow as the negate test and keeping the abs byte in AL
;; with a single `xor ah,ah` shared across all three RGB components. The RGB
;; average `(pal[a]+pal[b])>>1` widens two far byte reads with 16-bit
;; `movzx ax,es:[bx]`. The epilogue is a manual `add sp,8; pop bp`.
;;
;; The far-pointer load `MOV DI,[off]; MOV AX,[seg]; MOV ES,AX` loads the offset
;; into DI but then DEAD-drops it and indexes the palette from segment:0
;; (es:[idx*3], FP_OFF ignored) -- a seg:0000-buffer optimization.
;;
;; Registers in the main loop:
;;   CX = i (loop counter, 0x10..0xe6)
;;   DX = best_total (best sum-of-abs-diffs seen so far, starts 0x300)
;;   DI = threshold (adaptive; starts 0x12, drops when a better match found)
;;   SI = i * 3 (current palette entry byte offset, recomputed each iteration)
;;   BX = temp: abs-diff accumulator within an iteration
;;   AL = temp: per-component abs-diff byte; AH = 0 (XOR AH,AH once per iter)
;; Stack frame (sub sp, 8):
;;   [BP-2] = avg_r  (byte)
;;   [BP-4] = avg_g  (byte)
;;   [BP-6] = avg_b  (byte)
;;   [BP-8] = local_a / best_idx (word, returned at end)

	.386

	extrn	_g_pAaPaletteBuf:dword	; DGROUP+0x4c46  far ptr to palette buffer (declared ulong)

	_DATA	segment word public 'DATA'
	_DATA	ends
	_BSS	segment word public 'BSS'
	_BSS	ends
	DGROUP	group _DATA, _BSS

; WORD-aligned: the original word-aligns this module (DISTDIR.ASM ends at the odd
; load-module byte 0x68fb, so TLINK emits one 0x00 pad to start us at the even 0x68fc);
; a BYTE-aligned _TEXT drops that pad and shifts the whole resident tail by -1.
S168F_TEXT	segment word public use16 'CODE'
	assume	cs:S168F_TEXT, ds:DGROUP

	public	_palette_blend_lookup

;; int palette_blend_lookup(uint idx_a, uint idx_b)
;; [BP+6] = idx_a
;; [BP+8] = idx_b
_palette_blend_lookup	proc far
	push	bp
	mov	bp,sp
	sub	sp,8h
	mov	bx,word ptr [bp+6h]	; BX = idx_a
	mov	cx,word ptr [bp+8h]	; CX = idx_b
	and	bx,0ffh			; BX = idx_a & 0xFF
	and	cx,0ffh			; CX = idx_b & 0xFF
	push	si
	push	di
	mov	di,word ptr [_g_pAaPaletteBuf]		; DI = palette offset (low word of far ptr)
	mov	ax,word ptr [_g_pAaPaletteBuf+2]	; AX = palette segment (high word)
	mov	es,ax				; ES = palette segment
	mov	ax,bx
	shl	ax,1h
	add	bx,ax				; BX = idx_a * 3
	mov	si,cx
	mov	ax,si
	shl	ax,1h
	add	si,ax				; SI = idx_b * 3
	movzx	ax,byte ptr es:[bx]		; AX = palette[idx_a*3]   (R component)
	movzx	cx,byte ptr es:[si]		; CX = palette[idx_b*3]
	add	ax,cx
	shr	ax,1h
	mov	byte ptr [bp-2h],al		; avg_r = (R_a + R_b) >> 1
	movzx	ax,byte ptr es:[bx+1h]		; AX = palette[idx_a*3+1] (G component)
	movzx	cx,byte ptr es:[si+1h]		; CX = palette[idx_b*3+1]
	add	ax,cx
	shr	ax,1h
	mov	byte ptr [bp-4h],al		; avg_g = (G_a + G_b) >> 1
	movzx	ax,byte ptr es:[bx+2h]		; AX = palette[idx_a*3+2] (B component)
	movzx	cx,byte ptr es:[si+2h]		; CX = palette[idx_b*3+2]
	add	ax,cx
	shr	ax,1h
	mov	byte ptr [bp-6h],al		; avg_b = (B_a + B_b) >> 1
	mov	word ptr [bp-8h],0h		; best_idx = 0
	mov	dx,300h				; 0300h best_total init: SAD sentinel max
	mov	cx,10h				; i = 0x10
	mov	di,12h				; threshold = 0x12

L_6968:					;; loop body (one iteration per palette entry)
	mov	si,cx
	shl	si,1h
	add	si,cx				; SI = i * 3
	xor	ah,ah
	mov	al,byte ptr [bp-2h]		; AL = avg_r
	sub	al,byte ptr es:[si]		; AL = avg_r - entry_r  (carry if avg_r < entry_r)
	jnc	L_697a
	neg	al				; AL = abs(diff_r)
L_697a:
	cmp	ax,di				; abs(diff_r) vs threshold
	jnc	L_69b8				; >= threshold -> skip entry
	mov	bx,ax				; BX = diff_r
	mov	al,byte ptr [bp-4h]		; AL = avg_g
	sub	al,byte ptr es:[si+1h]		; AL = avg_g - entry_g
	jnc	L_698b
	neg	al
L_698b:
	cmp	ax,di				; abs(diff_g) vs threshold
	jnc	L_69b8
	add	bx,ax				; BX += diff_g
	mov	al,byte ptr [bp-6h]		; AL = avg_b
	sub	al,byte ptr es:[si+2h]		; AL = avg_b - entry_b
	jnc	L_699c
	neg	al
L_699c:
	cmp	ax,di				; abs(diff_b) vs threshold
	jnc	L_69b8
	add	bx,ax				; BX = total diff
	cmp	bx,dx				; total < best_total?
	jnc	L_69b8
	mov	ax,cx				; AX = i (for early return)
	cmp	bx,2h				; total <= 2 -> very close match, return now
	jbe	L_69ca
	mov	dx,bx				; best_total = total
	mov	word ptr [bp-8h],cx		; best_idx = i
	cmp	bx,di				; total < threshold?
	jnc	L_69b8
	mov	di,bx				; threshold = total (tighten)
L_69b8:
	inc	cx				; i++
	cmp	cx,0e7h
	jnz	L_6968				; loop until i == 0xe7
	mov	ax,word ptr [bp-8h]		; AX = best_idx
	cmp	dx,28h				; best_total > 0x27?
	jc	L_69ca
	mov	ax,0ffffh			; return -1
L_69ca:
	pop	di
	pop	si
	add	sp,8h
	pop	bp
	retf
_palette_blend_lookup	endp

S168F_TEXT	ends
	end
