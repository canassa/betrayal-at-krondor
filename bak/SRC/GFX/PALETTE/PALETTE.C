#include <dos.h>
#include <mem.h>
#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/WORLD/ZONE/ZONE.H"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/GFX/FONT/FONT.H"
#include "structs.h"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/SYS/RAND.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/GAME/TIMERPL.H"
#include "SRC/SCREENS/ITEMUSE.H"

char g_abPaletteBlendLut[127];

void palette_buffers_alloc(char *fname) {
    g_pPalLoadedBuf = chunk_load_into_slot(fname);
    g_pPalAltA = (unsigned char far *)alloc_far(0x300, 0);
    g_pPalAltB = (unsigned char far *)alloc_far(0x300, 0);
    g_pPalBlendScratch = (unsigned char far *)alloc_far(0x300, 0);
    g_pPalQueuedForFlip = g_pPalLoadedBuf;
    g_nPalBlendMode = 1;
    g_gameState.nPalFadeDirty = 1;
}

void palette_buffers_free(void) {
    _freemem(g_pPalBlendScratch);
    _freemem(g_pPalAltB);
    _freemem(g_pPalAltA);
    cache_release(g_pPalLoadedBuf);
    g_gameState.nPalFadeDirty = 0;
    g_pPalLoadedBuf = (unsigned char far *)0x0;
    g_pPalAltA = (unsigned char far *)0x0;
    g_pPalAltB = (unsigned char far *)0x0;
    g_pPalBlendScratch = (unsigned char far *)0x0;
    g_nPalBlendMode = 0;
}

void far palette_apply_pending_load(void) {
    if (g_gameState.nPalFadeDirty != 0) {
        palette_blend_with_daynight(g_pPalLoadedBuf);
        palette_apply_cycled();
        g_gameState.nPalFadeDirty = 0;
    }
    return;
}

void palette_state_reset(void) {
    g_gameState.nPalFadeDirty = 0;
    g_gameState.nPrevWorldBrightness = -1;
    g_gameState.world_brightness = 0x41;
    g_gameState.nPalDaynightDelta = 0;
    g_gameState.nPalAreaBrightness = 0;
    g_gameState.nPalBrightnessBoost = 0;
    g_gameState.nPalBlendWeight = 0x40;
    return;
}

void far palette_fade_in(unsigned int palette_off, unsigned int palette_seg, int step, int wait_each_step) {
    int intensity;

    if (step == -1) {
        step = 2;
    }
    intensity = 0;
    do {
        palette_set_scaled(palette_off, palette_seg, 0, intensity);
        if (wait_each_step != 0) {
            screen_frame_present();
        }
        intensity = intensity + step;
    } while (intensity < 0x3f);
    palette_set_scaled(palette_off, palette_seg, 0, 0x3f);
    return;
}

void far palette_fade_out(unsigned int palette_off, unsigned int palette_seg, int step, int wait_each_step) {
    int intensity;

    if (step == -1) {
        step = 2;
    }
    for (intensity = 0x3f; 0 < intensity; intensity -= step) {
        palette_set_scaled(palette_off, palette_seg, 0, intensity);
        if (wait_each_step != 0) {
            screen_frame_present();
        }
    }
    palette_set_scaled(palette_off, palette_seg, 0, 0);
    return;
}

void far palette_screen_clear_black(void) {
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage =
        g_graphics_context.wVgaFrontPageBase;
    g_graphics_context.bClip_enabled = 0;
    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bGfx_outline_color = g_graphics_context.bGfx_fill_color =
        g_graphics_context.bGfx_dither_color = 0;
    draw_rect_filled(0, 0, 0x140, 200);
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    return;
}

