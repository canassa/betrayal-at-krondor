; D_32C8.ASM — data/BSS-only resident TU anchor (segment 32c8, before MIDI.ASM)
;
; The FBOV _SEGTABLE_ carries a zero-length resident CODE record here, the
; single empty immediately before MIDI.ASM's record in segment 32c8. TLINK
; emits one _EXEINFO_ record per distinctly-named final segment, so without
; this module the FBOV table is 8 bytes short and everything below it (stub
; band, DGROUP) para-shifts. Only the link-order POSITION and COUNT are
; load-bearing.
;
; An empty byte-aligned CODE segment. The segment name must NOT be the
; unit's S32C8_TEXT — that would public-combine into the unit's record
; instead of emitting its own.

	.286

D32C8_TEXT	segment byte public use16 'CODE'
D32C8_TEXT	ends

	end
