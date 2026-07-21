; vidvtbl.asm - the video-driver import vector table (DGROUP:0x2b8e in
; KRONDOR.EXE): g_gfx_default_fptr (the no-op RETF default handler slot) and
; g_video_driver_imports (the 19 engine entry points a loaded VMCODE.OVL video
; driver calls back into), as a standalone relocatable far-function-pointer
; data module linked IMMEDIATELY BEFORE PALDRV.OBJ (PALDRV.C) so the table
; lands at DGROUP+0x2b8e and PALDRV's own _DATA follows at +0x2bde.
; The table's 20 seg-word fixups are emitted ASCENDING by offset (TASM's order),
; in records ahead of PALDRV's code fixups; era Borland C writers emit FIXUPP
; subrecords DESCENDING. This is the sibling case to the renderer vtable
; (rndvtbl.asm).
;
; No CPU directive: this is a pure 16-bit far-pointer DATA module (no 386
; instructions). `.386p` would make TASM emit 32-bit OMF records the 16-bit
; TLINK rejects ("Fatal: 32-bit record encountered").

	extrn	_gfx_retf_stub:far
	extrn	_alloc_far:far
	extrn	__freemem:far
	extrn	_my_read:far
	extrn	_bak_fseek:far
	extrn	_bak_ftell:far
	extrn	_bak_fwrite:far
	extrn	_bak_putc:far
	extrn	_bak_rewind:far
	extrn	_my_close:far
	extrn	_bak_fopen:far
	extrn	_bak_fread:far
	extrn	_bak_fclose:far
	extrn	_my_malloc:far
	extrn	_my_calloc:far
	extrn	_bak_fgetc:far
	extrn	_my_free:far
	extrn	_my_strcat:far
	extrn	_my_strcpy:far
	extrn	_my_strchr:far

; A `word public 'DATA'` contribution to the COMBINED _DATA (not an own segment),
; matching PALDRV.C's _DATA alignment so the follow-on contribution lands where
; PALDRV's named data does.
_DATA	segment word public 'DATA'
DGROUP	group	_DATA

	public	_g_gfx_default_fptr
_g_gfx_default_fptr	label dword
	dd	_gfx_retf_stub	; DGROUP+0x2b8e: default no-op handler

	public	_g_video_driver_imports
_g_video_driver_imports	label byte
	dd	_alloc_far	; +0x00 pfn_alloc_far
	dd	__freemem	; +0x04 pfn_freemem
	dd	_my_read	; +0x08 pfn_read_far
	dd	_bak_fseek	; +0x0c pfn_fseek
	dd	_bak_ftell	; +0x10 pfn_ftell
	dd	_bak_fwrite	; +0x14 pfn_fwrite
	dd	_bak_putc	; +0x18 pfn_putc
	dd	_bak_rewind	; +0x1c pfn_rewind
	dd	_my_close	; +0x20 pfn_close_far
	dd	_bak_fopen	; +0x24 pfn_fopen
	dd	_bak_fread	; +0x28 pfn_fread
	dd	_bak_fclose	; +0x2c pfn_fclose
	dd	_my_malloc	; +0x30 pfn_malloc_far
	dd	_my_calloc	; +0x34 pfn_calloc_far
	dd	_bak_fgetc	; +0x38 pfn_fgetc
	dd	_my_free	; +0x3c pfn_free
	dd	_my_strcat	; +0x40 pfn_strcat_far
	dd	_my_strcpy	; +0x44 pfn_strcpy_far
	dd	_my_strchr	; +0x48 pfn_strchr_far

_DATA	ends

	end