void far palette_blend_with_daynight(unsigned char far *pPalSrc) {
    int cycleBlend;
    int range_start;
    char *pCycleBand;
    int darkness;
    int range_end;

    if (g_game_mode == 2) {
        if (g_gameState.nPalAreaBrightness != 0) {
            pCycleBand = &g_rgbDayNightCycle_4f4[9];
            cycleBlend = 0x32;
        } else {
            pCycleBand = (char *)0;
        }
        darkness = g_gameState.nPalAreaBrightness + 0xf;
    } else {
        if (g_gameState.nPalBrightnessBoost != 0) {
            pCycleBand = &g_rgbDayNightCycle_4f4[0xc];
            cycleBlend = palette_daylight_modulate(0x1e);
        } else if (g_gameState.nPalDaynightDelta != 0) {
            pCycleBand = &g_rgbDayNightCycle_4f4[6];
            cycleBlend = palette_daylight_modulate(0x25);
        } else {
            pCycleBand = (char *)0;
        }
        darkness = g_gameState.world_brightness + g_gameState.nPalBrightnessBoost;
    }

    darkness = darkness + g_gameState.nPalDaynightDelta;
    if (darkness < 0xf) {
        darkness = 0xf;
    } else if (0x40 < darkness) {
        darkness = 0x40;
    }

    if (g_nPalBlendMode != 1 && g_nPalBlendMode != 2) {
        return;
    }
    if (g_nPalBlendMode == 1) {
        range_start = 0x70;
        range_end = 0xff;
    } else if (g_nPalBlendMode == 2) {
        range_start = 0x10;
        range_end = 0xff;
    }

    palette_interpolate_range(pPalSrc, g_pPalAltB, g_rgbDayNightCycle_4f4, range_start, range_end,
                              g_gameState.nPalBlendWeight);

    if (pCycleBand != (char *)0 && cycleBlend < 0x40) {
        palette_interpolate_range(g_pPalAltB, g_pPalBlendScratch, pCycleBand, range_start,
                                  range_end, cycleBlend);
        palette_interpolate_range(g_pPalBlendScratch, g_pPalAltA, &g_rgbDayNightCycle_4f4[3],
                                  range_start, range_end, darkness);
    } else {
        palette_interpolate_range(g_pPalAltB, g_pPalAltA, &g_rgbDayNightCycle_4f4[3], range_start,
                                  range_end, darkness);
    }

    if (range_start != 0) {
        _fmemcpy(g_pPalAltA, pPalSrc, range_start * 3);
    }
    if (range_end < 0xff) {

        _fmemcpy(g_pPalAltA + range_end + 1, pPalSrc + (range_end + 1) * 3,
                 (0x100 - range_end) * 3);
    }
}

void palette_apply_cycled(void) {
    if (g_nPalBlendMode != 0) {
        (*(void(far *)(unsigned char far *))g_renderer_vtable.pfn_palette_set)(g_pPalAltA);
    }
    g_pPalLastInstalled = g_pPalLoadedBuf;
}

void far palette_interpolate_range(unsigned char far *src, unsigned char far *dst, char *pTarget, int range_start,
                                   int range_end, int blend) {
    char far *pSrc;
    char far *pDst;
    int target_r;
    int target_g;
    int target_b;
    int i;

    pSrc = (char far *)src + range_start * 3;
    pDst = (char far *)dst + range_start * 3;
    blend = 0x40 - blend;
    if (blend > 0 && blend < 0x40) {
        target_r = (signed char)pTarget[0];
        target_g = (signed char)pTarget[1];
        target_b = (signed char)pTarget[2];
        palette_build_blend_lut(blend);
        i = range_start;
        for (; i <= range_end;) {
            pDst[0] = pSrc[0] + g_abPaletteBlendLut[target_r + 0x3f - (signed char)pSrc[0]];
            pDst[1] = pSrc[1] + g_abPaletteBlendLut[target_g + 0x3f - (signed char)pSrc[1]];
            pDst[2] = pSrc[2] + g_abPaletteBlendLut[target_b + 0x3f - (signed char)pSrc[2]];
            i++;
            pSrc += 3;
            pDst += 3;
        }
    } else {
        _fmemcpy(pDst, pSrc, ((range_end - range_start) + 1) * 3);
    }
}

void palette_build_blend_lut(int blend_factor) {
    register int shifted;
    register int acc;
    int i;

    if (blend_factor != g_nPaletteBlendFactorCached) {
        g_nPaletteBlendFactorCached = blend_factor;
        for (i = 1, acc = 0; i < 0x40; i = i + 1, acc = acc + blend_factor) {
            shifted = acc >> 6;
            g_abPaletteBlendLut[0x3f + i] = (char)shifted;
            g_abPaletteBlendLut[0x3f - i] = -(char)shifted;
        }
    }
    return;
}

