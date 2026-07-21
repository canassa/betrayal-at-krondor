; E_7878.ASM — empty overlay module (VROOMM overlay segment 7878)
;
; Occupies overlay segment 7878: the lone empty between the region encoder
; (rgnenc, 7735) and the windowed cursor loader (wcursor, 7879). Only the
; link-order POSITION is load-bearing.
;
; An empty, overlay-eligible CODE segment S7878_TEXT; TLINK /o emits the
; header-only resident stub + 16-byte pool slot itself.

	.286

S7878_TEXT	segment byte public use16 'CODE'
S7878_TEXT	ends

	end
