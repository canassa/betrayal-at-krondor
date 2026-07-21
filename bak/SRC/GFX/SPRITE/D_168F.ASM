; D_168F.ASM — data/BSS-only resident TU anchor (segment 168f, before PALBLEND.ASM)
;
; The FBOV _SEGTABLE_ carries a zero-length resident CODE record here, the
; single empty before PALBLEND.ASM's record in segment 168f. TLINK emits one
; _EXEINFO_ record per distinctly-named final segment, so without this module
; the FBOV table is 8 bytes short and everything below it (stub band, DGROUP)
; para-shifts. Only the link-order POSITION and COUNT are load-bearing.
;
; An empty WORD-aligned CODE segment. WORD (not BYTE): the empty record sits at
; the even start of the unit's code (one byte past the odd end of the previous
; segment). The segment name must NOT be the unit's S168F_TEXT — that would
; public-combine into the unit's record instead of emitting its own.

	.286

D168F_TEXT	segment word public use16 'CODE'
D168F_TEXT	ends

	end