void palette_daylight_tick(void) {
    g_gameState.nPrevWorldBrightness = g_gameState.world_brightness;
    g_gameState.world_brightness = palette_compute_daylight();
    if (g_gameState.world_brightness != g_gameState.nPrevWorldBrightness) {
        g_gameState.nPalFadeDirty = 1;
    }
    return;
}

int palette_compute_daylight(void) {
    unsigned int hour;
    int remainder;
    int ramp;

    hour = (unsigned int)((g_gameState.game_time % 0xa8c0UL) / 0x708UL);
    remainder = (int)(unsigned int)(g_gameState.game_time % 0xa8c0UL);

    if (hour >= 8 && hour < 0x11) {
        return 0x40;
    }
    if (hour < 4 || hour >= 0x14) {
        return 0xf;
    }
    if (hour < 0x11) {
        remainder += 0xe3e0;
        ramp = (int)(((long)(unsigned int)remainder * 0x31L) / 0x1c20L);
        return ramp + 0xf;
    }
    remainder += 0x8878;
    ramp = (int)(((long)(unsigned int)remainder * 0x31L) / 0x1518L);
    return 0x40 - ramp;
}

int palette_daylight_modulate(int base_brightness) {
    int level;
    unsigned int hour;
    int remainder;
    int ramp;

    level = base_brightness;
    hour = (unsigned int)((unsigned long)(g_gameState.game_time % 0xa8c0) / 0x708);
    remainder = (int)((unsigned long)g_gameState.game_time % 0xa8c0);
    if (hour >= 8 && hour < 0x11) {
        return 0x40;
    }
    if (hour < 4 || hour >= 0x14) {
        return level;
    }
    if (hour < 0x11) {
        remainder += 0xe3e0;
        ramp = (int)((long)((unsigned long)(unsigned)remainder * (long)(0x40 - level)) / 0x1c20);
        return level + ramp;
    }
    remainder += 0x8878;
    ramp = (int)((long)((unsigned long)(unsigned)remainder * (long)(0x40 - level)) / 0x1518);
    return 0x40 - ramp;
}

TimerEventEntry *far palette_fade_schedule(unsigned short sub_id, unsigned long duration) {
    g_gameState.nPalFadeDirty = 1;
    return timerpool_upsert(1, sub_id, 0x80, duration);
}

void far palette_fade_run_scheduled(TimerEventEntry *entry) {
    long phase;

    if (entry == 0)
        return;

    phase = entry->nValue / 30;
    switch (entry->wSub_id) {
    case 0:
        if (phase < 8)
            g_gameState.nPalDaynightDelta = (short)(phase * phase);
        else
            g_gameState.nPalDaynightDelta = 0x31;
        if (entry->nValue == 0)
            itemuse_party_tick_temporary();
        g_gameState.nPalFadeDirty = 1;
        return;
    case 1:
        if (phase < 8) {
            if (phase != 0) {
                phase = 8 - phase;
                g_gameState.nPalBlendWeight = (short)(phase * phase) + 8;
            } else {
                g_gameState.nPalBlendWeight = 0x40;
                g_gameState.nPalFadeDirty = 1;
                return;
            }
        } else {
            g_gameState.nPalBlendWeight = RND2(2) + 8;
        }
        g_gameState.nPalFadeDirty = 1;
        return;
    case 2:
        if (phase < 8)
            g_gameState.nPalAreaBrightness = (short)(phase * phase);
        else
            g_gameState.nPalAreaBrightness = 0x31;
        break;
    case 3:
        if (phase < 8)
            g_gameState.nPalBrightnessBoost = (short)(phase * phase);
        else
            g_gameState.nPalBrightnessBoost = 0x31;
        break;
    default:
        return;
    }
    g_gameState.nPalFadeDirty = 1;
}

unsigned char far *palette_set(unsigned char far *pal) {
    if (g_graphics_context.pPaletteScratchBuf == 0) {
        g_graphics_context.pPaletteScratchBuf = (unsigned char far *)alloc_far(0x600L, 0L);
    }
    if (pal == (unsigned char far *)0) {
        return g_pPalLastInstalled;
    }
    g_pPalLastInstalled = pal;
    (*(void(far *)(unsigned char far *))g_renderer_vtable.pfn_palette_set)(pal);
    return pal;
}
