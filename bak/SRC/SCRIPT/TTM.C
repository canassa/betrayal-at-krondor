#include <dos.h>
#include <stdlib.h>
#include <string.h>

#include "gtypes.h"
#include "structs.h"
#include "globals.h"
#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/SCRIPT/ANIMSCR.H"

#include "SRC/SCRIPT/TTM.H"
#include "SRC/SYS/RAND.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/RASTER/CIRCLE.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/SPRITE/STRBLIT.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/GFX/RASTER/DRAWLINE.H"
#include "SRC/GFX/RASTER/PIXEL.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/STREAM/RESLOAD/FONTLOAD.H"
#include "SRC/GFX/SPRITE/ROTBLIT.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/AUDIO/CHAN/AUDCHBYT.H"
#include "SRC/AUDIO/CHAN/SFXEVENT.H"
#include "SRC/AUDIO/CHAN/AUDCHORD.H"
#include "SRC/AUDIO/CHAN/AUDCMD07.H"
#include "SRC/AUDIO/ENGINE/AUDSTPFL.H"
#include "SRC/AUDIO/CHAN/AUDSTPCT.H"
#include "SRC/AUDIO/CHAN/AUDSTPID.H"
#include "SRC/AUDIO/CHAN/AUDSETIN.H"
#include "SRC/AUDIO/CHAN/AUDCCHG.H"
#include "SRC/AUDIO/MUSIC/MUSFADE.H"
#include "SRC/AUDIO/ENGINE/AUDSTPND.H"
#include "SRC/AUDIO/ENGINE/AUDDRVST.H"
#include "SRC/AUDIO/CHAN/AUDCHWRD.H"
#include "SRC/SYS/EMS.H"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/SCRIPT/ADSCRIPT.H"
#include "SRC/SCRIPT/TTMDLG.H"
#include "SRC/UI/MENULBL.H"


short g_nPaletteCycleSavedDuration;
short g_nScriptTickOverride;
short g_nScriptSubOriginX;
short g_nScriptSubOriginY;
unsigned short g_wTtmBlitTint;
unsigned short g_nScriptCurOpcode;
unsigned short g_wScriptOpCursorCache;
short g_aPaletteCycleBandEnd[3];
short g_aPaletteCycleBandStart[3];
unsigned short g_wScript537fbOpVestigial;
unsigned short g_aTtmResourceSlots[20];
char g_szTtmScratch[100];
unsigned char far *g_pPendingPalette;

static void ttmscript_sfx_channel_register(unsigned short handle) {
    int i;

    if (handle != 0) {
        for (i = 0; i < 0x14 && g_aTtmResourceSlots[i] != 0; i++) {
        }
        if (i < 0x14) {
            g_aTtmResourceSlots[i] = handle;
        }
    }
    return;
}

static void ttmscript_resource_slot_release(unsigned short handle) {
    int i;

    if (handle != 0) {
        for (i = 0; i < 0x14 && g_aTtmResourceSlots[i] != handle; i++) {
        }
        if (i < 0x14) {
            g_aTtmResourceSlots[i] = 0;
        }
    }
    return;
}

void ttmscript_sfx_channels_stop_all(void) {
    int i;

    i = 0;
    do {
        if (g_aTtmResourceSlots[i] != 0) {
            audio_sfx_stop(g_aTtmResourceSlots[i]);
            g_aTtmResourceSlots[i] = 0;
        }
        i++;
    } while (i < 0x14);
}

static int far ttmscript_opcode_disp_secondary(unsigned short p0, unsigned short p1, unsigned short p2, unsigned short p3,
                                               unsigned short p4) {
    switch (g_nScriptCurOpcode) {
    case 0xc01f:
    case 0xc02f:
        break;
    case 0xc031:
        if (audio_sfx_register(g_pSfxArchiveStream, p0)) {
            ttmscript_sfx_channel_register(p0);
        }
        break;
    case 0xc041:
        if (audio_sfx_stop(p0)) {
            ttmscript_resource_slot_release(p0);
        }
        break;
    case 0xc051:
        audio_play(p0);
        break;
    case 0xc061:
        audio_driver_stop(p0);
        break;
    case 0xc071:
        audio_stop_category(p0);
        break;
    case 0xc081:
        audio_stop_sfx_all_with_id(p0);
        break;
    case 0xc091:
        audio_stop_filter(p0);
        break;
    case 0xc0a1:
        audio_start_pending(p0);
        break;
    case 0xc102:
        audio_set_intensity(p0, p1);
        break;
    case 0xc0b2:
        audio_channel_apply_chord_event(p0, p1);
        break;
    case 0xc0c2:
        audio_channel_set_byte_15a(p0, p1);
        break;
    case 0xc0d3:
        audio_channel_set_word_bc(p0, p1, p2);
        break;
    case 0xc0e3:
        music_fade(p0, p1, p2);
        break;
    case 0xc0f4:
        audio_chan_apply_ctrl_change(p0, p1, p2, p3);
        break;
    case 0xcf01:
        audio_driver_cmd07_dispatch(p0);
        break;
    case 0xcf11:
        sfx_event_call_32c8_0063(p0);
        break;
    default:
        return -1;
    }
    return 0;
}

