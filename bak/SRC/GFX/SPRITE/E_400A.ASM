; E_400A.ASM — empty overlay module (VROOMM overlay segment 400a)
;
; Occupies overlay segment 400a: second of three consecutive empties between the
; mdacon console-driver module (3ff1) and blit_sprite_aa_edges (400c). Only the
; link-order POSITION is load-bearing.
;
; An empty, overlay-eligible CODE segment S400A_TEXT; TLINK /o emits the
; header-only resident stub + 16-byte pool slot itself.

	.286

S400A_TEXT	segment byte public use16 'CODE'
S400A_TEXT	ends

	end
