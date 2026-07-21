; D_233E.ASM -- data/BSS-only TU anchor (segment 233e, before R3D.ASM)
;
; Contributes a zero-length resident CODE record immediately before R3D.ASM's
; record in segment 233e. TLINK emits one _EXEINFO_ record per distinctly-named
; final segment; this empty record's POSITION and COUNT are load-bearing --
; without it the FBOV _SEGTABLE_ is 8 bytes short and everything below it (stub
; band, DGROUP) para-shifts.
;
; The empty byte-aligned CODE segment must NOT be named S233E_TEXT -- that would
; public-combine into the unit's own record instead of emitting its own record.
;
; It also declares an EMPTY word-aligned S233E_TEXT (matching R3D.ASM's SEGDEF)
; to open that segment ahead of R3D.ASM's later contribution; the empty
; declaration public-combines with it, so the segtable shows exactly one D233E
; empty record + one S233E record.

	.286

D233E_TEXT	segment byte public use16 'CODE'
D233E_TEXT	ends

S233E_TEXT	segment word public use16 'CODE'
S233E_TEXT	ends

	end
