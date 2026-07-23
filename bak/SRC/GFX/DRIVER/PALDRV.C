#include "SRC/GEN/GFXCTX.H"
#include "SRC/GEN/RNDVTBL.H"
#include "SRC/GFX/FONT/FONT.H"
#include "structs.h"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/SYS/FARPTR.H"
#include "SRC/STREAM/RESLOAD/IFFREAD.H"

short g_palette_cycle_end[10];
short g_palette_cycle_start[10];
short g_palette_cycle_target[10];

short g_palette_cycle_count = 0;
short g_nPaletteScaledIntensity = 63;
short g_nPaletteScaledLevel = 0;
int g_nCurChunkSize = 768;
unsigned short g_awPaletteSizeByAdapter[16] = {0x0000, 0x0102, 0x0011, 0x0011, 0x0102, 0x0300,
                                               0x0000, 0x0300, 0x0300, 0x0300, 0x0300, 0x0030,
                                               0x0030, 0x0030, 0x0030, 0x0300};
char g_szPalVgaChunkTag[9] = "PAL:VGA:";
char g_szPalEgaChunkTag[9] = "PAL:EGA:";
char g_szPalCgaChunkTag[9] = "PAL:CGA:";
char g_szPalEmptyChunkTag[1] = {0x00};
unsigned short g_apszPalChunkTagByAdapter[16] = {
    (unsigned short)g_szPalEmptyChunkTag, (unsigned short)g_szPalCgaChunkTag,
    (unsigned short)g_szPalEgaChunkTag,   (unsigned short)g_szPalEgaChunkTag,
    (unsigned short)g_szPalCgaChunkTag,   (unsigned short)g_szPalVgaChunkTag,
    (unsigned short)g_szPalEmptyChunkTag, (unsigned short)g_szPalVgaChunkTag,
    (unsigned short)g_szPalVgaChunkTag,   (unsigned short)g_szPalVgaChunkTag,
    (unsigned short)g_szPalVgaChunkTag,   (unsigned short)g_szPalEgaChunkTag,
    (unsigned short)g_szPalVgaChunkTag,   (unsigned short)g_szPalVgaChunkTag,
    (unsigned short)g_szPalVgaChunkTag,   (unsigned short)g_szPalVgaChunkTag};
unsigned char far *g_pCurPalette = {0};

unsigned char far *chunk_load_into_slot(BakFileRef *file) {
    int openedHere;
    unsigned char far *pDst;
    unsigned char far *pPalette;
    unsigned char paletteBuf[768];
    unsigned char amgBuf[64];
    int i;
    register int j;

    pPalette = (unsigned char far *)0L;
    g_nCurChunkSize = g_awPaletteSizeByAdapter[(signed char)g_graphics_context.bVideoAdapter];

    for (i = 1;
         (((unsigned char far *far *)&g_graphics_context.pPaletteScratchBuf)[i] != (unsigned char far *)0L) &&
         (i < 10);
         i++) {
    }
    if (i >= 10)
        goto store_slot;

    if (is_file_cached(file) == 0) {
        openedHere = 1;
        file = cached_file_open(file);
    } else {
        openedHere = 0;
    }

    if (chunk_seek(
            file, (char *)g_apszPalChunkTagByAdapter[(signed char)g_graphics_context.bVideoAdapter],
            0) != -1L) {

        if ((pPalette = (unsigned char far *)alloc_far((long)g_nCurChunkSize, 0L)) == (unsigned char far *)0L)
            goto close_file;
        bak_fread(paletteBuf, 1, g_nCurChunkSize, file);
        fmemmove(pPalette, (unsigned char far *)paletteBuf, (long)g_nCurChunkSize);
        goto close_file;
    }

    if (g_graphics_context.bGfxRenderStateFlag == 0)
        goto close_file;

    if (chunk_seek(file, "PAL:AMG:", 0) == -1L)
        goto close_file;

    if (bak_fread(amgBuf, 1, 0x40, file) == 0)
        goto close_file;

    if ((pPalette = (unsigned char far *)alloc_far((long)g_nCurChunkSize, 0L)) == (unsigned char far *)0L)
        goto close_file;

    pDst = pPalette;
    for (j = 0; j < 0x20; j++) {
        *pDst = (unsigned char)(((int)((unsigned short *)amgBuf)[j] >> 8) & 0x0f) << 2;
        pDst++;
        *pDst = (unsigned char)(((int)((unsigned short *)amgBuf)[j] >> 4) & 0x0f) << 2;
        pDst++;
        *pDst = (unsigned char)(amgBuf[j * 2] & 0x0f) << 2;
        pDst++;
    }

    for (j = 0; j < 0x2a0; j++) {
        *pDst = 0;
        pDst++;
    }

close_file:
    if (openedHere != 0)
        cached_file_close(file);

store_slot:
    ((unsigned char far *far *)&g_graphics_context.pPaletteScratchBuf)[i] = pPalette;
    return pPalette;
}

