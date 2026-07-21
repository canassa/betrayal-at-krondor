; D_2148.ASM — data/BSS-only resident TU anchor (segment 2148, before WORLDHIT.C)
;
; The FBOV _SEGTABLE_ carries a zero-length resident CODE record here, the
; single empty before WORLDHIT.C's record in segment 2148. TLINK emits one
; _EXEINFO_ record per distinctly-named final segment, so without this module
; the FBOV table is 8 bytes short and everything below it (stub band, DGROUP)
; para-shifts. Only the link-order POSITION and COUNT are load-bearing.
;
; An empty byte-aligned CODE segment. The segment name must NOT be the unit's
; S2148_TEXT — that would public-combine into the unit's record instead of
; emitting its own.

	.286

D2148_TEXT	segment byte public use16 'CODE'
D2148_TEXT	ends

	end
