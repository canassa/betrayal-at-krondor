#include <conio.h>
#include "globals.h"
#include "SRC/COMBAT/GRID/CMBTGRID.H"
#include "SRC/WORLD/LOOP/WORLDLP.H"
#include "SRC/SYS/SYSLOWIO.H"
#include "SRC/INPUT/TIMER.H"
#include "structs.h"
#include "SRC/GFX/SCREEN/SCREEN.H"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/INPUT/KEYBOARD.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/INPUT/MOUSE.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/R3D/SCENE/WORLDHIT.H"
#include "SRC/UI/MENUPAGE.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/UI/UIWIDGET.H"
#include "SRC/COMBAT/SPELL/SPELLFX.H"

CursorState g_cursor_prev_x[2];
unsigned char far *g_pActiveCursorBuf;
unsigned char far *g_pCursorScratchBuf1;
unsigned char far *g_pCursorScratchBuf2;

short g_cursor_hidden = 1;
short g_cursor_prev_shape = 0;
ImageRecord **g_cursor_state = {0};
unsigned char far *g_pPalQueuedForFlip = {0};
short g_nCursorX = 0;
short g_nCursorY = 0;
unsigned short g_nCursorStateSaved = 0x0000;
unsigned char far *g_pSavedCursorBuf1 = {0};
unsigned char far *g_pSavedCursorBuf2 = {0};

int screen_cursor_get_position(short *out_x, short *out_y) {
    if (g_mouse_installed) {
        return mouse_get_position((unsigned int *)out_x, (unsigned int *)out_y);
    }
    *out_x = g_nCursorX;
    *out_y = g_nCursorY;
    return 1;
}

int screen_cursor_set_position(int x, int y) {
    if (g_mouse_installed != '\0') {
        return mouse_set_position(x, y);
    }
    if (x < 0) {
        x = 0;
    }

    if (0x13f < x) {
        x = 0x13f;
    }
    if (y < 0) {
        y = 0;
    }
    if (199 < y) {
        y = 199;
    }
    g_nCursorX = x;
    g_nCursorY = y;
    return 1;
}

void screen_cursor_set_hidden_flag(int hidden) {
    g_cursor_hidden = hidden;
}

short screen_cursor_get_x(void) {
    return g_cursor_prev_x[1].nX;
}

short screen_cursor_get_y(void) {
    return g_cursor_prev_x[1].nY;
}

ImageRecord **screen_cursor_state_get(void) {
    return g_cursor_state;
}

void screen_cur_set_shape_remember(int shape_id) {
    screen_cursor_set_shape(shape_id);
    g_cursor_prev_shape = g_cursor_prev_x[1].shape;
}

void screen_cursor_set_shape(int shape_id) {
    g_cBusyCursorShown = 0;
    if (0 < shape_id && shape_id < null_terminated_count(g_cursor_state)) {
        g_cursor_prev_x[1].shape = shape_id;
        if (shape_id >= 2) {
            g_cursor_prev_x[1].nHotX = g_cursor_state[shape_id]->nWidth / 2;
            g_cursor_prev_x[1].nHotY = g_cursor_state[shape_id]->nHeight / 2;
        } else {
            g_cursor_prev_x[1].nHotX = g_cursor_prev_x[1].nHotY = 0;
        }
    } else {
        g_cursor_prev_x[1].shape = g_cursor_prev_x[1].nHotX = g_cursor_prev_x[1].nHotY = 0;
        if (shape_id < 0) {
            g_cursor_prev_x[1].shape = g_cursor_prev_shape;
        }
    }
    g_cursor_prev_x[1].nWidth = g_cursor_state[g_cursor_prev_x[1].shape]->nWidth;
    g_cursor_prev_x[1].nHeight = g_cursor_state[g_cursor_prev_x[1].shape]->nHeight;
    return;
}

