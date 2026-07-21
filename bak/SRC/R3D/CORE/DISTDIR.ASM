; ============================================================================
; DISTDIR.ASM -- KRONDOR.EXE segment 0x1678 distance/direction math band.
;
; One module: three contiguous routines that abut exactly and share the 9-byte
; CS-resident shift LUT at CS:0008h:
;   1678:0011  distdir_vec3_distance_dir_approx  (230 B)  0011+E6 = 00F7
;   1678:00f7  distdir_octagonal_distance        ( 74 B)  00F7+4A = 0141
;   1678:0141  distdir_octagonal_distance_dxdy   ( 58 B)  0141+3A = 017B
;
; Register conventions across the three: the two routines that take stack args
; address them frameless via `mov bx,sp` with no BP frame; deltas are held live
; in EDX/ECX (and the 3*min scratch in EBX) rather than spilled; the first routine
; packs AH/AL as two independent byte fields (quadrant / octant).
;
; The 9-byte CS-resident shift table (loaded at CS:0008h in the final segment):
;   index  0  1  2  3  4  5  6  7  8
;   shift  4  5  6  7  8  8  8  8  8
; The table is loaded at CS:0008h (the overlay minoff for this segment is 8) and
; accessed at runtime via the disp16 `CS:[si + 8]`.
;
; Build: one obj (DISTDIR.OBJ) covers all three functions (369 B whole-segment span).
; ============================================================================

	.386

	extrn	_g_nVec3DistResult:dword	; DGROUP+028ah

; --- DGROUP / segment declarations -----------------------------------------
_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

; WORD-aligned: the original word-aligns this module (RESBLIT.C ends at the odd
; load-module byte 0x6787, so TLINK emits one 0x00 pad to start us at the even 0x6788);
; a BYTE-aligned _TEXT drops that pad and shifts the whole resident tail by -1.
S1678_TEXT	segment word public use16 'CODE'
	assume	cs:S1678_TEXT, ds:DGROUP

	public	_distdir_vec3_distance_dir_approx
	public	_distdir_octagonal_distance
	public	_distdir_octagonal_distance_dxdy

; --- CS-resident shift lookup table (loaded at CS:0008h in the final segment) -
; Shift amounts for angular-difference values 0..8, accessed at runtime as
; `MOV CL, byte ptr CS:[SI + 8]`. The FBOV minoff for seg 1678 is 8: the overlay's
; owned content STARTS at segment offset 8 (the 8 bytes at CS:00h..07h are the
; prior overlay's / 160a's tail, aliased, NOT owned by 1678). So this module emits
; NO leading bytes -- the table is its first content byte -- and the loader places
; it at CS:08h via minoff. The table is a same-segment self-reference, so
; `g_distdir_shift_lut` resolves to its linked segment offset (obj offset 0 +
; base_off 8 = 8), and the disp16 `CS:[SI + 8]` access addresses it directly.
g_distdir_shift_lut	label	byte
	db	4, 5, 6, 7, 8, 8, 8, 8, 8	; loaded at CS:08h..10h: shift amounts for dir-diff 0..8

; ============================================================================
; ulong distdir_vec3_distance_dir_approx(long *a, ulong b, unsigned short dir_in)
;   [BP+6]  = a       (NEAR pointer to long[2]: a[0]=x, a[1]=y)
;   [BP+8]  = b       (FAR pointer stored as ulong; b[0]=x, b[1]=y)
;   [BP+C]  = dir_in  (high byte bits 15-8: 4-bit direction field, XOR-inverted)
; Fast 2D octagonal distance + 16-direction estimate between two 32-bit points.
; Stores one of three values to g_nVec3DistResult by distance magnitude.
; ============================================================================
_distdir_vec3_distance_dir_approx	proc far
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	si,word ptr [bp + 6]		; SI = a (near ptr)
	les	di,[bp + 8]			; ES:DI = b (far ptr)
	mov	edx,dword ptr es:[di]		; edx = b->x
	sub	edx,dword ptr [si]		; edx = b->x - a->x  (dx)
	mov	ecx,dword ptr es:[di + 4]	; ecx = b->y
	sub	ecx,dword ptr [si + 4]		; ecx = b->y - a->y  (dy)
	cmp	edx,0
	jge	short v3_dx_pos			; if dx >= 0, skip negate
	neg	edx				; dx = |dx|
	mov	ah,3				; quadrant: dx<0 => Q2 or Q3
	cmp	ecx,0
	jge	short v3_check_oct		; dy >= 0: quadrant = 3 (dx<0, dy>=0)
	neg	ecx				; dy = |dy|
	mov	ah,2				; quadrant: dx<0, dy<0 => Q2
	jmp	short v3_check_oct
