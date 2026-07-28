; ============================================================================
; CGAPASTE.ASM -- cga_rect_paste_from_buffer (180c:2a40 / 0x1ab00, 4 bytes).
;
; Bare vtable dispatch thunk: JMPF [g_renderer_vtable+0x1c]
; (RendererVtable.pfn_paste_rect). Same construct as the VTHUNKS.ASM /
; SPRTHNKS.ASM thunk bands: an argument-transparent tail jump through a DGROUP
; slot -- no BCC equivalent (no tail-call optimisation), genuinely asm glue.
;
; Split out of the former VIDINIT.ASM unit when video_init was reconstructed as
; bc31 .cas C (now VIDINIT.C): the C compiler cannot emit a bare JMPF member, so
; the thunk keeps its own one-proc module, linked immediately before VIDINIT.OBJ
; so it stays at 0x1ab00 and video_init starts at 0x1ab04.
; ============================================================================

	.286

	extrn	_g_renderer_vtable:dword		; RendererVtable in DGROUP

_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_cga_rect_paste_from_buffer

; ----------------------------------------------------------------------------
; void far cga_rect_paste_from_buffer(...)  -- tail-jumps through pfn_paste_rect (+0x1c)
; ----------------------------------------------------------------------------
_cga_rect_paste_from_buffer	proc far
	jmp	dword ptr [_g_renderer_vtable + 01ch]
_cga_rect_paste_from_buffer	endp

S180C_TEXT	ends
	end