int screen_input_poll_confirm_cancel(void) {
    int result;

    result = 0;
    if (mouse_button_pressed(0) || key_is_down(0x4c) || key_is_down(0x52)) {
        result = 1;
    } else if (mouse_button_pressed(1) || key_is_down(0x4e)) {
        result = 2;
    }
    return result;
}

void screen_cursor_load_pack(int pack_id) {
    int i;
    int sz;
    int count;
    int maxSize;

    switch (pack_id) {
    case 0:
        g_cursor_state = resblit_load_asset_table("pointer.bmp", 0);
        break;
    case 1:
        g_cursor_state = resblit_load_asset_table("pointerg.bmp", 0);
        break;
    }

    count = null_terminated_count(g_cursor_state);
    i = maxSize = 0;
    for (; i < count; i++) {
        if ((sz = (int)rect_byte_size(g_cursor_state[i]->nWidth, g_cursor_state[i]->nHeight)) >
            maxSize) {
            maxSize = sz;
        }
    }

    screen_cursor_get_position(&g_cursor_prev_x[1].nX, &g_cursor_prev_x[1].nY);
    screen_cur_set_shape_remember(0);
    g_cursor_prev_x[0] = g_cursor_prev_x[1];

    g_pCursorScratchBuf1 = g_pActiveCursorBuf = alloc_far((long)maxSize, 0);
    g_pCursorScratchBuf2 = alloc_far((long)maxSize, 0);

    cga_save_rect_to_buffer(g_pCursorScratchBuf1, g_cursor_prev_x[1].nX, g_cursor_prev_x[1].nY,
                            g_cursor_prev_x[1].nWidth, g_cursor_prev_x[1].nHeight);
    cga_save_rect_to_buffer(g_pCursorScratchBuf2, g_cursor_prev_x[1].nX, g_cursor_prev_x[1].nY,
                            g_cursor_prev_x[1].nWidth, g_cursor_prev_x[1].nHeight);
}

void screen_cursor_unload_pack(void) {
    _freemem(g_pCursorScratchBuf2);
    _freemem(g_pCursorScratchBuf1);
    free_image_record(g_cursor_state);
    g_cursor_state = 0;
    return;
}

void screen_cursor_state_push_pop(int restore) {
    if (restore != 0) {

        g_nCursorStateSaved = (unsigned short)g_cursor_state;
        g_pSavedCursorBuf1 = g_pCursorScratchBuf1;
        g_pSavedCursorBuf2 = g_pCursorScratchBuf2;
        g_cursor_state = (ImageRecord **)0;
        g_pActiveCursorBuf = g_pCursorScratchBuf1 = g_pCursorScratchBuf2 = (unsigned char far *)0;
    } else {

        g_cursor_state = (ImageRecord **)g_nCursorStateSaved;
        g_pActiveCursorBuf = g_pCursorScratchBuf1 = g_pSavedCursorBuf1;
        g_pCursorScratchBuf2 = g_pSavedCursorBuf2;
        g_nCursorStateSaved = 0;
        g_pSavedCursorBuf1 = g_pSavedCursorBuf2 = (unsigned char far *)0;

        screen_cursor_get_position(&g_cursor_prev_x[1].nX, &g_cursor_prev_x[1].nY);
        screen_cur_set_shape_remember(0);
        g_cursor_prev_x[0] = g_cursor_prev_x[1];

        cga_save_rect_to_buffer(g_pCursorScratchBuf1, g_cursor_prev_x[1].nX, g_cursor_prev_x[1].nY,
                                g_cursor_prev_x[1].nWidth, g_cursor_prev_x[1].nHeight);
        cga_save_rect_to_buffer(g_pCursorScratchBuf2, g_cursor_prev_x[1].nX, g_cursor_prev_x[1].nY,
                                g_cursor_prev_x[1].nWidth, g_cursor_prev_x[1].nHeight);
    }
}

void screen_cursor_hide(void) {
    g_cursor_prev_x[0].nX = -999;
}