v3_dx_pos:
	mov	ah,0				; quadrant: dx>=0 => Q0 or Q1
	cmp	ecx,0
	jge	short v3_check_oct		; dy >= 0: quadrant = 0 (dx>=0, dy>=0)
	neg	ecx				; dy = |dy|
	mov	ah,1				; quadrant: dx>=0, dy<0 => Q1
v3_check_oct:
	cmp	ecx,edx				; |dy| vs |dx|
	jl	short v3_dx_bigger		; |dx| > |dy|: X axis dominates
; |dy| >= |dx|: Y axis dominates
	mov	ebx,edx
	shl	ebx,1				; ebx = 2*|dx|
	mov	al,1				; octant-in-quadrant = 1 (diagonal-ish Y)
	cmp	ecx,ebx				; |dy| vs 2*|dx|
	jle	short v3_oct_done		; |dy| <= 2*|dx|: al=1
	mov	al,0				; |dy| > 2*|dx|: purely Y, al=0
	jmp	short v3_oct_done
v3_dx_bigger:
	mov	ebx,ecx
	shl	ebx,1				; ebx = 2*|dy|
	mov	al,2				; octant-in-quadrant = 2 (diagonal-ish X)
	cmp	edx,ebx				; |dx| vs 2*|dy|
	jle	short v3_oct_done		; |dx| <= 2*|dy|: al=2
	mov	al,3				; |dx| > 2*|dy|: purely X, al=3
v3_oct_done:
; AH=quadrant (0-3), AL=octant-in-quadrant (0-3)
; Fold quadrant + octant into 16-point direction (BL):
	cmp	ah,0
	jnz	short v3_q1
	mov	bl,al				; Q0: dir = al (0..3)
	jmp	short v3_dir_done
v3_q1:
	cmp	ah,1
	jnz	short v3_q2
	mov	bl,7
	sub	bl,al				; Q1: dir = 7 - al (4..7)
	jmp	short v3_dir_done
v3_q2:
	cmp	ah,2
	jnz	short v3_q3
	mov	bl,8
	add	bl,al				; Q2: dir = 8 + al (8..11)
	jmp	short v3_dir_done
v3_q3:
	mov	bl,0fh
	sub	bl,al				; Q3: dir = 15 - al (12..15)
v3_dir_done:
; Compare BL (computed direction 0-15) with inverted/shifted high byte of dir_in
	mov	ax,word ptr [bp + 0ch]		; ax = dir_in
	xor	ax,0ffffh			; invert all bits
	shr	ax,0ch				; ax = bits 15-12 shifted to bits 3-0
	sub	al,bl				; diff = rotated_dir_in - computed_dir
	jge	short v3_abs			; if diff >= 0, already positive
	neg	al				; diff = |diff|
v3_abs:
	cmp	al,8
	jle	short v3_no_wrap		; if diff <= 8, no wrap needed
	sub	al,0fh
	neg	al				; wrap: diff = 15 - diff (circular angular dist)
v3_no_wrap:
; Compute octagonal distance: max(|dx|,|dy|) + 3*min(|dx|,|dy|)/8
; (ECX = |dy|, EDX = |dx| -- still valid from quadrant detection above)
	cmp	ecx,edx				; |dy| vs |dx|
	jle	short v3_min_max_done		; ECX <= EDX: EDX=max, ECX=min already
	xchg	edx,ecx				; swap so EDX=max, ECX=min
v3_min_max_done:
	mov	ebx,ecx				; ebx = min
	shl	ecx,1
	add	ecx,ebx				; ecx = 3*min
	shr	ecx,3				; ecx = 3*min/8
	add	edx,ecx				; edx = max + 3*min/8  (distance)
