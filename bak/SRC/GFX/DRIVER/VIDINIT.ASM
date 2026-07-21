; ============================================================================
; VIDINIT.ASM -- KRONDOR.EXE video subsystem entry points (segment 180c).
;
; Two routines, contiguous in the image (180c:2a40..2b7b, linear
; 0x1ab00..0x1ac26):
;
;   _cga_rect_paste_from_buffer  a bare vtable dispatch thunk:
;                             JMPF [g_renderer_vtable+0x1c]
;                             (RendererVtable.pfn_paste_rect).
;   _video_init                the video subsystem bring-up routine: frees any
;                             stale palette-scratch buffer, probes/records the
;                             BIOS video mode, detects the adapter
;                             (video_detect_adapter, defined in the sibling
;                             VIDDET.ASM unit), loads and calls the matching
;                             driver's init entry through a far function pointer,
;                             copies the driver's 100-entry vtable into
;                             g_renderer_vtable with REP MOVSW, patches every
;                             slot's segment half with STOSW/LOOP, stores the
;                             DGROUP paragraph at the absolute address 0000:04f0
;                             (an engine page-seg cell read by other overlays),
;                             allocates + fills the span-table scratch buffer,
;                             and pulls the ROM 8x8 double-dot font via INT 10h
;                             AH=11h AL=30h.
;
; The three immediates 140h (screen width), 1130h (INT 10h AH=11 AL=30 font-info
; call), 808h (packed font h/w) are plain values, NOT DGROUP addresses.
;
; video_init's callees (__freemem, video_driver_load, alloc_far as FAR calls;
; bios_get_video_mode_bits and video_detect_adapter as near calls) are all
; external to this unit. video_detect_adapter lives in the sibling VIDDET.ASM
; unit (0x1ac53), so it stays `extrn :near`.
; ============================================================================

	.286

	extrn	__freemem:far
	extrn	_bios_get_video_mode_bits:near
	extrn	_video_detect_adapter:near		; defined in sibling unit VIDDET.ASM (0x1ac53)
	extrn	_video_driver_load:far
	extrn	_alloc_far:far

	extrn	_g_renderer_vtable:dword		; RendererVtable in DGROUP
	; In-span graphics-context fields (structs.md §36) -> EQUs into
	; _g_graphics_context via gfxctx.inc: g_bYResDoubled, g_bGfxRenderStateFlag,
	; g_pPaletteScratchBuf, g_bVideoAdapter, g_text_fg_color,
	; g_wVgaFrontPageBase, g_wVgaPage2Base, g_wGfxBlitSrcPage/DstPage,
	; g_wScreen_width/height + render-tail g_graphics_context_render.wSpanTableBufSeg,
	; g_font_height/glyph_width_bits/base_char/glyph_count.
	; (g_text_fg_color = field +0 = the struct base; `offset DGROUP:_g_graphics_context.bText_fg_color`
	;  thus equals `offset _g_graphics_context`, the ptr video_init passes the driver.)
	include	gfxctx.inc
	; Out-of-span globals keep their own extrns:
	extrn	_g_video_driver_imports:byte
	extrn	_g_font_bitmap_data:byte

	; medium-model group, so DGROUP / ASSUME DS:DGROUP resolve
	; This module's own _DATA block (DG 0x2ea8..0x2eae): the video-subsystem
	; mode-save state + the video-driver-init far pointer. video_init (below)
	; writes g_pfnVideoDriverInit and both mode bytes; the sibling VIDDET obj
	; references g_bSavedBiosVideoMode/g_bRequestedVideoMode by extrn.
_DATA	segment word public 'DATA'

	public	_g_bSavedBiosVideoMode, _g_bRequestedVideoMode, _g_pfnVideoDriverInit

_g_bSavedBiosVideoMode	db	0ffh	; DGROUP+0x2ea8 (1B) uchar
_g_bRequestedVideoMode	db	0ffh	; DGROUP+0x2ea9 (1B) uchar
_g_pfnVideoDriverInit	dd	0	; DGROUP+0x2eaa (4B) void *32 (relocated ptr; init image 0)
_DATA	ends
_BSS	segment word public 'BSS'
_BSS	ends
DGROUP	group _DATA, _BSS

S180C_TEXT	segment byte public use16 'CODE'
	assume	cs:S180C_TEXT, ds:DGROUP

	public	_cga_rect_paste_from_buffer, _video_init