void screen_cursor_draw(CursorState *cursor_rec, unsigned char far *buf) {
    int x_start;
    int row;

    x_start = cursor_rec->nX - cursor_rec->nHotX;
    row = cursor_rec->nY - cursor_rec->nHotY;
    if (x_start < 0) {
        x_start = 0;
    }
    if (row < 0) {
        row = 0;
    }
    cga_save_rect_to_buffer(buf, x_start, row, cursor_rec->nWidth, cursor_rec->nHeight);
    return;
}

void screen_cursor_restore_background(CursorState *cur, unsigned char far *pBgBuffer) {
    int x;
    int row;

    x = cur->nX - cur->nHotX;
    row = cur->nY - cur->nHotY;
    if (x < 0) {
        x = 0;
    }
    if (row < 0) {
        row = 0;
    }
    if (row + cur->nHeight > (int)g_wScreen_height - 1) {
        cga_rect_paste_from_buffer(pBgBuffer, x, row, cur->nWidth, g_wScreen_height - row);
    } else {
        cga_rect_paste_from_buffer(pBgBuffer, x, row, cur->nWidth, cur->nHeight);
    }
}

void screen_cur_refr_during_long_op(void) {
    unsigned char far *pBgBuffer;
    short savedClipXmin;
    short savedClipYmin;
    short savedClipXmax;
    short savedClipYmax;
    short savedClipEnabled;

    screen_cursor_get_position(&g_cursor_prev_x[1].nX, &g_cursor_prev_x[1].nY);

    if (g_cursor_prev_x[0].nX == g_cursor_prev_x[1].nX &&
        g_cursor_prev_x[0].nY == g_cursor_prev_x[1].nY)
        return;

    savedClipEnabled = (signed char)g_graphics_context.bClip_enabled;
    savedClipXmin = g_graphics_context.clip.xmin;
    savedClipYmin = g_graphics_context.clip.ymin;
    savedClipXmax = g_graphics_context.clip.xmax;
    savedClipYmax = g_graphics_context.clip.ymax;

    g_graphics_context.bClip_enabled = 1;
    g_graphics_context.clip.xmin = g_graphics_context.clip.ymin = 0;
    g_graphics_context.clip.xmax = g_wScreen_width - 1;
    g_graphics_context.clip.ymax = g_wScreen_height - 1;

    asm cld;

    if ((unsigned char huge *)g_pActiveCursorBuf == (unsigned char huge *)g_pCursorScratchBuf1)
        pBgBuffer = g_pCursorScratchBuf2;
    else
        pBgBuffer = g_pCursorScratchBuf1;

    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage =
        g_graphics_context.wVgaFrontPageBase;

    if (g_cursor_prev_x[0].nX != -999) {
        screen_cursor_restore_background(&g_cursor_prev_x[0], pBgBuffer);
    }

    g_cursor_prev_x[0] = g_cursor_prev_x[1];

    screen_cursor_draw(&g_cursor_prev_x[1], pBgBuffer);

    if (g_cursor_hidden != 0 && g_cursor_prev_x[1].shape != 2) {
        blit_sprite_indirect((unsigned short)g_cursor_state[g_cursor_prev_x[1].shape],
                             g_cursor_prev_x[1].nX - g_cursor_prev_x[1].nHotX,
                             g_cursor_prev_x[1].nY - g_cursor_prev_x[1].nHotY, 0);
    }

    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;

    g_graphics_context.bClip_enabled = (unsigned char)savedClipEnabled;
    g_graphics_context.clip.xmin = savedClipXmin;
    g_graphics_context.clip.ymin = savedClipYmin;
    g_graphics_context.clip.xmax = savedClipXmax;
    g_graphics_context.clip.ymax = savedClipYmax;
}

