; D_320A.ASM — data/BSS-only resident TU anchor (segment 320a, before AUDLOAD.C)
;
; The FBOV _SEGTABLE_ carries a zero-length resident CODE record here, before
; AUDLOAD.C's record in segment 320a. TLINK emits one _EXEINFO_ record per
; distinctly-named final segment, so without this module the FBOV table is 8
; bytes short and everything below it (stub band, DGROUP) para-shifts. Only the
; link-order POSITION and COUNT are load-bearing.
;
; The empty WORD-aligned CODE segment's word alignment is LOAD-BEARING: TLINK
; aligns even a zero-length segment, so the single 0x00 pad before the following
; C unit comes from THIS segment's word A-field, and the C unit's own _TEXT
; stays at bcc's byte default. The segment name must NOT be the unit's
; S320A_TEXT — that would public-combine into the unit's record instead of
; emitting its own.

	.286

D320A_TEXT	segment word public use16 'CODE'
D320A_TEXT	ends

	end
