; ============================================================================
; PRESENT.ASM -- KRONDOR.EXE renderer-vtable dispatch thunk (segment 180c).
; Single member: gfx_present_dispatch (180c:1ea4, linear 0x19f64, 4 bytes).
;
; Performs an indirect far jump through the g_renderer_vtable.pfn_present
; slot (DGROUP+0x2ad6 = vtable base 0x2ac6 + 0x10).
;
; Original disassembly (180c:1ea4):
;   JMPF [0x2ad6]    ; FF 2E D6 2A
;
; WHY ASM: a bare JMPF through a memory slot is not expressible in Borland C++
; (BCC 3.1 has no tail-call optimisation) and must remain hand-written assembly.
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

	PUBLIC _gfx_present_dispatch

_gfx_present_dispatch PROC FAR
	jmp	dword ptr [_g_renderer_vtable + 010h]
_gfx_present_dispatch ENDP

S180c_TEXT ENDS
	END
