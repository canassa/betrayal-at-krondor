; ============================================================================
; gfxctx.inc -- shared TASM STRUC for the engine graphics-context struct
;               that the 8 Vmcode.OVL video drivers overlay by offset.
;               (8.3 DOS filename: TASM 3.1 cannot open a >8-char basename.)
;
; WHAT THIS IS
;   Each driver, at init, is handed the host engine's graphics-context base
;   (the game passes its base; the driver computes scratch_DS = caller_DS +
;   base/16 so scratch_DS:0 points at this struct). The driver then reads and
;   writes engine video-state through FIXED struct-relative offsets -- e.g.
;   wScreen_height at +0x6EC, the 200-row offset LUT at +0x6F2, the page
;   bases at +0x10. The original devs wrote a TASM STRUC + field names; the
;   assembler resolved those names to the raw numbers the drivers use today
;   (e.g. `mov cx, ds:[6ECh]`). This file RECOVERS that STRUC so the drivers
;   can write `mov cx, ds:[GfxContext.wScreen_height]` instead.
;
; INVARIANT -- THE LAYOUT MUST STAY BYTE-EXACT.
;   Every field is at the EXACT offset of the engine's struct. The drivers
;   are byte-identical hand-disassemblies of the shipped DOS code; if any
;   field moves, GfxContext.<field> stops resolving to the original numeric
;   offset and the per-chunk byte-match diff breaks. Total size is 2742
;   bytes (0x0AB6). Reserved gaps are emitted as `db N dup(?)` to hold the
;   holes between named fields.
;
; SOURCE OF TRUTH
;   the struct `GraphicsContext` recovered from the shipped KRONDOR.EXE
;   (51 fields, 2742 bytes); the engine-side mirror of the same layout is
;   INCLUDE\gfxctx.inc / structs.h. This struct mirrors KRONDOR
;   DGROUP:0x2010 at runtime.
;
; Cross-references:
;   structs.h           -- the engine struct catalogue (GraphicsContext)
;
; USAGE (in a driver .asm, before any reference to the fields):
;   INCLUDE gfxctx.inc
; This file lives in SRC\DRIVERS\VMCODE\ alongside the video drivers; TASM finds
; it via the /iSRC\DRIVERS\VMCODE include-path option (see DRIVERS.MAK's VASM).
; A STRUC definition emits no bytes, so this include can sit near the top of
; the file (e.g. just after the .MODEL / .CODE directives) without perturbing
; the assembled output.
; ============================================================================

GfxContext      STRUC
; --- text / fill render state -------------------------------------------------
bText_fg_color          db ?            ; +0x000
bText_bg_color          db ?            ; +0x001
bText_style_flags       db ?            ; +0x002
bClip_enabled           db ?            ; +0x003
nClip_xmin              dw ?            ; +0x004  (short)
nClip_xmax              dw ?            ; +0x006  (short)
nClip_ymin              dw ?            ; +0x008  (short)
nClip_ymax              dw ?            ; +0x00A  (short)
bGfx_fill_enabled       db ?            ; +0x00C
bGfx_fill_color         db ?            ; +0x00D
bGfx_outline_color      db ?            ; +0x00E
bGfx_dither_color       db ?            ; +0x00F
; --- page bases / blit pages --------------------------------------------------
wVgaPage1Base           dw ?            ; +0x010
wVgaPage2Base           dw ?            ; +0x012
wVgaFrontPageBase       dw ?            ; +0x014
wGfxBlitSrcPage         dw ?            ; +0x016
wGfxBlitDstPage         dw ?            ; +0x018
pReserved_0x1a          db 2 dup(?)     ; +0x01A
; --- adapter / mode state -----------------------------------------------------
bBiosCompatible         db ?            ; +0x01C
bVideoAdapter           db ?            ; +0x01D
bReserved_0x1e          db ?            ; +0x01E
bGfxRenderStateFlag     db ?            ; +0x01F
bReserved_0x20          db ?            ; +0x020
bActiveVgaMode          db ?            ; +0x021
pReserved_0x22          db 18 dup(?)    ; +0x022
; --- font tables (20 entries each) --------------------------------------------
pFont_glyph_width_bits  db 20 dup(?)    ; +0x034
pFont_height            db 20 dup(?)    ; +0x048
pFont_base_char         db 20 dup(?)    ; +0x05C
pFont_glyph_count       db 20 dup(?)    ; +0x070
pReserved_0x84          db 40 dup(?)    ; +0x084
; --- polygon vertex scratch (20 verts each, short) ----------------------------
pPolygonX               dw 20 dup(?)    ; +0x0AC  (short[20])
pPolygonY               dw 20 dup(?)    ; +0x0D4  (short[20])
pPolygonXClipped        dw 20 dup(?)    ; +0x0FC  (short[20])
pPolygonYClipped        dw 20 dup(?)    ; +0x124  (short[20])
pPolygonXSaved          dw 20 dup(?)    ; +0x14C  (short[20])
pPolygonYSaved          dw 20 dup(?)    ; +0x174  (short[20])
nPolygonClipVertexCount dw ?            ; +0x19C  (short)
; --- palette scratch far pointer (BorlandFarPtr: off word, seg word) ----------
pPaletteScratchBuf      dw 2 dup(?)     ; +0x19E  off @ +0x19E, seg @ +0x1A0
pDriver_scratch_0x1a2   db 1306 dup(?)  ; +0x1A2
; --- texture / screen geometry ------------------------------------------------
wTextureIdx             dw ?            ; +0x6BC
pReserved_0x6be         db 42 dup(?)    ; +0x6BE
bYResDoubled            db ?            ; +0x6E8
bReserved_0x6e9         db ?            ; +0x6E9
wScreen_width           dw ?            ; +0x6EA
wScreen_height          dw ?            ; +0x6EC
pReserved_0x6ee         db 4 dup(?)     ; +0x6EE
pRow_offset_lut         dw 200 dup(?)   ; +0x6F2  (ushort[200])
pReserved_tail          db 560 dup(?)   ; +0x882
; --- span-table / autodetect tail --------------------------------------------
wSpanTableBufSeg        dw ?            ; +0xAB2
bVideoAutoDetectEnabled db ?            ; +0xAB4
bReserved_0xab5         db ?            ; +0xAB5
GfxContext      ENDS                    ;  size = 0x0AB6 (2742 bytes)
