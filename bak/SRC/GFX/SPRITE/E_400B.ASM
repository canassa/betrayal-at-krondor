; E_400B.ASM — empty overlay module (VROOMM overlay segment 400b)
;
; Occupies overlay segment 400b: third of three consecutive empties between the
; mdacon console-driver module (3ff1) and blit_sprite_aa_edges (400c). Only the
; link-order POSITION is load-bearing.
;
; An empty, overlay-eligible CODE segment S400B_TEXT; TLINK /o emits the
; header-only resident stub + 16-byte pool slot itself.

	.286

S400B_TEXT	segment byte public use16 'CODE'
S400B_TEXT	ends

	end
