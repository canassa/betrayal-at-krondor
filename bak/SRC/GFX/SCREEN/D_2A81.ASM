; D_2A81.ASM — data/BSS-only resident TU anchor (segment 2a81, before SCREEN.C)
;
; Emits a zero-length resident CODE segment, immediately before SCREEN.C in
; segment 2a81. Its link-order POSITION and COUNT are load-bearing: TLINK emits
; one FBOV _EXEINFO_ record per distinctly-named final segment, so without this
; module the FBOV table is 8 bytes short and everything below it (stub band,
; DGROUP) para-shifts.
;
; The empty CODE segment is WORD-aligned: TLINK aligns even a zero-length
; segment, so the single 0x00 pad before the following C unit comes from this
; segment's word A-field. The segment name must NOT be S2A81_TEXT — that would
; public-combine into SCREEN.C's record instead of emitting its own.

	.286

D2A81_TEXT	segment word public use16 'CODE'
D2A81_TEXT	ends

	end
