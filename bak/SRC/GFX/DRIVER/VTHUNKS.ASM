; ============================================================================
; VTHUNKS.ASM -- KRONDOR.EXE renderer-vtable dispatch band (segment 180c).
;
; Six routines, contiguous in the image (180c:22ad..22c1, linear
; 0x1a36d..0x1a382): a leading 1-byte no-op far stub followed by five 4-byte
; indirect-far-jump dispatch thunks, each tail-jumping through one slot of
; g_renderer_vtable (DGROUP+0x2ac6):
;
;   _gfx_dispatch_noop        (180c:22ad / 0x1a36d) RETF (bare far no-op, 1 byte)
;   _set_border_color         (180c:22ae / 0x1a36e) JMPF [g_renderer_vtable+0x64]
;   _renderer_vslot26_dispatch(180c:22b2 / 0x1a372) JMPF [g_renderer_vtable+0x68]
;                             (RendererVtable slot 26)
;   _vsync_hook               (180c:22b6 / 0x1a376) JMPF [g_renderer_vtable+0x20]
;                             (RendererVtable.pfn_vsync_wait)
;   _cga_save_rect_to_buffer  (180c:22ba / 0x1a37a) JMPF [g_renderer_vtable+0x14]
;                             (RendererVtable.pfn_save_rect)
;   _rect_byte_size           (180c:22be / 0x1a37e) JMPF [g_renderer_vtable+0x18]
;                             (RendererVtable.pfn_rect_byte_size)
;
; WHY ASM (all six) -- a bare tail JMPF through a memory slot (and a lone far
; RETF) is not expressible in Borland C++ (BCC 3.1 has no tail-call optimisation;
; an empty far C function emits push bp/pop bp/retf, not a bare retf), so they
; must remain hand-written assembly. Each thunk is `ff 2e <FIXUPP word>`.
; ============================================================================

	.286

	extrn	_g_renderer_vtable:dword	; RendererVtable in DGROUP (+0x2ac6)

	; medium-model group, so DGROUP / ASSUME DS:DGROUP resolve
_DATA	segment word public 'DATA'
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_gfx_dispatch_noop, _set_border_color, _renderer_vslot26_dispatch
	public	_vsync_hook, _cga_save_rect_to_buffer, _rect_byte_size

; ----------------------------------------------------------------------------
; void far gfx_dispatch_noop(void)  -- bare far RETF no-op (1 byte)
; ----------------------------------------------------------------------------
_gfx_dispatch_noop	proc far
	retf
_gfx_dispatch_noop	endp

; ----------------------------------------------------------------------------
; void far set_border_color(...)  -- tail-jumps through vtable slot +0x64
; ----------------------------------------------------------------------------
_set_border_color	proc far
	jmp	dword ptr [_g_renderer_vtable+064h]
_set_border_color	endp

; ----------------------------------------------------------------------------
; void far renderer_vslot26_dispatch(...)  -- tail-jumps through vtable slot +0x68
; ----------------------------------------------------------------------------
_renderer_vslot26_dispatch	proc far
	jmp	dword ptr [_g_renderer_vtable+068h]
_renderer_vslot26_dispatch	endp

; ----------------------------------------------------------------------------
; void far vsync_hook(...)  -- tail-jumps through pfn_vsync_wait (+0x20)
; ----------------------------------------------------------------------------
_vsync_hook	proc far
	jmp	dword ptr [_g_renderer_vtable+020h]
_vsync_hook	endp

; ----------------------------------------------------------------------------
; void far cga_save_rect_to_buffer(...)  -- tail-jumps through pfn_save_rect (+0x14)
; ----------------------------------------------------------------------------
_cga_save_rect_to_buffer	proc far
	jmp	dword ptr [_g_renderer_vtable+014h]
_cga_save_rect_to_buffer	endp

; ----------------------------------------------------------------------------
; void far rect_byte_size(...)  -- tail-jumps through pfn_rect_byte_size (+0x18)
; ----------------------------------------------------------------------------
_rect_byte_size	proc far
	jmp	dword ptr [_g_renderer_vtable+018h]
_rect_byte_size	endp

S180C_TEXT	ends
	end
