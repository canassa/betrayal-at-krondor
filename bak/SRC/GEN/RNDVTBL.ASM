; rndvtbl.asm - the renderer vtable (struct RendererVtable, DGROUP:0x2ac6 in
; KRONDOR.EXE) as a standalone relocatable far-function-pointer table. It is a
; TASM data module rather than a C `{ &gfx_retf_stub, ... }` initializer so the
; inline-asm-referenced slots can carry flat PUBLIC labels on the real slot
; storage -- the BCCX built-in inline assembler can't address
; `g_renderer_vtable.pfn_X` / `[vtable+const]`, only a bare symbol.
; Each slot is a FIXUPP-relocated `dd <far fn>` (reloc-equivalent to a C `&fn`).
; C / TASM consumers resolve via the public _g_renderer_vtable. Hand-maintained.
; The table's 50 seg-word fixups are emitted ASCENDING by offset (TASM's order);
; era Borland C writers emit FIXUPP subrecords DESCENDING.
;
; No CPU directive: this is a pure 16-bit far-pointer DATA module (no 386
; instructions). `.386p` would make TASM emit 32-bit OMF records the 16-bit TLINK
; rejects ("Fatal: 32-bit record encountered").

	extrn	_gfx_retf_stub:far

; A `word public 'DATA'` contribution to the COMBINED _DATA (not an own segment).
; Link order places this obj right after the gfx block so g_renderer_vtable lands
; at DGROUP:0x2ac6, mid-_DATA.
_DATA	segment word public 'DATA'
DGROUP	group	_DATA

	public	_g_renderer_vtable
_g_renderer_vtable	label dword
	dd	_gfx_retf_stub	; slot  0 (+0x00)
	dd	_gfx_retf_stub	; slot  1 (+0x04)
	dd	_gfx_retf_stub	; slot  2 (+0x08)
	dd	_gfx_retf_stub	; slot  3 (+0x0c)
	dd	_gfx_retf_stub	; slot  4 (+0x10)
	dd	_gfx_retf_stub	; slot  5 (+0x14)
	dd	_gfx_retf_stub	; slot  6 (+0x18)
	dd	_gfx_retf_stub	; slot  7 (+0x1c)
	dd	_gfx_retf_stub	; slot  8 (+0x20)
	dd	_gfx_retf_stub	; slot  9 (+0x24)
	dd	_gfx_retf_stub	; slot 10 (+0x28)
	dd	_gfx_retf_stub	; slot 11 (+0x2c)
	dd	_gfx_retf_stub	; slot 12 (+0x30)
	dd	_gfx_retf_stub	; slot 13 (+0x34)
	dd	_gfx_retf_stub	; slot 14 (+0x38)
	dd	_gfx_retf_stub	; slot 15 (+0x3c)
	dd	_gfx_retf_stub	; slot 16 (+0x40)
	dd	_gfx_retf_stub	; slot 17 (+0x44)
	dd	_gfx_retf_stub	; slot 18 (+0x48)
	dd	_gfx_retf_stub	; slot 19 (+0x4c)
	dd	_gfx_retf_stub	; slot 20 (+0x50)
	dd	_gfx_retf_stub	; slot 21 (+0x54)
	dd	_gfx_retf_stub	; slot 22 (+0x58)
	dd	_gfx_retf_stub	; slot 23 (+0x5c)
	dd	_gfx_retf_stub	; slot 24 (+0x60)
	dd	_gfx_retf_stub	; slot 25 (+0x64)
	dd	_gfx_retf_stub	; slot 26 (+0x68)
	dd	_gfx_retf_stub	; slot 27 (+0x6c)
	dd	_gfx_retf_stub	; slot 28 (+0x70)
	dd	_gfx_retf_stub	; slot 29 (+0x74)
	dd	_gfx_retf_stub	; slot 30 (+0x78)
	dd	_gfx_retf_stub	; slot 31 (+0x7c)
	dd	_gfx_retf_stub	; slot 32 (+0x80)
	dd	_gfx_retf_stub	; slot 33 (+0x84)
	dd	_gfx_retf_stub	; slot 34 (+0x88)
	dd	_gfx_retf_stub	; slot 35 (+0x8c)
	dd	_gfx_retf_stub	; slot 36 (+0x90)
	public	_g_pfn_blit_stretched
_g_pfn_blit_stretched	label dword	; slot 37 (+0x94)
	dd	_gfx_retf_stub	; slot 37 (+0x94)
	dd	_gfx_retf_stub	; slot 38 (+0x98)
	dd	_gfx_retf_stub	; slot 39 (+0x9c)
	dd	_gfx_retf_stub	; slot 40 (+0xa0)
	dd	_gfx_retf_stub	; slot 41 (+0xa4)
	dd	_gfx_retf_stub	; slot 42 (+0xa8)
	dd	_gfx_retf_stub	; slot 43 (+0xac)
	dd	_gfx_retf_stub	; slot 44 (+0xb0)
	dd	_gfx_retf_stub	; slot 45 (+0xb4)
	dd	_gfx_retf_stub	; slot 46 (+0xb8)
	dd	_gfx_retf_stub	; slot 47 (+0xbc)
	dd	_gfx_retf_stub	; slot 48 (+0xc0)
	dd	_gfx_retf_stub	; slot 49 (+0xc4)

_DATA	ends
	end
