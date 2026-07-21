; ============================================================================
; RAND.ASM -- subtractive lagged-Fibonacci pseudo-random number generator
;
; Provides the game's core PRNG, satisfying two C prototypes:
;   int  rand(void)                -- draw the next pseudo-random word
;   void _rand_reset_indices(void) -- reseed the two ring cursors
;
; A lagged-Fibonacci generator produces each output from two earlier outputs
; held in a circular "state ring". Two cursors, lag J and lag I, index into a
; 56-word ring (_g_randState). Each draw combines the words at J and I, stores
; the result back into the ring at I (so the ring evolves), and then steps
; both cursors backward one slot, wrapping around when they run off the front.
; This variant *adds* the two lagged words (a common integer lagged-Fibonacci
; form); the seed ring below is a fixed table, so the sequence is deterministic
; from a cold start until _rand_reset_indices runs.
;
; The two cursors are stored as *byte* offsets into the word ring, not element
; indices: a cursor value of 0x6e addresses ring slot 55 (55 * 2 = 0x6e). The
; step is therefore -2 (one word), and the wrap target is 0x6e.
; ============================================================================

	.286
	locals

; ----------------------------------------------------------------------------
; PRNG state (this module's _DATA)
;
; All generator state lives here: the two cursors, the last drawn value, and
; the 56-word ring. It is initialized data (a fixed seed ring), so it lands
; in _DATA, not _BSS.
; ----------------------------------------------------------------------------
_DATA	segment word public 'DATA'
	public	_g_randPosJ
	public	_g_randPosI
	public	_g_randLast
	public	_g_randState

_g_randPosJ	dw	0			; lag-J cursor: byte offset into the ring
_g_randPosI	dw	0			; lag-I cursor: byte offset into the ring
_g_randLast	dw	0			; most recent draw (rand's return value)

; The 56-word state ring. Each draw reads two of these words and overwrites
; one; over time the whole ring churns. These are the initial seed values.
_g_randState	dw	0dd23h, 09533h, 0f3c8h, 04bc2h, 0f7e2h, 0a3dfh, 0aa70h, 060aah
	dw	0144bh, 08948h, 01928h, 06b0dh, 09e0bh, 0fbf1h, 08607h, 0465dh
	dw	0eaf4h, 069fdh, 06c44h, 01b27h, 0db71h, 0e38fh, 0abb4h, 0dc47h
	dw	00fdeh, 04d8eh, 0fc7dh, 08d38h, 05048h, 0e36fh, 0aa22h, 02f26h
	dw	043fah, 0b5a5h, 020ebh, 0ed85h, 0f5c3h, 0819fh, 02d9ch, 0b26dh
	dw	0e92bh, 097d5h, 03da1h, 089edh, 01bf4h, 074b5h, 0002ch, 0d37dh
	dw	03b08h, 00df5h, 0f27eh, 0c270h, 02589h, 02e8bh, 06352h, 0da2dh
_DATA	ends

_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group	_DATA, _BSS

_TEXT	segment byte public use16 'CODE'
	assume	cs:_TEXT, ds:DGROUP

	public	_rand
	public	__rand_reset_indices

; ----------------------------------------------------------------------------
; int rand(void)
;   Entry:    (none) -- all state in this module's DGROUP _DATA
;   Exit:     AX = next pseudo-random word (also cached in _g_randLast)
;   Trashes:  AX BX  (SI saved+restored)
;
; Draws one word: sum the ring words at cursors J and I, store the sum back at
; I, cache it as the result, then retreat both cursors one word (wrapping).
; ----------------------------------------------------------------------------
_rand	proc far
	push	si

	; Load the two lag cursors into index registers. J goes in BX (a
	; caller-saved scratch reg, so no save needed) and I in SI (callee-saved,
	; hence the surrounding PUSH SI / POP SI). Each transfer routes through AX
	; because a memory-to-index-register move isn't a single-instruction form
	; here.
	mov	ax,word ptr [_g_randPosJ]
	mov	bx,ax				; BX = J cursor
	mov	ax,word ptr [_g_randPosI]
	mov	si,ax				; SI = I cursor

	; draw = ring[J] + ring[I]; write it back at ring[I] and cache as result.
	; The cursors are byte offsets, so they index the word ring directly.
	mov	ax,word ptr [bx + _g_randState]
	add	ax,word ptr [si + _g_randState]
	mov	word ptr [si + _g_randState],ax
	mov	word ptr [_g_randLast],ax

	; Retreat J one word. SUB sets the sign flag; JNS then reads that same
	; flag, so the subtraction doubles as the "did it go negative?" test.
	; On underflow, wrap to the last ring slot (offset 0x6e = slot 55).
	sub	bx,2
	jns	short @@store_j
	mov	bx,6eh				; wrap J to ring slot 55
@@store_j:
	mov	ax,bx
	mov	word ptr [_g_randPosJ],ax	; store updated J cursor

	; Retreat I one word, same wrap-on-underflow handling as J above.
	sub	si,2
	jns	short @@store_i
	mov	si,6eh				; wrap I to ring slot 55
@@store_i:
	mov	ax,si
	mov	word ptr [_g_randPosI],ax	; store updated I cursor

	; Return the cached draw in AX.
	mov	ax,word ptr [_g_randLast]
	pop	si
	retf
_rand	endp

; ----------------------------------------------------------------------------
; void _rand_reset_indices(void)
;   Entry:    (none)
;   Exit:     (none) -- cursors reseeded in _DATA
;   Trashes:  AX
;
; Reseeds the two lag cursors to their starting offsets, restarting the
; generator's walk over the ring without touching the ring contents.
; ----------------------------------------------------------------------------
__rand_reset_indices	proc far
	mov	ax,30h
	mov	word ptr [_g_randPosJ],ax	; J = offset 0x30 (ring slot 24)
	mov	ax,6eh
	mov	word ptr [_g_randPosI],ax	; I = offset 0x6e (ring slot 55)
	retf
__rand_reset_indices	endp

_TEXT	ends
	end
