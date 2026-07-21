; E_4009.ASM — empty overlay module (VROOMM overlay segment 4009)
;
; Occupies overlay segment 4009: first of three consecutive empties between the
; mdacon console-driver module (3ff1) and blit_sprite_aa_edges (400c). Only the
; link-order POSITION is load-bearing.
;
; An empty, overlay-eligible CODE segment S4009_TEXT; TLINK /o emits the
; header-only resident stub + 16-byte pool slot itself.

	.286

S4009_TEXT	segment byte public use16 'CODE'
S4009_TEXT	ends

	end