; Store g_nVec3DistResult based on distance magnitude:
	mov	ebx,20000000h			; default: "infinity" sentinel
	cmp	edx,1000000h
	jge	short v3_done			; signed >= 1000000h: EBX=sentinel, store and return
	movzx	si,al				; SI = angular diff (0..8)
	mov	ebx,edx				; EBX = distance
	jc	short v3_done			; unsigned < 1000000h: store distance as-is
	; huge unsigned distance (> 7FFFFFFFh): apply shift from CS table
	mov	cl,byte ptr cs:[si + g_distdir_shift_lut]	; CL = shift amount (table loaded at CS:0008h)
	shl	ebx,cl				; EBX = distance << shift
v3_done:
	mov	dword ptr [_g_nVec3DistResult],ebx	; store result
	mov	eax,edx				; EAX = distance (low 32 bits)
	shr	edx,10h			; EDX:AX = distance (DX = high 16 bits)
	pop	di
	pop	si
	pop	bp
	retf
_distdir_vec3_distance_dir_approx	endp

; ============================================================================
; int distdir_octagonal_distance(long *p1, long *p2)
; Fast octagonal approximation of Euclidean distance between two long-coordinate
; points {x,y}: max(|dx|,|dy|) + 3*min(|dx|,|dy|)/8. Frameless; holds both longs
; live in EDX/ECX, addressing params through `MOV BX,SP` with no BP frame.
; ============================================================================
_distdir_octagonal_distance	proc far
	mov	bx,sp
	push	si
	push	di
	mov	si,word ptr [bx + 4]		; si = p1
	mov	di,word ptr [bx + 6]		; di = p2
	mov	edx,dword ptr [di]		; edx = *p2
	sub	edx,dword ptr [si]		; edx = *p2 - *p1
	jge	short oc_dx_pos
	neg	edx				; edx = |*p2 - *p1|
oc_dx_pos:
	mov	ecx,dword ptr [di + 4]		; ecx = p2[1]
	sub	ecx,dword ptr [si + 4]		; ecx = p2[1] - p1[1]
	jge	short oc_dy_pos
	neg	ecx				; ecx = |p2[1] - p1[1]|
oc_dy_pos:
	cmp	edx,ecx
	jge	short oc_have_max		; if edx >= ecx, edx=max, ecx=min
	xchg	edx,ecx				; else swap so edx=max, ecx=min
oc_have_max:
	mov	ebx,ecx				; ebx = min
	shl	ecx,1
	add	ecx,ebx				; ecx = 3*min
	shr	ecx,3				; ecx = 3*min / 8
	add	edx,ecx				; edx = max + 3*min/8
	mov	eax,edx
	and	eax,0ffffh			; AX = low 16 bits (int result)
	shr	edx,10h				; DX = high 16 bits
	pop	di
	pop	si
	retf
_distdir_octagonal_distance	endp

; ============================================================================
; long distdir_octagonal_distance_dxdy(long dx, long dy)
; Same octagonal approximation, but takes the two long deltas directly on the
; stack: max(|dx|,|dy|) + 3*min(|dx|,|dy|)/8. Returns the long in DX:AX.
; Frameless; keeps dx/dy live in EDX/ECX and the 3*min scratch in EBX.
; ============================================================================
_distdir_octagonal_distance_dxdy	proc far
	mov	bx,sp
	mov	edx,dword ptr [bx + 4]		; dx
	mov	ecx,dword ptr [bx + 8]		; dy
	or	edx,edx
	jge	short dd_dx_pos
	neg	edx				; dx = -dx
dd_dx_pos:
	or	ecx,ecx
	jge	short dd_dy_pos
	neg	ecx				; dy = -dy
dd_dy_pos:
	cmp	ecx,edx
	jle	short dd_have_max		; if dy <= dx, max=edx, min=ecx
	xchg	edx,ecx				; else swap so edx=max, ecx=min
dd_have_max:
	mov	ebx,ecx				; ebx = min
	shl	ecx,1
	add	ecx,ebx				; ecx = 3*min
	shr	ecx,3				; ecx = 3*min / 8
	add	edx,ecx				; edx = max + 3*min/8
	mov	eax,edx
	shr	edx,10h				; DX:AX = result
	retf
_distdir_octagonal_distance_dxdy	endp

S1678_TEXT	ends
	end