static int far ttmscript_opcode_dispatch_main(unsigned short param_1, unsigned short param_2, int param_3,
                                              int param_4, unsigned short param_5, unsigned short param_6,
                                              int param_7, unsigned short param_8) {
    unsigned char far *far *pfreemem;

    switch (g_nScriptCurOpcode) {
    case 0xa0a4:

        draw_line(param_1, param_2, param_3, param_4);
        break;
    case 0xa114:

        g_graphics_context.bGfx_fill_enabled = 0;
        draw_rect_filled(param_1, param_2, param_3, param_4);
        g_graphics_context.bGfx_fill_enabled = 1;
        break;
    case 0xa104:

        g_graphics_context.bGfx_fill_enabled = 1;
        draw_rect_filled(param_1, param_2, param_3, param_4);
        break;
    case 0xa424:

        /* fill-off circle: set fill mode 0, then forward-jump into the fill-on
         * case's shared circle-draw body. */
        g_graphics_context.bGfx_fill_enabled = 0;
        goto L_draw_circle_body;
    case 0xa404:

        g_graphics_context.bGfx_fill_enabled = 1;
    L_draw_circle_body:

        param_5 = (unsigned short)(param_4 >> 1);
        param_6 = param_1 + param_5;
        param_7 = param_2 + param_5;

        draw_circle(param_5, param_6, param_7);
        g_graphics_context.bGfx_fill_enabled = 1;
        break;
    case 0xaf1f:

        /* fill-off text glyph: set fill mode 0, then forward-jump into the
         * fill-on case's shared tail (a redundant fill=1 store + break). */
        g_graphics_context.bGfx_fill_enabled = 0;
        goto L_set_fill_on;
    case 0xaf2f:

        g_graphics_context.bGfx_fill_enabled = 1;
    L_set_fill_on:
        g_graphics_context.bGfx_fill_enabled = 1;
        break;
    case 0xa002:

        putpixel(param_1, param_2, (int)(signed char)g_graphics_context.bGfx_outline_color);
        break;
    case 0xa504:
    case 0xa505:
    case 0xa506:
    case 0xa514:
    case 0xa515:
    case 0xa516:
    case 0xa524:
    case 0xa525:
    case 0xa526:
    case 0xa534:
    case 0xa535:
    case 0xa536:
    case 0xa5a7: {

        unsigned short saved_page_id;
        unsigned char far *ems_ptr;

        g_wTtmBlitTint = (g_nScriptCurOpcode & 0xf0) >> 4;

        if (g_pCurScriptObject->pAhPagedImage[param_4] &&
            (param_3 = ((unsigned short *)g_pCurScriptObject->pAhPagedImage[param_4])[(unsigned short)param_3])) {

            saved_page_id = ((ImageRecord *)param_3)->wImageData;

            if (saved_page_id < 300) {
                ems_ptr = ems_map_resource_pages(saved_page_id);

                ((ImageRecord *)param_3)->wImageData = ((unsigned short *)&ems_ptr)[1];
            }

            if ((g_nScriptCurOpcode & 0x0f) == 7) {
                jmp_via_2f48((unsigned char *)param_3, param_1, param_2, param_7, param_5, param_6,
                             ((ImageRecord *)param_3)->nWidth >> 1,
                             ((ImageRecord *)param_3)->nHeight >> 1);
            } else if ((g_nScriptCurOpcode & 0x0f) == 6) {
                if (((ImageRecord *)param_3)->wUnk4 & 0x20) {
                    emsimg_sprite_blit_scaled_paged((ImageRecord *)param_3, param_1, param_2,
                                                    g_wTtmBlitTint, param_5, param_6);
                } else {
                    blit_image_stretched((ImageRecord *)param_3, param_1, param_2, g_wTtmBlitTint,
                                         param_5, param_6);
                }
            } else if ((g_nScriptCurOpcode & 0x0f) != 5) {
                if (((ImageRecord *)param_3)->wUnk4 & 0x20) {
                    resblit_sprite_frame((ImageRecord *)param_3, param_1, param_2, g_wTtmBlitTint);
                } else {
                    blit_sprite_indirect((unsigned short)param_3, param_1, param_2, g_wTtmBlitTint);
                }
            }

            ((ImageRecord *)param_3)->wImageData = saved_page_id;
        }
        break;
    }
    case 0xa601:

        if (g_wScriptOpCursorCache != 0)
            break;
        pfreemem = &g_pCurScriptObject->pFreemem[param_1];
        if (!*pfreemem)
            break;
        cga_rect_paste_from_buffer(*pfreemem, g_pCurScriptObject->pRectSrcX[param_1],
                                   g_pCurScriptObject->pRectSrcY[param_1],
                                   g_pCurScriptObject->pRectDstX[param_1],
                                   g_pCurScriptObject->pRectDstY[param_1]);
        break;
    case 0xa304:
    case 0xa704:
    case 0xaf02:

        break;
    default:

        if ((g_nScriptCurOpcode >= 0xa014 && g_nScriptCurOpcode <= 0xa094) ||
            g_nScriptCurOpcode == 0xa0b5) {

            if (g_wScriptOpCursorCache != 0)
                break;
            if (param_3 <= 0)
                break;
            if (param_4 <= 0)
                break;

            if ((int)param_1 + param_3 > (int)g_wScreen_width)
                break;
            if ((int)param_2 + param_4 > (int)g_wScreen_height)
                break;
            ttmscript_screen_trans_disp(param_1, param_2, param_3, param_4, param_5,
                                        g_nScriptCurOpcode);
        } else if (g_nScriptCurOpcode >= 0xa204 && g_nScriptCurOpcode <= 0xa294) {

            font_activate(g_pCurScriptObject->pAhFont[g_pCurScriptAnimNode->wFld_10]);
            g_graphics_context.bText_style_flags = 1;
            font_draw_text_ds((char *)g_aTtmTextStringOffsets[(g_nScriptCurOpcode - 0xa204u) >> 4],
                              param_1, param_2);
            g_graphics_context.bText_style_flags = 0;
        } else {
            return -1;
        }
        break;
    }
    return 0;
}

