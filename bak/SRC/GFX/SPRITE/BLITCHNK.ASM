; ============================================================================
; BLITCHNK.ASM -- KRONDOR.EXE renderer-vtable dispatch thunks (segment 180c).
; Two members, each a 4-byte hand-asm indirect far jump through
; one slot of g_renderer_vtable (DGROUP+0x2ac6):
;
;   _blit_chunky              JMPF [g_renderer_vtable+0x44]
;                             (RendererVtable.pfn_blit_chunky)
;   _blit_chunky_planar_4bit  JMPF [g_renderer_vtable+0x48]
;                             (RendererVtable.pfn_blit_chunky_planar_4bit)
;
; WHY ASM (both): a bare JMPF through a memory slot is not expressible in Borland
; C++ (BCC 3.1 has no tail-call optimisation) and must remain hand-written
; assembly. The slot addresses are DGROUP-relative offsets expressed symbolically
; as _g_renderer_vtable+off so the linker emits the correct FIXUPP relocation.
; ============================================================================

	.286

	extrn	_g_renderer_vtable:dword	; RendererVtable in DGROUP

	_DATA	SEGMENT WORD PUBLIC 'DATA'
	_DATA	ENDS
	_BSS	SEGMENT WORD PUBLIC 'BSS'
	_BSS	ENDS
	DGROUP	GROUP _DATA, _BSS

S180c_TEXT SEGMENT BYTE PUBLIC USE16 'CODE'
	ASSUME CS:S180c_TEXT, DS:DGROUP

	PUBLIC _blit_chunky
	PUBLIC _blit_chunky_planar_4bit

_blit_chunky PROC FAR
	jmp	dword ptr [_g_renderer_vtable + 044h]
_blit_chunky ENDP

_blit_chunky_planar_4bit PROC FAR
	jmp	dword ptr [_g_renderer_vtable + 048h]
_blit_chunky_planar_4bit ENDP

S180c_TEXT ENDS
	END