unsigned char far *palette_set_active(unsigned char far *palette) {
    g_nCurChunkSize = g_awPaletteSizeByAdapter[(signed char)g_graphics_context.bVideoAdapter];
    if (g_graphics_context.pPaletteScratchBuf == 0 && g_nCurChunkSize != 0)
        g_graphics_context.pPaletteScratchBuf = alloc_far(g_nCurChunkSize * 2, 0L);
    if (palette == 0)
        return g_pCurPalette;
    g_pCurPalette = palette;
    (*(void(far *)(unsigned char far *))g_renderer_vtable.pfn_palette_set)(palette);
    return palette;
}

void cache_release(unsigned char far *buf_farptr) {
    register int i;

    if (!buf_farptr)
        return;

    for (i = 1; i < 10; i++) {
        if (((unsigned char far *far *)&g_graphics_context.pPaletteScratchBuf)[i] == buf_farptr) {
            _freemem(((unsigned char far *far *)&g_graphics_context.pPaletteScratchBuf)[i]);
            ((unsigned char far *far *)&g_graphics_context.pPaletteScratchBuf)[i] = 0;
        }
    }
}

void palette_set_scaled(unsigned int first_color, unsigned int last_color, int target_color, int intensity) {
    g_nPaletteScaledIntensity = intensity;
    g_nPaletteScaledLevel = target_color;
    (*(void(far *)(unsigned int, unsigned int, int, int))g_renderer_vtable.pfn_palette_lerp_dac)(
        first_color, last_color, target_color, intensity);
    return;
}

int far palette_cycle_add(int start, int count, int target) {
    if (start < 0)
        g_palette_cycle_count = count = 0;
    if (!(int)(signed char)g_graphics_context.bGfxRenderStateFlag || g_palette_cycle_count >= 9 ||
        count <= 1)
        return 0;
    g_palette_cycle_start[g_palette_cycle_count] = start * 3;
    g_palette_cycle_end[g_palette_cycle_count] = (start + count) * 3;
    if (target < 0)
        target = count + target;
    g_palette_cycle_target[g_palette_cycle_count] = target * 3;
    g_palette_cycle_count++;
    return g_palette_cycle_count;
}

void far palette_cycle_tick(void) {
    int start, end, target, i;
    unsigned char far *pWork;
    unsigned char far *pSaved;

    if (!(int)(signed char)g_graphics_context.bGfxRenderStateFlag)
        return;
    pWork = pSaved = g_graphics_context.pPaletteScratchBuf;
    pSaved += 0x300;
    memcpy_inline(pSaved, pWork, 0x300);
    for (i = 0; i < g_palette_cycle_count; i++) {
        start = g_palette_cycle_start[i];
        end = g_palette_cycle_end[i];
        target = g_palette_cycle_target[i];
        memcpy_inline(pWork + start, pSaved + (start + target), end - start - target);
        memcpy_inline(pWork + (end - target), pSaved + start, target);
    }
    (*(Slot34Fn)g_renderer_vtable.pfn_palette_lerp_dac)(0, 0x100, g_nPaletteScaledLevel,
                                                        g_nPaletteScaledIntensity);
}

void near memcpy_inline(unsigned char far *src, unsigned char far *dst, int count) {
    while (count--)
        *dst++ = *src++;
}