int ttmscript_interpret_loop(int block_index) {
    int p0, p1, p2, p3, p4, p5, p6;
    int frame_hold_was_clear;
    unsigned short far *w;
    char *scratchStr;
    int low;
    unsigned long sz;
    ScriptObject far *fp;
    unsigned char far *far *pp;
    int x0, y0;
    int si;
    int t;

    if (g_pCurScriptObject == 0)
        return 0;

    w = (unsigned short far *)g_pCurScriptObject->pBlocks[block_index];
    g_wScriptOpCursorCache = g_pCurScriptAnimNode->wOpCursor;
    g_nScriptPendingJumpTarget = -1;

    for (;;) {
        g_nScriptCurOpcode = w[0];
        low = g_nScriptCurOpcode & 0xf;

        if (g_nScriptCurOpcode == 0x1301)
            g_nScriptCurOpcode = 0xc051;
        if (g_nScriptCurOpcode == 0x1311)
            g_nScriptCurOpcode = 0xc061;

        if (g_nScriptCurOpcode == 0xff0)
            goto L_return_1;

        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage =
            g_graphics_context.wVgaPage2Base;

        w++;
        p0 = w[0];
        p1 = w[1];
        p2 = w[2];
        p3 = w[3];
        p4 = w[4];
        p5 = w[5];
        p6 = w[6];

        if (low == 0xf) {
            if (g_nScriptCurOpcode == 0xaf1f || g_nScriptCurOpcode == 0xaf2f) {
                scratchStr = ttmscript_strcpy_to_scratch(p0 << 2, (char far *)(w + 1));
                FP_OFF(w) += p0 * 4 + 2;
            } else {
                scratchStr = ttmscript_strcpy_to_scratch(0, (char far *)w);
                w = (unsigned short far *)adscript_skip_aligned_cstring((char far *)w);
            }
        } else {
            scratchStr = (char *)0;
            FP_OFF(w) += low * 2;
        }

        if (g_nScriptEnhancedOpcodeDispatchEnabled != 0 && g_nScriptCurOpcode >= 0xa000 &&
            g_nScriptCurOpcode <= 0xafff) {
            switch (g_nScriptCurOpcode) {
            case 0xa601:
            case 0xaf1f:
            case 0xaf2f:
                break;
            case 0xa0a4:
                p2 += g_nScriptSubOriginX;
                p3 += g_nScriptSubOriginY;
            default:
                p0 += g_nScriptSubOriginX;
                p1 += g_nScriptSubOriginY;
                break;
            }
        }

        if ((g_nScriptCurOpcode & 0xf000) == 0xc000) {
            if (g_wScriptOpCursorCache == 0) {

                if (ttmscript_opcode_disp_secondary(p0, p1, p2, p3, (unsigned short)scratchStr)) {
                }
            }
        } else if ((g_nScriptCurOpcode & 0xf000) == 0xa000) {
            if (ttmscript_opcode_dispatch_main(p0, p1, p2, p3, p4, p5, p6, (unsigned short)scratchStr)) {
            }
        } else {
            switch (g_nScriptCurOpcode) {

            case 0x2002:
                g_pCurScriptAnimNode->bSavedFgColor = (unsigned char)p0;
                g_graphics_context.bGfx_outline_color = (unsigned char)p0;
                g_graphics_context.bText_fg_color = (unsigned char)p0;
                g_pCurScriptAnimNode->bSavedFillColor = (unsigned char)p1;
                g_graphics_context.bGfx_fill_color = (unsigned char)p1;
                break;

            case 0xf01f:
                if (g_wScriptOpCursorCache == 0) {
                    resblit_load_pal_or_stream(scratchStr);
                    adscript_blit_full_other_page();
                }
                break;

            case 0x1031:
                g_pCurScriptAnimNode->wFld_1c = p0;
                break;

            case 0x1051:
                g_pCurScriptAnimNode->wFld_14 = p0;
                break;

            case 0xf02f:
                if (g_wScriptOpCursorCache == 0) {
                    unsigned short h;
                    si = g_pCurScriptAnimNode->wFld_14;
                    h = g_pCurScriptObject->pAhPagedImage[si];
                    if (h != 0)
                        emsimg_free_paged((void *)h);
                    g_pCurScriptObject->pAhPagedImage[si] =
                        (unsigned short)resblit_load_asset_table(scratchStr, 2);
                }
                break;

            case 0x80:
                if (g_wScriptOpCursorCache == 0) {
                    unsigned short h;
                    si = g_pCurScriptAnimNode->wFld_14;
                    h = g_pCurScriptObject->pAhPagedImage[si];
                    if (h != 0)
                        emsimg_free_paged((void *)h);
                    g_pCurScriptObject->pAhPagedImage[si] = 0;
                }
                break;

            case 0x1121:
                g_pCurScriptAnimNode->wFld_16 = p0;
                break;

            case 0x4214:
                if (g_wScriptOpCursorCache == 0) {
                    si = g_pCurScriptAnimNode->wFld_16;
                    g_pCurScriptObject->pRectSrcX[si] = p0;
                    g_pCurScriptObject->pRectSrcY[si] = p1;
                    g_pCurScriptObject->pRectDstX[si] = p2;
                    g_pCurScriptObject->pRectDstY[si] = p3;
                    pp = &g_pCurScriptObject->pFreemem[si];
                    if (*pp != 0) {
                        _freemem(*pp);
                        *pp = 0;
                    }
                    if ((sz = (unsigned)rect_byte_size(p2, p3)) != 0) {
                        if ((*pp = (unsigned char far *)alloc_far(sz, 0)) != 0)
                            cga_save_rect_to_buffer(*pp, p0, p1, p2, p3);
                    }
                }
                break;

            case 0xc0:
                if (g_wScriptOpCursorCache == 0) {
                    pp = &g_pCurScriptObject->pFreemem[g_pCurScriptAnimNode->wFld_16];
                    if (*pp != 0)
                        _freemem(*pp);
                    *pp = 0;
                }
                break;

            case 0x1071:
                g_pCurScriptAnimNode->wFld_10 = p0;
                font_activate(g_pCurScriptObject->pAhFont[p0]);
                break;

            case 0xf04f:
                if (g_wScriptOpCursorCache == 0) {
                    fp = ttmscript_body_after_args();
                    if (fp->wResourceId != 0)
                        font_unload(fp->wResourceId);
                    font_activate(fp->wResourceId = font_load(scratchStr));
                }
                break;

            case 0x90:
                if (g_wScriptOpCursorCache == 0) {
                    fp = ttmscript_body_after_args();
                    if (fp->wResourceId != 0)
                        font_unload(fp->wResourceId);
                    fp->wResourceId = 0;
                }
                break;

            case 0x1061:
                g_pCurScriptAnimNode->wFld_12 = p0;
                if (g_wScriptOpCursorCache == 0) {
                    g_pPendingPalette = g_pCurScriptObject->pCachedResource[p0];
                    if (g_graphics_context.bVideoAdapter == 4)
                        palette_set(g_pPendingPalette);
                }
                break;

            case 0xf05f:
                if (g_wScriptOpCursorCache == 0) {
                    p0 = g_pCurScriptAnimNode->wFld_12;
                    if (g_pCurScriptObject->pCachedResource[p0] != 0)
                        cache_release(g_pCurScriptObject->pCachedResource[p0]);
                    g_pPendingPalette = g_pCurScriptObject->pCachedResource[p0] =
                        chunk_load_into_slot(scratchStr);
                }
                break;

            case 0x70:
                if (g_wScriptOpCursorCache == 0) {
                    p0 = g_pCurScriptAnimNode->wFld_12;
                    if (g_pCurScriptObject->pCachedResource[p0] != 0) {
                        if (g_pCurScriptObject->pCachedResource[p0] == g_pPendingPalette)
                            g_pPendingPalette = 0;
                        cache_release(g_pCurScriptObject->pCachedResource[p0]);
                    }
                    g_pCurScriptObject->pCachedResource[p0] = 0;
                }
                break;

            case 0x1041:
                g_wScript537fbOpVestigial = p0;
                break;

            case 0x1011:
                set_border_color(p0);
                break;

            case 0x4114:
                if (g_wScriptOpCursorCache == 0) {
                    if (g_graphics_context.bGfxRenderStateFlag != 0) {
                        g_nScriptCurOpcode = g_aTtmFadeStepTable[p3];
                        if (g_nScriptCurOpcode == 0) {
                            palette_set_scaled(p0, p1, p2, 0);
                        } else {

                            for (si = 0x280; si != 0; si -= g_nScriptCurOpcode) {
                                palette_set_scaled(p0, p1, p2,
                                                   (si / 10 < 0 ? 0 : si / 10) > 0x3f
                                                       ? 0x3f
                                                       : (si / 10 < 0 ? 0 : si / 10));
                            }
                        }
                    }
                    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;
                    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaFrontPageBase;
                    gfx_present_dispatch(0, 0, g_wScreen_width, g_wScreen_height);
                    if ((int)g_nVgaRenderMode >= 3) {
                        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
                        gfx_present_dispatch(0, 0, g_wScreen_width, g_wScreen_height);
                    }
                    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                    g_pPendingPalette = palette_set(g_pPendingPalette);
                }
                break;

            case 0x4124:
                if (g_wScriptOpCursorCache == 0) {
                    palette_set(g_pPendingPalette);
                    if (g_graphics_context.bGfxRenderStateFlag != 0)
                        palette_set_scaled(p0, p1, p2, 0);
                    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaFrontPageBase;
                    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;
                    gfx_present_dispatch(0, 0, g_wScreen_width, g_wScreen_height);
                    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                    if (g_graphics_context.bGfxRenderStateFlag != 0) {
                        g_nScriptCurOpcode = g_aTtmFadeStepTable[p3];
                        if (g_nScriptCurOpcode == 0) {
                            palette_set_scaled(p0, p1, p2, 0x3f);
                        } else {
                            for (si = 0; si <= 0x280; si += g_nScriptCurOpcode) {
                                palette_set_scaled(p0, p1, p2,
                                                   (si / 10 < 0 ? 0 : si / 10) > 0x3f
                                                       ? 0x3f
                                                       : (si / 10 < 0 ? 0 : si / 10));
                            }
                        }
                    }
                }
                break;

            case 0x2302:
            case 0x2312:
            case 0x2322:
                if (g_graphics_context.bGfxRenderStateFlag != 0) {

                    si = (unsigned int)(g_nScriptCurOpcode - 0x2302) >> 4;
                    g_aPaletteCycleBandStart[si] = p0;
                    g_aPaletteCycleBandEnd[si] = p1;
                }
                break;

            case 0x2402:
                if (g_wScriptOpCursorCache == 0 && g_graphics_context.bGfxRenderStateFlag != 0) {
                    if (p1 == 0)
                        p1 = 1;
                    si = p1 / abs(p1);
                    g_nPaletteCycleSavedDuration = abs(p1);
                    g_bPaletteCycleEbActive = 1;
                    palette_cycle_add(-1, 0, 0);
                    if (p0 & 1)
                        ttmscript_pal_cycle_band_add(0, si);
                    if (p0 & 2)
                        ttmscript_pal_cycle_band_add(1, si);
                    if (p0 & 4)
                        ttmscript_pal_cycle_band_add(2, si);
                }
                break;

            case 0x400:
                if (g_wScriptOpCursorCache == 0 && g_graphics_context.bGfxRenderStateFlag != 0) {
                    palette_cycle_add(-1, 0, 0);
                    g_pPendingPalette = palette_set(g_pPendingPalette);
                    g_bPaletteCycleEbActive = 0;
                }
                break;

            case 0x2022:
                if (g_wScriptOpCursorCache == 0)
                    g_nScriptTickOverride =
                        p0 + abs((short)((unsigned int)rand() % (unsigned int)(p1 - p0)));
                break;

            case 0x1021:
                g_nScriptTickOverride = p0;
                break;

            case 0x20:
                if (g_wScriptOpCursorCache == 0)
                    adscript_blit_full_other_page();
                break;

            case 0x4204:
                if (g_wScriptOpCursorCache == 0 && (int)g_nVgaRenderMode >= 3)
                    adscript_rndr_blit_other_page(p0, p1, p2, p3);
                break;

            case 0xb606:
                if (g_wScriptOpCursorCache == 0) {
                    g_graphics_context.wGfxBlitSrcPage = ttmscript_lookup_coord_global(p4);
                    g_graphics_context.wGfxBlitDstPage = ttmscript_lookup_coord_global(p5);
                    gfx_present_dispatch(p0, p1, p2, p3);
                    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
                    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
                }
                break;

            case 0x2012:
                ttmscript_show_dialog_action(p0, p1);
                break;

            case 0x4004:
                g_graphics_context.clip.xmin = g_pCurScriptAnimNode->nSavedClipXmin = p0;
                g_graphics_context.clip.ymin = g_pCurScriptAnimNode->nSavedClipYmin = p1;
                g_graphics_context.clip.xmax = g_pCurScriptAnimNode->nSavedClipXmax = p2;
                g_graphics_context.clip.ymax = g_pCurScriptAnimNode->nSavedClipYmax = p3;
                g_graphics_context.bClip_enabled = g_pCurScriptAnimNode->bSavedClipEnabled = 1;
                break;

            case 0x110:
                g_wScriptFrameHoldFlag = 1;
                break;

            case 0x3003:
                g_nScriptEnhancedOpcodeDispatchEnabled++;
                g_nScriptSubOriginX = p0;
                g_nScriptSubOriginY = p1;
                frame_hold_was_clear = !g_wScriptFrameHoldFlag;
                ttmscript_interpret_loop(ttmscript_find_block_by_tag(p2));
                if (g_wScriptFrameHoldFlag != 0 && frame_hold_was_clear)
                    g_wScriptFrameHoldFlag = 0;
                g_nScriptEnhancedOpcodeDispatchEnabled--;
                break;

            case 0x1201:
                g_nScriptPendingJumpTarget = ttmscript_find_block_by_tag(p0);
                break;

            case 0x500:
                g_wScriptEnhancedAuxFlag = 1;
                break;

            case 0x510:
                g_wScriptEnhancedAuxFlag = 0;
                break;

            case 0xb000:
                if (g_wScriptOpCursorCache == 0)
                    menulbl_calc_max_label_width();
                break;

            case 0xb013:
                menulbl_scroll_step_and_draw(p0, p1, p2);
                break;

            case 0x10:
            case 0x1101:
            case 0x1111:
            case 0x3103:
            case 0x4136:
            case 0x5005:
                break;

            default:

                if (g_nScriptCurOpcode >= 0xf10f && g_nScriptCurOpcode <= 0xf19f) {
                    si = (unsigned int)(g_nScriptCurOpcode - 0xf10f) >> 4;
                    strcpy((char *)g_aTtmTextStringOffsets[si], scratchStr);
                    si = si + 1;
                    for (; si < 9; si++)
                        *(char *)g_aTtmTextStringOffsets[si] = 0;
                } else if (g_nScriptCurOpcode == 0xff0) {
                }
                break;
            }
        }

        if (g_nScriptCurOpcode >= 0xa000 && g_nScriptCurOpcode <= 0xafff) {
            switch (g_nScriptCurOpcode) {
            case 0xa5a7:
                read_4words_from_2tables((unsigned short *)&p0, (unsigned short *)&p1, (unsigned short *)&p4,
                                         (unsigned short *)&p5);
                p4 -= p0;
                p5 -= p1;
                adscript_op_noop(p0, p1, p4, p5);
                break;

            case 0xa704:
                if (g_bTtmViewportClampFlag == 0)
                    continue;
                adscript_op_noop(p0, p1, p2, p3);
                break;

            case 0xa504:
            case 0xa505:
            case 0xa506:
            case 0xa514:
            case 0xa515:
            case 0xa516:
            case 0xa524:
            case 0xa525:
            case 0xa526:
            case 0xa534:
            case 0xa535:
            case 0xa536: {

                if (g_pCurScriptObject->pAhPagedImage[p3] == 0 ||
                    (si = ((unsigned short *)g_pCurScriptObject->pAhPagedImage[p3])[p2]) == 0)
                    continue;
                if ((g_nScriptCurOpcode & 0xf) == 6) {

                    if (p4 > 0)
                        if (p5) {
                        }
                    adscript_op_noop(p0, p1, p4, p5);
                } else {
                    register int d;
                    if ((t = ((((ImageRecord *)si)->nWidth >= 0) ? ((ImageRecord *)si)->nWidth
                                                                 : -((ImageRecord *)si)->nWidth)) !=
                        0) {
                        d = ((ImageRecord *)si)->nHeight + 2;
                        adscript_op_noop(p0, p1, t, d);
                    }
                }
                break;
            }

            case 0xa404:
            case 0xa424:
                adscript_op_noop(p0 - 0x14, p1, p2 + 0x30, p3 + 1);
                break;

            case 0xaf1f:
            case 0xaf2f:
                adscript_op_noop(0, 0, g_wScreen_width, g_wScreen_height);
                break;

            case 0xa601:
                if (g_pCurScriptObject->pFreemem[p0] != 0)
                    adscript_op_noop(
                        g_pCurScriptObject->pRectSrcX[p0], g_pCurScriptObject->pRectSrcY[p0],
                        g_pCurScriptObject->pRectDstX[p0], g_pCurScriptObject->pRectDstY[p0]);
                break;

            case 0xa002:
                adscript_op_noop(p0, p1, 8, 1);
                break;

            case 0xa0a4: {
                register int h;
                x0 = (p0 < p2) ? p0 : p2;
                y0 = (p1 < p3) ? p1 : p3;
                t = abs(p0 - p2);
                h = abs(p1 - p3);
                adscript_op_noop(x0, y0, t + 8, h + 2);
                break;
            }

            case 0xaf02:
                continue;

            default:
                adscript_op_noop(p0, p1, p2 + 8, p3 + 2);
                break;
            }
        }
    }

L_return_1:
    return 1;
}