void far screen_frame_present(void) {
    g_cBusyCursorShown = 0;
    g_graphics_context.bClip_enabled = 1;
    g_graphics_context.clip.xmin = g_graphics_context.clip.ymin = 0;
    g_graphics_context.clip.xmax = g_wScreen_width - 1;
    g_graphics_context.clip.ymax = g_wScreen_height - 1;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    screen_cursor_get_position(&g_cursor_prev_x[1].nX, &g_cursor_prev_x[1].nY);
    screen_cursor_draw(&g_cursor_prev_x[1], g_pActiveCursorBuf);
    if (g_cursor_prev_x[0].nX != -999 && g_cursor_hidden != 0 && g_cursor_prev_x[1].shape != 2) {
        blit_sprite_indirect((unsigned short)g_cursor_state[g_cursor_prev_x[1].shape],
                             g_cursor_prev_x[1].nX - g_cursor_prev_x[1].nHotX,
                             g_cursor_prev_x[1].nY - g_cursor_prev_x[1].nHotY, 0);
    }
    screen_frame_flip();
    if ((unsigned char huge *)g_pActiveCursorBuf == (unsigned char huge *)g_pCursorScratchBuf1)
        g_pActiveCursorBuf = g_pCursorScratchBuf2;
    else
        g_pActiveCursorBuf = g_pCursorScratchBuf1;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    if (g_cursor_prev_x[0].nX != -999) {
        screen_cursor_restore_background(&g_cursor_prev_x[0], g_pActiveCursorBuf);
    }
    g_cursor_prev_x[0] = g_cursor_prev_x[1];
}

void far screen_frame_sync_buffers_rect(int row_start, int row_count) {
    asm mov dx, 050h;
    asm mov ax, word ptr row_start;
    asm imul dx;
    asm mov word ptr row_start, ax;
    asm mov dx, 050h;
    asm mov ax, word ptr row_count;
    asm imul dx;
    asm mov word ptr row_count, ax;

    outpw(0x3c4, 0xf02);
    outpw(0x3ce, 0x4105);

    asm mov di, word ptr row_start;
    asm mov si, di;
    asm mov cx, word ptr row_count;
    asm push ds;
    asm mov es, word ptr[g_graphics_context.wVgaPage2Base];
    asm mov ds, word ptr[g_graphics_context.wVgaFrontPageBase];
    asm rep movsb;
    asm pop ds;

    asm mov ax, 04005h;
    asm out dx, ax;

    if (g_cursor_prev_x[1].nX != -999) {
        if ((unsigned char huge *)g_pActiveCursorBuf == (unsigned char huge *)g_pCursorScratchBuf1)
            screen_cursor_restore_background(&g_cursor_prev_x[1], g_pCursorScratchBuf2);
        else
            screen_cursor_restore_background(&g_cursor_prev_x[1], g_pCursorScratchBuf1);
    }
}

void screen_clear_both_pages(void) {
    int i;

    i = 0;
    do {
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage1Base;
        g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
        gfx_present_dispatch(0, 0, 0x140, 200);
        screen_frame_present();
        i++;
    } while (i < 2);
}

void screen_clear_back_buffer(void) {
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
}

void far screen_render_main_frame(char *menu_only) {
    g_cBusyCursorShown = 0;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    if (menu_only != 0) {
        resblit_load_pal_or_stream(menu_only);
    } else {
        resblit_load_pal_or_stream("FRAME.SCR");
        if (g_wSaveSlotDirValid != 0) {
            g_pReqMainPage->pEntries[7].wEnable_gate = 0;
        } else {
            g_pReqMainPage->pEntries[7].wEnable_gate = 1;
        }
        if (g_full_redraw_needed != 0) {
            menupage_draw(g_pReqMapPage);
        } else {
            menupage_draw(g_pReqMainPage);
        }
        uiwidget_compass_draw();
        world_render_scene_dispatch(0);
        spellfx_draw_events_caption();
    }
    screen_frame_flip();
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaFrontPageBase;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    gfx_present_dispatch(0, 0, 0x140, 200);
    screen_cursor_hide();
    screen_frame_present();
}

void screen_cursor_show_busy(void) {
    if (!g_cBusyCursorShown) {
        screen_cursor_set_shape(2);
        screen_frame_present();
        g_cBusyCursorShown = 1;
    }
}

