/*
 * VIDINIT.C -- video_init (180c:2a44 / 0x1ab04, 290 bytes).
 *
 * Video subsystem bring-up: frees any stale palette-scratch buffer, records the
 * BIOS video mode, detects the adapter, loads the matching driver and calls its
 * init entry, copies the driver's 100-entry vtable template into
 * g_renderer_vtable (segment half patched to the driver segment), publishes
 * DGROUP at the absolute engine cell 0000:04f0, allocates the span-table scratch
 * buffer, and grabs the ROM 8x8 font via INT 10h AH=11h AL=30h.
 *
 * Borland RTL-style .cas (C with pseudo-registers + inline asm, cf. DOSMEM.C):
 * the driver init returns its vtable template in DS-relative SI/DX registers
 * consumed by the REP MOVSW block, and the return value rides an asm PUSH AX /
 * POP AX bracket across the tail. Every direction-ambiguous reg,reg op is
 * compiler-emitted pseudo-register C; the asm statements proper are all
 * direction-unambiguous instructions, so the bc31 built-in assembler's store-
 * form habit never shows. This TU owns the video-mode _DATA block (the three
 * mode/driver-init globals at DG 0x2ea8..0x2eae).
 *
 * Split from VIDINIT.ASM: the sibling thunk cga_rect_paste_from_buffer (0x1ab00)
 * cannot be C (bare vtable tail-jump) and stays asm in CGAPASTE.ASM, linked
 * immediately before this object.
 */
#define alloc_far alloc_far_typed /* this TU calls alloc_far K&R (4 word args) */
#include "structs.h"
#include "defines.h"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/GEN/VIDVTBL.H"
#include "SRC/GFX/DRIVER/VIDMODE.H"
#include "SRC/GFX/DRIVER/VIDDET.H"
#include "SRC/GFX/DRIVER/VIDDRV.H"
#include "SRC/GFX/FONT/FONT.H"
#undef alloc_far

void far *alloc_far(); /* K&R view: (size_lo, size_hi, flags_lo, flags_hi) */

extern unsigned char g_renderer_vtable[]; /* this TU's opaque view (BASM can't offset a struct symbol) */

typedef void far VideoDriverInitFn(void *ctx, VideoDriverImports far *imports);

unsigned char g_bSavedBiosVideoMode = 0xff; /* DG+0x2ea8 */
unsigned char g_bRequestedVideoMode = 0xff; /* DG+0x2ea9 */
void far *g_pfnVideoDriverInit = 0;         /* DG+0x2eaa */

int video_init(int mode, int b, char *driver_name) {
    g_bRequestedVideoMode = (unsigned char)mode;
    _AX ^= _AX;
    g_graphics_context.bYResDoubled = _AL;
    g_graphics_context.bGfxRenderStateFlag = _AL;
    g_wScreen_width = 0x140;
    g_wScreen_height = 0xc8;
    _AX = ((unsigned *)&g_graphics_context.pPaletteScratchBuf)[0];
    _DX = ((unsigned *)&g_graphics_context.pPaletteScratchBuf)[1];
    _BX = _AX;
    _BX |= _DX;
    asm jz no_free;
    _freemem(_AX, _DX);
    _AX ^= _AX;
    ((unsigned *)&g_graphics_context.pPaletteScratchBuf)[0] = _AX;
    ((unsigned *)&g_graphics_context.pPaletteScratchBuf)[1] = _AX;
no_free:
    g_bSavedBiosVideoMode = (unsigned char)bios_get_video_mode_bits();
    g_graphics_context.bVideoAdapter = (unsigned char)video_detect_adapter();
    if (_AX == 0)
        goto no_adapter;
    video_driver_load(_AX, (FileRef *)driver_name);
    if (_DX == 0)
        goto no_adapter;
    ((unsigned *)&g_pfnVideoDriverInit)[0] = _AX;
    ((unsigned *)&g_pfnVideoDriverInit)[1] = _DX;
    (*(VideoDriverInitFn far *)g_pfnVideoDriverInit)(&g_graphics_context, &g_video_driver_imports);
    _SI; /* naming SI here is what makes bcc save/restore it around this function;
            the driver init leaves the vtable template at template_seg:SI (SI is
            callee-saved; DX = template segment) -- copy the 100 slots, then patch
            every slot's segment half to the driver segment */
    asm mov di, offset g_renderer_vtable;
    asm push ds;
    asm mov ax, ds;
    asm mov ds, dx;
    asm mov es, ax;
    asm mov ax, 0x32;
    _CX = _AX;
    asm shl cx, 1;
    asm rep movsw;
    asm pop ds;
    asm mov di, offset g_renderer_vtable;
    _AX = _DX;
    asm mov cx, 0x32;
patch_slot:
    asm add di, 2;
    asm stosw;
    asm loop patch_slot;
    goto vtable_done;
no_adapter:
    g_graphics_context.bVideoAdapter = 0;
vtable_done:
    _AX ^= _AX;
    asm mov es, ax;
    asm mov ax, ds;
    /* clang-format off */
    asm mov word ptr es:[0x4f0], ax; /* engine page-seg cell at absolute 0000:04f0 */
    /* clang-format on */
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    _AL = g_graphics_context.bVideoAdapter;
    _AH ^= _AH;
    asm push ax; /* return value (adapter) survives the tail on the stack */
    if (_AX == 0)
        goto done;
    _AX = g_graphics_context_render.wSpanTableBufSeg;
    if (_AX != 0) {
        _BX ^= _BX;
        _AX -= 1;
        _freemem(_BX, _AX);
    }
    _AX = g_wScreen_height;
    _AX <<= 1;
    _AX <<= 1;
    _AX += 0x20;
    _BX ^= _BX;
    alloc_far(_AX, _BX, _BX, _BX);
    if (_DX == 0)
        goto done;
    _DX += 1;
    g_graphics_context_render.wSpanTableBufSeg = _DX;
    /* ROM 8x8 double-dot font: INT 10h AH=11h AL=30h BH=3 -> ES:BP */
    asm mov ax, 0x1130;
    asm mov bh, 3;
    asm int 0x10;
    asm mov bx, offset g_font_bitmap_data;
    asm mov word ptr[bx], bp;
    asm mov word ptr[bx + 2], es;
    asm mov word ptr[bx + 4], bp;
    asm mov word ptr[bx + 6], es;
    _AX = 0x808;
    *(unsigned *)g_graphics_context.pFont_height = _AX;
    *(unsigned *)g_graphics_context.pFont_glyph_width_bits = _AX;
    asm mov ax, 0;
    *(unsigned *)g_graphics_context.pFont_base_char = _AX;
    _AX = 0xffff;
    *(unsigned *)g_graphics_context.pFont_glyph_count = _AX;
done:
    asm pop ax;
    return _AX;
}