int ttmscript_find_block_by_tag(int tag_arg) {
    int i;
    unsigned opcode;

    for (i = 0;; i++) {
        if (g_pCurScriptObject->pBlocks[i] == 0)
            return -1;
        opcode = g_pCurScriptObject->pBlocks[i]->wOpcode;

        if (opcode == 0x1101 || opcode == 0x1111) {
            opcode = g_pCurScriptObject->pBlocks[i]->wOperand;
            if (opcode == tag_arg)
                return i;
        }
    }
}

char *ttmscript_strcpy_to_scratch(int param_1, char far *param_2) {
    int i;

    (void)_SI;
    i = 0;
    if (param_1 < (short)g_wScreen_height) {
        if (param_1 == 0) {
            while (*param_2 != '\0') {
                g_szTtmScratch[i] = *param_2;
                param_2++;
                i++;
            }
        } else {
            while (param_1-- != 0) {
                g_szTtmScratch[i] = *param_2;
                param_2++;
                i++;
            }
        }
    }
    g_szTtmScratch[i] = '\0';
    return g_szTtmScratch;
}

ScriptObject far *ttmscript_body_after_args(void) {
    unsigned int tmp = g_pCurScriptAnimNode->wFld_10;

    return (ScriptObject far *)&g_pCurScriptObject->pAhFont[tmp];
}

