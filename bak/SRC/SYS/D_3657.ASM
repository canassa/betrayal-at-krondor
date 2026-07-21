; D_3657.ASM — data/BSS-only resident TU anchor (segment 3657, before EMSDET.C)
;
; The FBOV _SEGTABLE_ carries a zero-length resident CODE record here, before
; EMSDET.C's record in segment 3657. TLINK emits one _EXEINFO_ record per
; distinctly-named final segment, so without this module the FBOV table is 8
; bytes short and everything below it (stub band, DGROUP) para-shifts. Only the
; link-order POSITION and COUNT are load-bearing.
;
; The empty WORD-aligned CODE segment's word alignment is LOAD-BEARING: TLINK
; aligns even a zero-length segment, so the single 0x00 pad before the following
; C unit comes from THIS segment's word A-field, and the C unit's own _TEXT
; stays at bcc's byte default. The segment name must NOT be the unit's
; S3657_TEXT — that would public-combine into the unit's record instead of
; emitting its own.

	.286

D3657_TEXT	segment word public use16 'CODE'
D3657_TEXT	ends

	end