void screen_cursor_restore_shape(void) {
    screen_cursor_set_shape(-1);
}

void far screen_scene_reset_clip_cur(void) {
    g_cBusyCursorShown = 0;
    g_graphics_context.bClip_enabled = 1;
    g_graphics_context.clip.xmin = g_graphics_context.clip.ymin = 0;
    g_graphics_context.clip.xmax = g_wScreen_width - 1;
    g_graphics_context.clip.ymax = g_wScreen_height - 1;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;
    vsync_hook(1);
    if ((unsigned char huge *)g_pActiveCursorBuf == (unsigned char huge *)g_pCursorScratchBuf1) {
        g_pActiveCursorBuf = g_pCursorScratchBuf2;
    } else {
        g_pActiveCursorBuf = g_pCursorScratchBuf1;
    }
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage2Base;
    if (g_cursor_prev_x[0].nX != -999) {
        screen_cursor_restore_background(&g_cursor_prev_x[0], g_pActiveCursorBuf);
        g_cursor_prev_x[0].nX = -999;
    }
}

void far screen_wipe_horizontal(int x, int y, int w, int h) {
    int center;
    int left_x;
    int step;

    g_graphics_context.bClip_enabled = 1;
    g_graphics_context.clip.xmin = g_graphics_context.clip.ymin = 0;
    g_graphics_context.clip.xmax = g_wScreen_width - 1;
    g_graphics_context.clip.ymax = g_wScreen_height - 1;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;

    screen_cursor_draw(&g_cursor_prev_x[0], g_pActiveCursorBuf);

    if (g_cursor_hidden != 0 && g_cursor_prev_x[0].shape != 2) {
        blit_sprite_indirect((unsigned short)g_cursor_state[g_cursor_prev_x[0].shape],
                             g_cursor_prev_x[0].nX - g_cursor_prev_x[0].nHotX,
                             g_cursor_prev_x[0].nY - g_cursor_prev_x[0].nHotY, 0);
    }

    g_graphics_context.clip.xmax = x + w;
    g_graphics_context.clip.ymax = y + h;
    g_graphics_context.clip.xmin = x;
    g_graphics_context.clip.ymin = y;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaFrontPageBase;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;

    step = w / 0x4c;
    center = x + (w >> 1);
    for (left_x = center - step; left_x >= x; left_x -= step) {
        g_nFrameTickCountdown = 1;
        gfx_present_dispatch(left_x, y, step, h);
        gfx_present_dispatch(center + (center - left_x) - step, y, step, h);
        do {
        } while (g_nFrameTickCountdown != 0);
    }

    g_graphics_context.clip.xmin = g_graphics_context.clip.ymin = 0;
    g_graphics_context.clip.xmax = g_wScreen_width - 1;
    g_graphics_context.clip.ymax = g_wScreen_height - 1;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wGfxBlitSrcPage =
        g_graphics_context.wVgaPage2Base;

    screen_cursor_restore_background(&g_cursor_prev_x[0], g_pActiveCursorBuf);

    if ((unsigned char huge *)g_pActiveCursorBuf == (unsigned char huge *)g_pCursorScratchBuf1) {
        g_pActiveCursorBuf = g_pCursorScratchBuf2;
    } else {
        g_pActiveCursorBuf = g_pCursorScratchBuf1;
    }

    g_graphics_context.bClip_enabled = 0;
}

void screen_frame_flip(void) {
    if ((g_pPalQueuedForFlip != (unsigned char far *)0) && (g_nPalBlendMode != 0)) {
        palette_blend_with_daynight(g_pPalQueuedForFlip);
    }
    vsync_hook(1);
    if (g_pPalQueuedForFlip != (unsigned char far *)0) {
        if (g_nPalBlendMode != 0) {
            palette_apply_cycled();
        } else {
            palette_set(g_pPalQueuedForFlip);
        }
        g_pPalQueuedForFlip = (unsigned char far *)0;
    }
}
