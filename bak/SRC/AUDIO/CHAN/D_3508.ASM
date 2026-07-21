; D_3508.ASM — data/BSS-only resident TU anchor (segment 3508, before SFXEVENT.C)
;
; The FBOV _SEGTABLE_ carries a zero-length resident CODE record here, before
; SFXEVENT.C's record in segment 3508. TLINK emits one _EXEINFO_ record per
; distinctly-named final segment, so without this module the FBOV table is 8
; bytes short and everything below it (stub band, DGROUP) para-shifts. Only the
; link-order POSITION and COUNT are load-bearing.
;
; The empty WORD-aligned CODE segment's word alignment is LOAD-BEARING: TLINK
; aligns even a zero-length segment, so the single 0x00 pad before the following
; C unit comes from THIS segment's word A-field, and the C unit's own _TEXT
; stays at bcc's byte default. The segment name must NOT be the unit's
; S3508_TEXT — that would public-combine into the unit's record instead of
; emitting its own.

	.286

D3508_TEXT	segment word public use16 'CODE'
D3508_TEXT	ends

	end
