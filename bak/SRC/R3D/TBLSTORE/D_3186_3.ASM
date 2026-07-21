; D_3186_3.ASM — data/BSS-only resident TU anchor (segment 3186, before SHAPEBLD.C)
;
; The FBOV _SEGTABLE_ carries a zero-length resident CODE record here, empty
; 4 of 4 before SHAPEBLD.C's record in segment 3186. TLINK emits one _EXEINFO_
; record per distinctly-named final segment, so without this module the FBOV
; table is 8 bytes short and everything below it (stub band, DGROUP) para-shifts.
; Only the link-order POSITION and COUNT are load-bearing.
;
; An empty byte-aligned CODE segment. The segment name must NOT be the unit's
; S3186_TEXT — that would public-combine into the unit's record instead of
; emitting its own.

	.286

D3186_3_TEXT	segment byte public use16 'CODE'
D3186_3_TEXT	ends

	end
