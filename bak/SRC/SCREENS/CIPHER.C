#include "globals.h"
#include "SRC/WORLD/LOOP/WORLDLP.H"
#include "SRC/INPUT/TIMER.H"
#include "structs.h"
#include "SRC/SCREENS/CIPHER.H"
#include "SRC/SYS/MEM.H"
#include "SRC/GFX/PALETTE/PALCYC.H"
#include "SRC/AUDIO/ENGINE/AUDIO.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/SPRITE/RECTSPR.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/GFX/RASTER/DRAWLINE.H"
#include "SRC/GFX/RASTER/PIXEL.H"
#include "SRC/STREAM/RESLOAD/FONTLOAD.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/GFX/SCREEN/DISSOLV.H"
#include "SRC/GAME/GSTATE.H"
#include "SRC/DIALOG/DIALOG.H"
#include "SRC/COMBAT/SPELL/SPELLFX.H"

unsigned char far *g_pCipherTextEnd;
char far *g_pCipherTextBase;
char far *g_apCipherDialRows[10];
int *g_pCipherLetterSlots;
int g_nCipherRowCount;
int g_nCipherRowWidth;

int far cipher_dial_puzzle_run(int nPuzzleId) {
    DDXRecord far *pRecord;
    char styleBuf[8];
    int nTrack;
    int nFontSaved;
    int nFontAlien;
    int nFontPuzzle;
    int nFontTmp;
    int nResult;
    int bLoopActive;
    int bNeedRedraw;
    int bWantRun;
    unsigned int nAction;
    unsigned char far *pPalSaved;
    unsigned char far *pPuzzlePalChunk;
    int nBlendSaved;
    ImageRecord **pImgTable;
    MenuPage *pPage;
    int i;

    nResult = 0;
    bLoopActive = 1;
    bNeedRedraw = 1;
    bWantRun = 1;

    palette_cycle_eb_toggle(0);

    nTrack = audio_music_play(0x3eb);
    dialog_play_record(0xbL, 1);
    screen_cursor_show_busy();
    screen_cursor_hide();
    audio_sfx_register_pair_4_18();
    pImgTable = resblit_load_asset_table("puzzle.bmx", 0);
    pRecord = dialog_load_record_by_key((long)(nPuzzleId - 1) + 0x19f0a1L, 0);
    cipher_puzzle_parse_table((unsigned char far *)pRecord + pRecord->bCnt1 * sizeof(DdxChoice) +
                              pRecord->bCnt2 * sizeof(DdxOp) + sizeof(DDXRecord));
    g_pCipherLetterSlots = galloc_safe_zcalloc(g_nCipherRowWidth << 1);
    for (i = 0; i < g_nCipherRowWidth; i++) {
        g_pCipherLetterSlots[i] = 0;
    }
    pPage = menupage_load("req_puzl.dat");
    menupage_begin(pPage);
    pPalSaved = palette_set((unsigned char far *)0);
    g_pPalQueuedForFlip = pPuzzlePalChunk = chunk_load_into_slot("puzzle.pal");
    nBlendSaved = g_nPalBlendMode;
    g_nPalBlendMode = 0;
    nFontSaved = font_activate(0);
    nFontAlien = font_load("alien.fnt");
    nFontPuzzle = font_load("puzzle.fnt");
    palette_fade_out(0, 0x100, -1, 0);
    palette_screen_clear_black();
    screen_cursor_restore_shape();
    screen_frame_flip();
    screen_cursor_show_busy();
    screen_cursor_hide();
    palette_set_scaled(0, 0x100, 0, 0);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    resblit_load_pal_or_stream("puzzle.scr");
    font_activate(nFontAlien);
    cipher_puzzle_layout_letters(pPage);
    dialog_apply_style_state(pRecord, styleBuf);
    dialog_render_text_with_tokens(pRecord, g_pCipherTextEnd, 0x41, 0, -1, 0);
    dialog_render_text_with_tokens(pRecord, g_pCipherTextEnd, 0x95, 0, 1, 0);
    dialog_render_text_with_tokens(pRecord, g_pCipherTextEnd, 0x10, 0, 0, 0);
    cipher_menu_draw_hotkey_labels(pPage);
    screen_cursor_restore_shape();
    screen_frame_flip();
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    screen_cursor_show_busy();
    palette_fade_in(0, 0x100, -1, 0);
    screen_cursor_restore_shape();
    font_activate(nFontSaved);
    dialog_play_record(0xcL, 1);

    if (gstate_is_party_member(1) != 0 || spellfx_event_mask_test_bit(4) != 0) {
        font_activate(nFontPuzzle);
        screen_cursor_hide();
        screen_frame_present();
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        resblit_load_pal_or_stream("puzzle.scr");
        cipher_puzzle_layout_letters(pPage);
        dialog_render_text_with_tokens(pRecord, g_pCipherTextEnd, 0x41, 0, -1, 0);
        dialog_render_text_with_tokens(pRecord, g_pCipherTextEnd, 0x95, 0, 1, 0);
        dialog_render_text_with_tokens(pRecord, g_pCipherTextEnd, 0x10, 0, 0, 0);
        cipher_menu_draw_hotkey_labels(pPage);
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaFrontPageBase;
        dissolve_transition_lfsr(0, 0, 0x140, 200);
        screen_cursor_hide();
    } else {
        font_activate(nFontAlien);
    }

    while (bLoopActive) {
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        if (bNeedRedraw) {
            menupage_draw(pPage);
        }
        screen_frame_present();
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        if (bNeedRedraw) {
            menupage_draw(pPage);
            bNeedRedraw = 0;
        }
        screen_frame_present();

        if (bWantRun) {
            if ((nResult = cipher_puzzle_is_solved()) == 1) {
                nAction = 0x12;
            } else {
                nAction = menupage_run(pPage, &bNeedRedraw);
            }
            bWantRun = 0;
        } else {
            nAction = menupage_run(pPage, &bNeedRedraw);
        }

        if (nAction >= 0x80 && nAction <= 0x93) {
            if (menupage_state_0e7c() == 1) {
                cipher_anim_bevel_text_dropin(menupage_state_0e80(), nAction - 0x80);
                bWantRun = 1;
            } else {

                nFontTmp = font_activate(0);
                font_activate(nFontSaved);
                dialog_play_record(0xcdL, 1);
                font_activate(nFontTmp);
            }
        } else if (nAction == 0x12) {
            if (menupage_state_0e7c() == 1) {
                bLoopActive = 0;
            } else {
                nFontTmp = font_activate(0);
                font_activate(nFontSaved);
                dialog_play_record(0xceL, 1);
                font_activate(nFontTmp);
            }
        }
    }

    screen_cur_set_shape_remember(0);
    font_activate(nFontSaved);
    if (nResult != 0) {

        g_nFrameTickCountdown = 0x96;
        while (g_nFrameTickCountdown != 0) {
            screen_frame_present();
        }
        audio_play(4);
        blit_sprite_indirect((unsigned short)pImgTable[0], 0x1e, 0x17, 0);
        screen_frame_present();
        blit_sprite_indirect((unsigned short)pImgTable[0], 0x1e, 0x17, 0);
        g_nFrameTickCountdown = 0x3c;
        while (g_nFrameTickCountdown != 0) {
            screen_frame_present();
        }
        audio_play(4);

        blit_sprite_indirect((unsigned short)pImgTable[1], 0x100, 0x14, 0);
        screen_frame_present();
        blit_sprite_indirect((unsigned short)pImgTable[1], 0x100, 0x14, 0);
        g_nFrameTickCountdown = 0xc8;
        while (g_nFrameTickCountdown != 0) {
            screen_frame_present();
        }
        dialog_play_record(0xeL, 1);
        screen_cursor_show_busy();
        palette_fade_out(0, 0x100, 4, 0);
        screen_cursor_restore_shape();
        screen_cursor_hide();
        palette_screen_clear_black();
        g_nPalBlendMode = nBlendSaved;
        g_pPalQueuedForFlip = pPalSaved;
        screen_frame_flip();
    } else {
        dialog_play_record(0xdL, 1);
        g_nPalBlendMode = nBlendSaved;
        g_pPalQueuedForFlip = pPalSaved;
    }
    g_nSceneReloadPending = 1;
    font_unload(nFontPuzzle);
    font_unload(nFontAlien);
    cache_release(pPuzzlePalChunk);
    menupage_end(pPage);
    menupage_free(pPage);
    galloc_zfree(g_pCipherLetterSlots);
    dialog_freemem_if_not_null(&pRecord->bStyle);
    free_image_record(pImgTable);
    audio_sfx_stop_pair_4_18();
    audio_music_play(nTrack);
    return nResult;
}