; ----------------------------------------------------------------------------
; void far cga_rect_paste_from_buffer(...)  -- tail-jumps through pfn_paste_rect (+0x1c)
; ----------------------------------------------------------------------------
_cga_rect_paste_from_buffer	proc far
	jmp	dword ptr [_g_renderer_vtable + 01ch]
_cga_rect_paste_from_buffer	endp

; ----------------------------------------------------------------------------
; int far video_init(int mode, int driver_seg)   [BP+6]=mode  [BP+0ah]=driver_seg
; ----------------------------------------------------------------------------
_video_init	proc far
	push	bp				; +0x000
	mov	bp,sp				; +0x001
	push	si				; +0x003
	push	di				; +0x004
	mov	al,byte ptr [bp+6h]		; +0x005  mode (low byte)
	mov	byte ptr _g_bRequestedVideoMode,al	; +0x008
	xor	ax,ax				; +0x00b
	mov	byte ptr _g_graphics_context.bYResDoubled,al	; +0x00d
	mov	byte ptr _g_graphics_context.bGfxRenderStateFlag,al	; +0x010
	mov	word ptr _g_wScreen_width,140h	; +0x013  ; 140h screen width 320
	mov	word ptr _g_wScreen_height,0c8h	; +0x019
	mov	ax,word ptr _g_graphics_context.pPaletteScratchBuf	; +0x01f  off
	mov	dx,word ptr _g_graphics_context.pPaletteScratchBuf+2	; +0x022  seg
	mov	bx,ax				; +0x026
	or	bx,dx				; +0x028
	jz	L_vi_0082			; +0x02a  scratch == NULL -> skip free
	push	dx				; +0x02c
	push	ax				; +0x02d
	call	__freemem			; +0x02e  90 0e e8 (TLINK far->near collapse)
	add	sp,4				; +0x033
	xor	ax,ax				; +0x036
	mov	word ptr _g_graphics_context.pPaletteScratchBuf,ax	; +0x038
	mov	word ptr _g_graphics_context.pPaletteScratchBuf+2,ax	; +0x03b
L_vi_0082:
	call	near ptr _bios_get_video_mode_bits	; +0x03e
	mov	byte ptr _g_bSavedBiosVideoMode,al	; +0x041
	call	near ptr _video_detect_adapter	; +0x044
	mov	byte ptr _g_graphics_context.bVideoAdapter,al	; +0x047
	or	ax,ax				; +0x04a
	jz	L_vi_00dd			; +0x04c  no adapter -> skip load
	push	word ptr [bp+0ah]		; +0x04e  driver_seg
	push	ax				; +0x051  adapter (mode)
	call	_video_driver_load		; +0x052  -> DX:AX; 90 0e e8 (TLINK far->near collapse)
	add	sp,4				; +0x057
	or	dx,dx				; +0x05a
	jz	L_vi_00dd			; +0x05c  seg == 0 -> load failed
	mov	word ptr _g_pfnVideoDriverInit,ax	; +0x05e  off
	mov	word ptr _g_pfnVideoDriverInit+2,dx	; +0x061  seg
	push	ds				; +0x065  imports far seg
	mov	ax,offset DGROUP:_g_video_driver_imports	; +0x066
	push	ax				; +0x069  imports off
	mov	ax,offset DGROUP:_g_graphics_context.bText_fg_color	; +0x06a
	push	ax				; +0x06d  near ptr arg
	call	dword ptr _g_pfnVideoDriverInit	; +0x06e  driver init entry
	add	sp,6				; +0x072
	mov	di,offset DGROUP:_g_renderer_vtable	; +0x075
	push	ds				; +0x078
	mov	ax,ds				; +0x079
	mov	ds,dx				; +0x07b  DS = template seg
	mov	es,ax				; +0x07d  ES = DGROUP
	mov	ax,32h				; +0x07f  100 entries
	mov	cx,ax				; +0x082
	shl	cx,1				; +0x084  *2 = 200 words... (REP MOVSW count)
	rep	movsw				; +0x086  copy template vtable -> g_renderer_vtable
	pop	ds				; +0x088
	mov	di,offset DGROUP:_g_renderer_vtable	; +0x089
	mov	ax,dx				; +0x08c  DS (template seg) into slot segs
	mov	cx,32h				; +0x08e  50
