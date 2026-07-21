; ============================================================================
; R3DDOT3.ASM  --  dot-product leaf helpers
;
; r3d_dot3_long: signed 3-element dot product of two 16-bit vectors,
; 32-bit result in DX:AX (register convention: AX and BX carry the vector
; pointers). r3d_dot3_long_far: the far-callable thunk around it. Used
; for back-face tests, face shading, and mesh-part depth sorting.
;
; One of the four source files of segment S233E_TEXT -- see R3D.ASM for
; the segment layout and reading conventions; the link order is fixed by
; KRONDOR.RSP.
; ============================================================================

.286

S233E_TEXT	segment word public use16 'CODE'
	assume cs:S233E_TEXT, ds:S233E_TEXT

; ============================================================================
; _r3d_dot3_long
;
; Signed 3D dot product of two short[3] vectors, accumulated into a 32-bit long.
;
; C equivalent:
;   long near r3d_dot3_long(int *a, int *b)
;   {
;       return (long)a[0] * b[0] + (long)a[1] * b[1] + (long)a[2] * b[2];
;   }
; ============================================================================
	public _r3d_dot3_long
_r3d_dot3_long:
	push SI
	push DI
	mov SI,AX
	mov DI,BX
	lodsw
	mov DX, word ptr [DI]
	imul DX
	mov BX,AX
	mov CX,DX
	lodsw
	mov DX, word ptr [DI+2]
	imul DX
	add BX,AX
	adc CX,DX
	lodsw
	mov DX, word ptr [DI+4]
	imul DX
	add AX,BX
	adc DX,CX
	pop DI
	pop SI
	ret

; ============================================================================
; _r3d_dot3_long_far
;
; Far-callable thunk that forwards to the near r3d_dot3_long 3-element signed dot product,
; returning the 32-bit result.
;
; C equivalent:
;   long far r3d_dot3_long_far(int *pVecA, int *pVecB)
;   {
;       return r3d_dot3_long(pVecA, pVecB);
;   }
; ============================================================================
@pVecA equ word ptr [bp+6]
@pVecB equ word ptr [bp+8]
	public _r3d_dot3_long_far
_r3d_dot3_long_far:
	push BP
	mov BP,SP
	mov AX, @pVecA
	mov BX, @pVecB
	call _r3d_dot3_long
	pop BP
	retf

S233E_TEXT	ends

	end