void far cipher_puzzle_parse_table(unsigned char far *pTableData) {
    g_pCipherTextBase = (char far *)pTableData;
    g_nCipherRowCount = g_nCipherRowWidth = 0;
    while (*pTableData != '\n') {
        g_nCipherRowWidth++;
        pTableData++;
    }
    pTableData += 3;
    while (*pTableData != '#') {
        g_apCipherDialRows[g_nCipherRowCount] = (char far *)pTableData;
        g_nCipherRowCount++;
        pTableData += g_nCipherRowWidth + 1;
    }
    pTableData += 2;
    g_pCipherTextEnd = pTableData;
}

void cipher_puzzle_layout_letters(MenuPage *page) {
    int nCellW;
    int nCellH;
    int nRowSpan;
    int i;
    int x;
    MenuEntry *pEntry;

    i = 0;
    pEntry = page->pEntries;
    nCellW = g_graphics_context.pFont_glyph_width_bits[0] + 6;
    nCellH = g_graphics_context.pFont_height[0] + 6;
    nRowSpan = g_nCipherRowWidth * (nCellW + 2) - 2;
    x = ((int)g_wScreen_width >> 1) - (nRowSpan >> 1);
    pEntry++;
    if (i < g_nCipherRowWidth) {
        do {
            if (g_pCipherTextBase[i] != ' ') {
                pEntry->rect.x = x;
                pEntry->rect.y = 0x57;
                pEntry->rect.width = nCellW;
                pEntry->rect.height = nCellH;
            } else {
                pEntry->wEnable_gate = 1;
            }
            x += nCellW + 2;
            pEntry++;
            i++;
        } while (i < g_nCipherRowWidth);
    }
    i++;
    while (i < (int)page->wEntry_count) {
        pEntry->wEnable_gate = 1;
        pEntry++;
        i++;
    }
}