L_vi_00d5:
	add	di,2				; +0x091  point at slot.segment
	stosw					; +0x094  slot.segment = AX (template seg)
	loop	L_vi_00d5			; +0x095
	jmp	short L_vi_00e2			; +0x097
L_vi_00dd:
	mov	byte ptr _g_graphics_context.bVideoAdapter,0	; +0x099  adapter = 0 (failed)
L_vi_00e2:
	xor	ax,ax				; +0x09e
	mov	es,ax				; +0x0a0  ES = 0
	mov	ax,ds				; +0x0a2
	mov	es:[4f0h],ax			; +0x0a4  0000:04f0 = DGROUP (engine page seg)
	mov	ax,word ptr _g_graphics_context.wVgaFrontPageBase	; +0x0a8
	mov	word ptr _g_graphics_context.wGfxBlitSrcPage,ax	; +0x0ab
	mov	ax,word ptr _g_graphics_context.wVgaPage2Base	; +0x0ae
	mov	word ptr _g_graphics_context.wGfxBlitDstPage,ax	; +0x0b1
	mov	al,byte ptr _g_graphics_context.bVideoAdapter	; +0x0b4
	xor	ah,ah				; +0x0b7
	push	ax				; +0x0b9  save adapter (return value)
	or	ax,ax				; +0x0ba
	jz	L_vi_0161			; +0x0bc  no adapter -> done
	mov	ax,word ptr _g_graphics_context_render.wSpanTableBufSeg	; +0x0be
	or	ax,ax				; +0x0c1
	jz	L_vi_0116			; +0x0c3  no prior span buf -> skip free
	xor	bx,bx				; +0x0c5
	dec	ax				; +0x0c7  seg-1 (paragraph)
	push	ax				; +0x0c8
	push	bx				; +0x0c9  far ptr (seg-1):0
	call	__freemem			; +0x0ca  90 0e e8 (TLINK far->near collapse)
	add	sp,4				; +0x0cf
L_vi_0116:
	mov	ax,word ptr _g_wScreen_height	; +0x0d2
	shl	ax,1				; +0x0d5
	shl	ax,1				; +0x0d7  *4
	add	ax,20h				; +0x0d9  + 0x20 = span-table byte size
	xor	bx,bx				; +0x0dc
	push	bx				; +0x0de  flags = 0
	push	bx				; +0x0df  size_hi = 0
	push	bx				; +0x0e0  unused = 0
	push	ax				; +0x0e1  size_lo
	call	_alloc_far			; +0x0e2  -> DX:AX; 90 0e e8 (TLINK far->near collapse)
	add	sp,8				; +0x0e7
	or	dx,dx				; +0x0ea
	jz	L_vi_0161			; +0x0ec  alloc failed -> done
	inc	dx				; +0x0ee  seg+1
	mov	word ptr _g_graphics_context_render.wSpanTableBufSeg,dx	; +0x0ef
	mov	ax,1130h			; +0x0f3  ; 1130h INT10h AH=11 AL=30 font info
	mov	bh,3				; +0x0f6  ROM 8x8 double-dot font
	int	10h				; +0x0f8
	mov	bx,offset DGROUP:_g_font_bitmap_data	; +0x0fa
	mov	word ptr [bx],bp		; +0x0fd  font[0].offset = BP (ES:BP from INT 10h)
	mov	word ptr [bx+2h],es		; +0x0ff  font[0].segment = ES
	mov	word ptr [bx+4h],bp		; +0x102  font[1].offset = BP
	mov	word ptr [bx+6h],es		; +0x105  font[1].segment = ES
	mov	ax,808h				; +0x108  ; 808h packed 8/8 font h/w
	mov	word ptr _g_graphics_context.pFont_height,ax	; +0x10b
	mov	word ptr _g_graphics_context.pFont_glyph_width_bits,ax	; +0x10e
	mov	ax,0				; +0x111
	mov	word ptr _g_graphics_context.pFont_base_char,ax	; +0x114  base char = 0
	mov	ax,0ffffh			; +0x117
	mov	word ptr _g_graphics_context.pFont_glyph_count,ax	; +0x11a  glyph count = 0xff each
L_vi_0161:
	pop	ax				; +0x11d  return value (adapter)
	pop	di				; +0x11e
	pop	si				; +0x11f
	pop	bp				; +0x120
	retf					; +0x121
_video_init	endp

S180C_TEXT	ends
	end
