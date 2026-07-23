#include "globals.h"
#include "SRC/GEN/GFXCTX.H"
#include "structs.h"
#include "SRC/SCRIPT/TTMDLG.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/GAME/GMAIN.H"
#include "SRC/R3D/CORE/R3D.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/GFX/SPRITE/BLITAA.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/SCRIPT/ADSCRIPT.H"

unsigned short g_wScriptEnhancedAuxFlag = 0x0000;
unsigned short g_nScriptEnhancedOpcodeDispatchEnabled = 0x0000;
unsigned short g_aTtmFadeStepTable[7] = {0x0000, 0x0050, 0x0014, 0x000a, 0x0005, 0x0002, 0x0001};

int far ttmscript_show_dialog_action(int arg, unsigned int mode) {
    register unsigned int img;

    img = g_pCurScriptObject->pAhPagedImage[0];

    if (arg == -1) {
        if (img = g_pCurScriptObject->pAhPagedImage[1])
            blit_sprite_aa_edges((ImageRecord *)(*(unsigned int *)img),
                                 0xa0 - ((ImageRecord *)*(unsigned int *)img)->nWidth / 2,
                                 0x70 - ((ImageRecord *)*(unsigned int *)img)->nHeight,
                                 g_pCurScriptObject->pCachedResource[0]);
        return;
    }
    if (arg == 0) {
        int xs[4];
        int ys[4];

        if (mode == 0xff) {
            unsigned char buf[320];
            int row;
            resblit_load_pal_or_stream("DIALOG.SCR");
            g_graphics_context.bClip_enabled = 0;
            g_graphics_context.bGfx_outline_color = 6;
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
            draw_rect_filled(0xe, 10, 0x123, 0x67);
            for (row = 0xb; row < 0x70; row++) {
                cga_save_rect_to_buffer((unsigned char far *)buf, 0xf, row, 0x121, 1);
                cga_rect_paste_from_buffer((unsigned char far *)buf, 0xf, row, 0x121, 1);
            }
            adscript_blit_full_other_page();
            return;
        }
        arg = (int)((unsigned long)mode * 0x333);
        if ((int)mode > 0x14)
            return;
        if (!img)
            return;

        xs[0] = xs[3] = 0;
        xs[1] = xs[2] = (int)((long)r3d_tbl_cos(arg) * 0x13f >> 0xe);
        {
            int sin_y = (int)((long)r3d_tbl_sin(arg) * 0x19 >> 0xe);
            ys[1] = (ys[0] = 0) - sin_y;
            ys[2] = (ys[3] = 199) + sin_y;
        }
        if (xs[0] > xs[1]) {
            register int tmp = xs[0];
            xs[0] = xs[3] = xs[1];
            xs[1] = xs[2] = tmp;
        }
        emsimg_gouraud_blit_paged((unsigned int *)*(unsigned int *)img, xs, ys);
        return;
    }

    switch (mode) {
    case 0:
    case 3: {
        long key;
        PDdxRecord rec;

        key = (long)arg + 1600000;
        g_graphics_context.clip.ymin = g_graphics_context.clip.xmin = 0;
        g_graphics_context.clip.ymax = 199;

        g_graphics_context.clip.xmax = 0x13f;
        if (rec = dialog_load_record_by_key((unsigned long)key, 0)) {
            font_activate(g_wGameFontSlot);
            g_graphics_context.wGfxBlitSrcPage = g_wVgaScratchPageBase;
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            gfx_present_dispatch(0, 0x73, 0x140, 0x55);
            dialog_render_text_with_tokens(rec, (char far *)0, -1, 0, 0, 0);
            g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaFrontPageBase;
            gfx_present_dispatch(0, 0x73, 0x140, 0x55);
            g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
            adscript_rndr_blit_other_page(0, 0x73, 0x140, 0x55);
            if (mode != 3)
                dialog_wait_for_acknowledge(100, 0, 1, 0);
            return dialog_freemem_if_not_null((unsigned char far *)rec);
        }
        break;
    }
    case 1:
        font_activate(g_wGameFontSlot);
        screen_cursor_set_hidden_flag(0);
        dialog_show_by_key((long)arg + 1600000, 0);
        screen_cursor_set_hidden_flag(1);
        break;
    case 2:
        gmain_play_chapter_intro(arg / 10, arg % 10);
        break;
    case 4:
        screen_cursor_set_hidden_flag(0);
        font_activate(g_wGameFontSlot);
        dialog_show_by_key((long)arg + 1600000, 0);
        screen_cursor_set_hidden_flag(1);
        break;
    case 5:
        screen_cursor_set_hidden_flag(0);
        font_activate(g_wGameFontSlot);
        dialog_play_record((long)arg + 1600000, 0);
        screen_cursor_set_hidden_flag(1);
        g_pPalQueuedForFlip = 0;
        break;
    }
}