int far cipher_puzzle_is_solved(void) {
    int i;

    for (i = 0; i < g_nCipherRowWidth; i++) {
        if (g_pCipherTextBase[i] != ' ' &&
            g_pCipherTextBase[i] != g_apCipherDialRows[g_pCipherLetterSlots[i]][i])
            return 0;
    }
    return 1;
}

void far cipher_anim_bevel_text_dropin(MenuEntry *pEntry, int nCol) {
    char szOut[2];
    char szIn[2];
    unsigned int xOut;
    unsigned int xIn;
    unsigned int y;
    int x0, y0, x1, y1;
    int i;

    szOut[0] = g_apCipherDialRows[g_pCipherLetterSlots[nCol]][nCol];
    szOut[1] = 0;
    g_pCipherLetterSlots[nCol]++;
    if (g_pCipherLetterSlots[nCol] == g_nCipherRowCount) {
        g_pCipherLetterSlots[nCol] = 0;
    }
    szIn[0] = g_apCipherDialRows[g_pCipherLetterSlots[nCol]][nCol];
    szIn[1] = 0;

    font_glyph_metrics(szOut[0], &xOut, &y);
    xOut = ((pEntry->rect.x + (pEntry->rect.width >> 1)) - ((int)xOut >> 1)) + 1;
    font_glyph_metrics(szIn[0], &xIn, &y);
    xIn = ((pEntry->rect.x + (pEntry->rect.width >> 1)) - ((int)xIn >> 1)) + 1;
    y = (pEntry->rect.y + (pEntry->rect.height >> 1)) - ((int)y >> 1);

    g_graphics_context.bText_style_flags = 1;
    x0 = pEntry->rect.x + 1;
    y0 = pEntry->rect.y + 1;
    x1 = pEntry->rect.x + pEntry->rect.width - 2;
    y1 = pEntry->rect.y + pEntry->rect.height - 2;
    for (i = 0; i < (int)(g_graphics_context.pFont_height[0] + 3); i++) {
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
            g_graphics_context.wVgaPage2Base;
        g_graphics_context.bClip_enabled = 0;
        cipher_draw_bevelled_box(pEntry->rect.x, pEntry->rect.y, pEntry->rect.width,
                                 pEntry->rect.height);
        g_graphics_context.bClip_enabled = 1;
        g_graphics_context.clip.xmin = x0;
        g_graphics_context.clip.ymin = y0;
        g_graphics_context.clip.xmax = x1;
        g_graphics_context.clip.ymax = y1;
        g_graphics_context.bText_fg_color = 'A';
        font_draw_text_ds(szIn, xIn, (y - g_graphics_context.pFont_height[0]) + -3);
        font_draw_text_ds(szOut, xOut, y - 1);
        g_graphics_context.bText_fg_color = 0x95;
        font_draw_text_ds(szIn, xIn, (y - g_graphics_context.pFont_height[0]) - 1);
        font_draw_text_ds(szOut, xOut, y + 1);
        g_graphics_context.bText_fg_color = 0x10;
        font_draw_text_ds(szIn, xIn, (y - g_graphics_context.pFont_height[0]) + -2);
        font_draw_text_ds(szOut, xOut, y);
        screen_frame_present();
        y++;
    }
    y--;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    g_graphics_context.bClip_enabled = 0;
    cipher_draw_bevelled_box(pEntry->rect.x, pEntry->rect.y, pEntry->rect.width,
                             pEntry->rect.height);
    g_graphics_context.bClip_enabled = 1;
    g_graphics_context.clip.xmin = x0;
    g_graphics_context.clip.ymin = y0;
    g_graphics_context.clip.xmax = x1;
    g_graphics_context.clip.ymax = y1;
    g_graphics_context.bText_fg_color = 'A';
    font_draw_text_ds(szIn, xIn, (y - g_graphics_context.pFont_height[0]) + -3);
    font_draw_text_ds(szOut, xOut, y - 1);
    g_graphics_context.bText_fg_color = 0x95;
    font_draw_text_ds(szIn, xIn, (y - g_graphics_context.pFont_height[0]) - 1);
    font_draw_text_ds(szOut, xOut, y + 1);
    g_graphics_context.bText_fg_color = 0x10;
    font_draw_text_ds(szIn, xIn, (y - g_graphics_context.pFont_height[0]) + -2);
    font_draw_text_ds(szOut, xOut, y);
    screen_frame_present();
}