void ttmscript_pal_cycle_band_add(int param_1, int param_2) {
    palette_cycle_add(g_aPaletteCycleBandStart[param_1],
                      g_aPaletteCycleBandEnd[param_1] - g_aPaletteCycleBandStart[param_1] + 1,
                      param_2);
    return;
}

unsigned short ttmscript_lookup_coord_global(unsigned short idx) {
    switch (idx) {
    case 0:
        return g_graphics_context.wVgaFrontPageBase;
    case 1:
        return g_graphics_context.wVgaPage2Base;
    case 2:
        return g_graphics_context.wVgaPage1Base;
    case 3:
        return g_wVgaScratchPageBase;
    default:
        return g_graphics_context.wVgaPage2Base;
    }
}

void ttmscript_screen_trans_disp(unsigned short param_1, unsigned short param_2, int param_3, int param_4,
                                 unsigned short param_5, unsigned short param_6) {
    long tempA;
    long tempB;
    unsigned int xsave;
    int right;
    unsigned int xcenter;
    unsigned int ysave;
    int bottom;
    unsigned int ycenter;
    int dy;
    int bound;
    unsigned short savedDstPage;
    int i;
    int halfW;

    (void)param_5;

    savedDstPage = g_graphics_context.wGfxBlitDstPage;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaFrontPageBase;
    right = (xsave = param_1) + param_3;
    bottom = (ysave = param_2) + param_4;

    switch (param_6) {
    case 0xa034:
    case 0xa094:
        param_3 >>= 1;
        param_4 = param_4 >> 1;
        xcenter = param_1 + param_3;
        ycenter = param_2 + param_4;
        bound = (param_3 > param_4) ? param_3 : param_4;
        tempA = (long)param_3 * 1000 / bound;
        tempB = (long)param_4 * 1000 / bound;
        if (param_6 == 0xa034) {
            i = bound;
        } else {
            i = 1;
        }
        while ((i >= 1 && param_6 == 0xa034) || (i <= bound && param_6 == 0xa094)) {
            if (param_6 == 0xa034) {
                i--;
            } else {
                i++;
            }
            halfW = (int)(tempA * i / 1000);
            dy = (int)(tempB * i / 1000);
            param_1 = xcenter - halfW;
            param_2 = ycenter - dy;
            param_3 = halfW << 1;
            param_4 = dy << 1;
            if (param_6 == 0xa034) {
                ttmscript_vport_set_large_enough(xsave, ysave, param_1 - xsave, bottom - ysave);
                ttmscript_vport_set_large_enough(param_1 + param_3, ysave,
                                                 right - param_1 - param_3, bottom - ysave);
                ttmscript_vport_set_large_enough(param_1, ysave, param_3, param_2 - ysave);
                ttmscript_vport_set_large_enough(param_1, param_2 + param_4, param_3,
                                                 bottom - param_2 - param_4);
            } else {
                ttmscript_vport_set_large_enough(param_1, param_2, param_3, param_4);
            }
        }
        break;

    case 0xa024:
        ttmscript_vport_set_large_enough(param_1, param_2, param_3, param_4);
        break;

    case 0xa054:
    case 0xa064:
        bound = param_3;
        for (i = 3; i <= bound + -3; i++) {
            if (param_6 == 0xa064) {
                param_1 = right - i;
            } else if (param_6 == 0xa054) {
                param_1 = i + -3;
            }
            ttmscript_vport_set_large_enough(param_1, param_2, 3, param_4);
        }
        break;

    case 0xa044:
        for (i = 1; i <= 0xa; i++) {
            dy = 0;
            for (;;) {
                if ((int)(ysave + i + dy) > bottom) {
                    break;
                }
                if (param_3 != 0) {
                    gfx_present_dispatch(xsave, ysave + i + dy, param_3, 1);
                }
                dy += 10;
                ttmscript_vports_reset_all_100();
            }
        }
        break;

    case 0xa014:
    case 0xa0b5:

        break;

    default:
        bound = param_4;
        for (i = 3; i <= bound + -3; i++) {
            if (param_6 == 0xa084) {
                param_2 = bottom - i;
            } else if (param_6 == 0xa074) {
                param_2 = i + -3;
            }
            ttmscript_vport_set_large_enough(param_1, param_2, param_3, 3);
            ttmscript_vports_reset_all_100();
        }
        break;
    }

    g_graphics_context.wGfxBlitDstPage = savedDstPage;
}

void ttmscript_vports_reset_all_100(void) {
    int i;

    for (i = 1; i <= 0x64; i = i + 1) {
        ttmscript_vport_set_large_enough(0, 0, 0, 0);
    }
    return;
}

void ttmscript_vport_set_large_enough(int x, int y, int w, int h) {
    if ((w >= 3) && (h >= 3)) {
        gfx_present_dispatch(x, y, w, h);
    }
    return;
}
