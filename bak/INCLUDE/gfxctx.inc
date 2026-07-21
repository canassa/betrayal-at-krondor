; gfxctx.inc - the engine graphics-context para block as TASM STRUCs
; (GraphicsContext head @ DGROUP:0x2010 + GraphicsContextRender tail @
; DGROUP:0x26fe). Field names match structs.h - keep the two in lockstep.
; Reference a head field as [reg].GfxContext.<f> / [_g_graphics_context +
; GfxContext.<f>], a tail field as [_g_graphics_context_render + GfxContextRender.<f>].
; The screen-dim words are the standalone globals _g_wScreen_width /
; _g_wScreen_height. Storage: SRC\GEN\GFXCTX.ASM. Hand-maintained.

ifndef __GFXCTX_INC__
__GFXCTX_INC__ equ 1

GfxContext	struc
bText_fg_color	db	?
bText_bg_color	db	?
bText_style_flags	db	?
bClip_enabled	db	?
nClip_xmin	dw	?
nClip_xmax	dw	?
nClip_ymin	dw	?
nClip_ymax	dw	?
bGfx_fill_enabled	db	?
bGfx_fill_color	db	?
bGfx_outline_color	db	?
bGfx_dither_color	db	?
wVgaPage1Base	dw	?
wVgaPage2Base	dw	?
wVgaFrontPageBase	dw	?
wGfxBlitSrcPage	dw	?
wGfxBlitDstPage	dw	?
pReserved_0x1a	db	2 dup(?)
bBiosCompatible	db	?
bVideoAdapter	db	?
bReserved_0x1e	db	?
bGfxRenderStateFlag	db	?
bReserved_0x20	db	?
bActiveVgaMode	db	?
pReserved_0x22	db	18 dup(?)
pFont_glyph_width_bits	db	20 dup(?)
pFont_height	db	20 dup(?)
pFont_base_char	db	20 dup(?)
pFont_glyph_count	db	20 dup(?)
pReserved_0x84	db	40 dup(?)
pPolygonX	dw	20 dup(?)
pPolygonY	dw	20 dup(?)
pPolygonXClipped	dw	20 dup(?)
pPolygonYClipped	dw	20 dup(?)
pPolygonXSaved	dw	20 dup(?)
pPolygonYSaved	dw	20 dup(?)
nPolygonClipVertexCount	dw	?
pPaletteScratchBuf	dd	?
pDriver_scratch_0x1a2	db	1306 dup(?)
wTextureIdx	dw	?
pReserved_0x6be	db	42 dup(?)
bYResDoubled	db	?
bReserved_0x6e9	db	?
GfxContext	ends

	extrn	_g_graphics_context:byte
endif

; The graphics-context render tail (GraphicsContextRender @ DGROUP:0x26fe).
; Storage: the gfxctx.asm para block, label _g_graphics_context_render.

ifndef __GFXCTX_RENDER_INC__
__GFXCTX_RENDER_INC__ equ 1

GfxContextRender	struc
pReserved_tail	db	560 dup(?)
wSpanTableBufSeg	dw	?
bVideoAutoDetectEnabled	db	?
bReserved_0xab5	db	?
GfxContextRender	ends

	extrn	_g_graphics_context_render:byte
endif

; standalone scalar globals carved out of the para block (gfxctx.asm labels)

ifndef __GFXCTX_DIMS_INC__
__GFXCTX_DIMS_INC__ equ 1
	extrn	_g_wScreen_width:word
	extrn	_g_wScreen_height:word
	extrn	_g_pRow_offset_lut:word
endif
