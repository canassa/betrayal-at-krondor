; ============================================================================
; SPRTHNKS.ASM -- KRONDOR.EXE segment 0x180c sprite-blitter vtable dispatch
; thunks (180c:4ab9..180c:4ac9, linear 0x1cb79..0x1cb89, four functions).
;
; Each of the four is a bare 4-byte indirect far jump through one slot of
; g_renderer_vtable, the per-adapter RendererVtable installed by the video
; driver at startup (see palette_set_active / the VMCODE.OVL video drivers).
; A tail JMPF through a memory operand has no C spelling -- Borland C++ 3.1 has
; no tail-call optimisation, so these are hand-written assembly.
;
;   4ab9  blit_sprite              (4 bytes)  far, vtable slot +0x0c
;   4abd  blit_sprite_indirect     (4 bytes)  far, vtable slot +0x74
;   4ac1  gfx_putsprite_fp         (4 bytes)  far, vtable slot +0x84
;   4ac5  blit_stretched_dispatch  (4 bytes)  far, vtable slot +0x94 (dead API,
;                                             zero xrefs)
; ============================================================================

	.286

; --- DGROUP / segment declarations -----------------------------------------
_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

	extrn	_g_renderer_vtable:dword	; RendererVtable in DGROUP

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_blit_sprite
	public	_blit_sprite_indirect
	public	_gfx_putsprite_fp
	public	_blit_stretched_dispatch

; ============================================================================
; blit_sprite @ 180c:4ab9 (linear 0x1cb79, 4 bytes)
;
; Indirect far jump through g_renderer_vtable.pfn_blit_sprite
; (DGROUP+0x2ad2 = vtable base 0x2ac6 + 0x0c).
;
; Original disassembly (180c:4ab9):
;   JMPF [0x2ad2]    ; FF 2E D2 2A
; ============================================================================

_blit_sprite	proc far
	jmp	dword ptr [_g_renderer_vtable+00ch]
_blit_sprite	endp

; ============================================================================
; blit_sprite_indirect @ 180c:4abd (linear 0x1cb7d, 4 bytes)
;
; Indirect far jump through g_renderer_vtable.pfn_blit_sprite_master
; (DGROUP+0x2b3a = vtable base 0x2ac6 + 0x74).
;
; Original disassembly (180c:4abd):
;   JMPF [0x2b3a]    ; FF 2E 3A 2B
; ============================================================================

_blit_sprite_indirect	proc far
	jmp	dword ptr [_g_renderer_vtable+074h]
_blit_sprite_indirect	endp

; ============================================================================
; gfx_putsprite_fp @ 180c:4ac1 (linear 0x1cb81, 4 bytes)
;
; Indirect far jump through g_renderer_vtable.pfn_blit_sprite_simple
; (DGROUP+0x2b4a = vtable base 0x2ac6 + 0x84).
;
; Original disassembly (180c:4ac1):
;   JMPF [0x2b4a]    ; FF 2E 4A 2B
; ============================================================================

_gfx_putsprite_fp	proc far
	jmp	dword ptr [_g_renderer_vtable+084h]
_gfx_putsprite_fp	endp

; ============================================================================
; blit_stretched_dispatch @ 180c:4ac5 (linear 0x1cb85, 4 bytes)
;
; Indirect far jump through g_renderer_vtable.pfn_blit_stretched
; (DGROUP+0x2b5a = vtable base 0x2ac6 + 0x94).
;
; Zero xrefs in the whole program -- a dead public API wrapper (callers use
; the STRBLIT.C stretch blitters or the vtable directly).
;
;   JMPF [0x2b5a]    ; FF 2E 5A 2B
; ============================================================================

_blit_stretched_dispatch	proc far
	jmp	dword ptr [_g_renderer_vtable+094h]
_blit_stretched_dispatch	endp

S180C_TEXT	ends
	end
