#include "structs.h"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/SCRIPT/ANIMSCR.H"
#include "SRC/UI/MENULBL.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/SCRIPT/ADSCRIPT.H"

short g_nCreditsScrollYOffset;
short g_nCreditsMaxLabelHeight;

void menulbl_calc_max_label_width(void) {
    ImageRecord **table;
    int i;

    g_nCreditsMaxLabelHeight = 0;
    g_nCreditsScrollYOffset = 0;
    table = (ImageRecord **)g_pCurScriptObject->pAhPagedImage[g_pCurScriptAnimNode->wFld_14];
    for (i = 0; i < null_terminated_count(table); i++) {
        g_nCreditsMaxLabelHeight = table[i]->nWidth < g_nCreditsMaxLabelHeight
                                       ? g_nCreditsMaxLabelHeight
                                       : table[i]->nWidth;
    }
    return;
}

void menulbl_scroll_step_and_draw(int a, int b, int c) {
    ImageRecord **table;
    int count;
    int dst_y;
    int h;
    int adv;
    int i;
    unsigned flag;

    table = (ImageRecord **)g_pCurScriptObject->pAhPagedImage[g_pCurScriptAnimNode->wFld_14];
    if (table != 0) {
        count = null_terminated_count(table);
        if (count != 0) {
            dst_y = g_wScreen_height - g_nCreditsScrollYOffset;
            flag = 1;
            for (i = 0; i < count; i++) {
                if (dst_y > (int)g_wScreen_height) {
                    break;
                }
                h = table[i]->nWidth;
                adv = table[i]->nHeight;
                if (-g_nCreditsMaxLabelHeight < dst_y) {
                    blit_sprite_indirect((unsigned short)table[i], c, dst_y, 0);
                    adscript_op_noop(c, dst_y, h, adv);
                    flag = 0;
                }
                dst_y += a + adv;
            }
            g_nCreditsScrollYOffset += b;
            g_wScriptFrameHoldFlag |= flag;
        }
    }
    return;
}