void far cipher_menu_draw_hotkey_labels(MenuPage *page) {
    MenuEntry *pEntry;
    int i;
    char szGlyph[2];
    unsigned int x;
    unsigned int y;

    i = 0;
    pEntry = page->pEntries;
    g_graphics_context.bClip_enabled = '\0';
    g_graphics_context.bText_style_flags = '\x01';
    pEntry = pEntry + 1;
    szGlyph[1] = 0;
    if (i < g_nCipherRowWidth) {
        do {
            if (pEntry->wEnable_gate == 0) {
                cipher_draw_bevelled_box(pEntry->rect.x, pEntry->rect.y, pEntry->rect.width,
                                         pEntry->rect.height);
                szGlyph[0] = g_apCipherDialRows[g_pCipherLetterSlots[i]][i];
                font_glyph_metrics(szGlyph[0], &x, &y);
                x = ((pEntry->rect.x + (pEntry->rect.width >> 1)) - ((int)x >> 1)) + 1;
                y = (pEntry->rect.y + (pEntry->rect.height >> 1)) - ((int)y >> 1);
                g_graphics_context.bText_fg_color = 'A';
                font_draw_text_ds(szGlyph, x, y - 1);
                g_graphics_context.bText_fg_color = 0x95;
                font_draw_text_ds(szGlyph, x, y + 1);
                g_graphics_context.bText_fg_color = '\x10';
                font_draw_text_ds(szGlyph, x, y);
            }
            i = i + 1;
            pEntry = pEntry + 1;
        } while (i < g_nCipherRowWidth);
    }
    return;
}

void far cipher_draw_bevelled_box(int x, int y, int w, int h) {
    g_graphics_context.bGfx_fill_enabled = 1;
    g_graphics_context.bGfx_fill_color = 'w';
    g_graphics_context.bGfx_outline_color = 0x16;
    draw_rect_filled(x, y, w, h);

    g_graphics_context.bGfx_outline_color = 'A';
    draw_line(x, y + 1, x, y + h - 1);

    g_graphics_context.bGfx_outline_color = 0xb1;
    draw_line(x + w - 1, y, x + w - 1, y + h - 1);

    g_graphics_context.bGfx_outline_color = 0xd1;
    draw_line(x, y + h - 1, x + w - 1, y + h - 1);

    putpixel(x, y, 0x2c);
    putpixel(x + w - 1, y, 0x43);
    putpixel(x, y + h - 1, 0x6c);
    putpixel(x + w - 1, y + h - 1, 0xbb);
}
