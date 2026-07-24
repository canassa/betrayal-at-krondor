#include <dos.h>
#include <mem.h>

#include "gtypes.h"
#include "structs.h"
#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"

#include "SRC/SCRIPT/ADSCRIPT.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/GFX/DRIVER/PALDRV.H"
#include "SRC/GFX/RASTER/PRESENT.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/STREAM/RESLOAD/FONTLOAD.H"
#include "SRC/STREAM/RESLOAD/IFFREAD.H"
#include "SRC/STREAM/CODEC/STREAM.H"
#include "SRC/GFX/PALETTE/PALETTE.H"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/SCRIPT/TTM.H"


extern char g_aTtmTextBuf0[41];
extern char g_aTtmTextBuf1[41];
unsigned short g_aTtmTextStringOffsets[9] = {(unsigned short)g_aTtmTextBuf0,
                                             (unsigned short)g_aTtmTextBuf1,
                                             0x0000,
                                             0x0000,
                                             0x0000,
                                             0x0000,
                                             0x0000,
                                             0x0000,
                                             0x0000};
ScriptObject far *g_pScriptObjectListHead = {0};
ScriptObject far *g_pCurScriptObject = {0};
ScriptAnimNode *g_pScriptObjectChainHead = {0};
ScriptAnimNode *g_pCurScriptAnimNode = {0};
unsigned char g_bTtmViewportClampFlag = 0x00;
unsigned short g_nVgaRenderMode = 0x0004;

char g_aTtmTextBuf0[41] = "1234567890123456789012345678901234567890";
char g_aTtmTextBuf1[41] = "1234567890123456789012345678901234567890";

void adscript_set_dbb_if_202d_eq_0c(void) {
    if (g_graphics_context.bVideoAdapter == 0x0c) {
        g_nVgaRenderMode = 2;
    }
}

int adscript_resource_load(FileRef *file) {
    int tt3_bytes_read;
    int tt3_stream_size;
    char far *tt3_buf;
    unsigned long tt3_size_packed;
    int stream_id;
    int was_opened;
    int page_count;
    ScriptObject far *pTail;

    tt3_buf = (char far *)0L;
    if (!is_file_cached(file)) {
        file = cached_file_open(file);
        was_opened = 1;
    } else {
        was_opened = 0;
    }
    if (!file) {
        return -1;
    }
    if (chunk_seek(file, "PAG:", 0) == -1L) {

        page_count = 0x14a;
    } else {
        bak_fread(&page_count, 2, 1, file);
        page_count = page_count;
    }
    if (chunk_seek(file, "TT3:", 0) == -1L) {
        if (was_opened)
            cached_file_close(file);
        return -1;
    }
    tt3_size_packed = cached_file_chunk_size(file);
    stream_id = stream_open(-1, file, "r", tt3_size_packed);
    if (stream_id < 0) {
        if (was_opened)
            cached_file_close(file);
        return -1;
    }
    tt3_stream_size = (int)stream_size(stream_id);
    tt3_buf = (char far *)alloc_far((unsigned long)tt3_stream_size, 0L);
    if (tt3_buf == (char far *)0L) {
        stream_close(stream_id);
        if (was_opened)
            cached_file_close(file);
        return -1;
    }
    tt3_bytes_read = (int)stream_read(stream_id, tt3_buf, (unsigned int)tt3_stream_size);
    stream_close(stream_id);
    if (was_opened)
        cached_file_close(file);
    if (tt3_bytes_read != tt3_stream_size) {
        _freemem(tt3_buf);
        return -1;
    }
    if (g_pScriptObjectListHead == (ScriptObject far *)0L) {
        g_pScriptObjectListHead =
            (ScriptObject far *)alloc_far(sizeof(ScriptObject), ALLOC_FAR_ZERO_FILL);
        g_pCurScriptObject = g_pScriptObjectListHead;
    } else {
        pTail = g_pScriptObjectListHead;
        while ((ScriptObject far *)pTail->pNext != (ScriptObject far *)0L) {
            pTail = (ScriptObject far *)pTail->pNext;
        }
        g_pCurScriptObject = (ScriptObject far *)(pTail->pNext = (unsigned char far *)alloc_far(
                                                      sizeof(ScriptObject), ALLOC_FAR_ZERO_FILL));
    }
    if (g_pCurScriptObject == (ScriptObject far *)0L) {
        return -1;
    }
    g_pCurScriptObject->nBlockCount = (short)page_count;
    g_pCurScriptObject->pBlocks = (ScriptBlock far *far *)alloc_far(
        (unsigned long)((unsigned int)(page_count + 1) << 2), ALLOC_FAR_ZERO_FILL);
    g_pCurScriptObject->pTt3_data = (unsigned char far *)tt3_buf;
    g_pCurScriptObject->pTt3_end = (unsigned char far *)(tt3_buf + (unsigned int)tt3_stream_size - 1);
    if (g_pCurScriptObject->pBlocks == (ScriptBlock far *far *)0L) {
        return -1;
    }
    g_pCurScriptObject->wResourceId = 0;
    return 1;
}

int adscript_select_object(int id) {
    g_pCurScriptObject = g_pScriptObjectListHead;
    while (g_pCurScriptObject != (ScriptObject far *)0L) {
        if (g_pCurScriptObject->wResourceId == id)
            return 1;
        g_pCurScriptObject = (ScriptObject far *)g_pCurScriptObject->pNext;
    }
    return 0;
}

static void adscript_object_chain_append(unsigned short id_a, unsigned short tag, unsigned short id_b) {
    ScriptAnimNode *pTail;

    if (g_pScriptObjectChainHead == (ScriptAnimNode *)0x0) {
        g_pCurScriptAnimNode = g_pScriptObjectChainHead = my_malloc(0x3d);
    } else {
        pTail = g_pScriptObjectChainHead;
        for (; pTail->pNext != (ScriptAnimNode *)0x0; pTail = pTail->pNext) {
        }
        g_pCurScriptAnimNode = pTail->pNext = my_malloc(0x3d);
    }
    if (g_pCurScriptAnimNode != (ScriptAnimNode *)0x0) {
        memset(g_pCurScriptAnimNode, 0, 0x3d);
        g_pCurScriptAnimNode->wPcSaved = id_a;
        g_pCurScriptAnimNode->wPc = id_a;
        g_pCurScriptAnimNode->wTag = tag;
        g_pCurScriptAnimNode->wIdB = id_b;
        g_pCurScriptAnimNode->wDispatchPc = 0xffff;
    }
    return;
}

char far *adscript_skip_aligned_cstring(char far *p) {
    int count;

    count = 0;
    while (*p++ != '\0') {
        count++;
    }
    if (!(count & 1)) {
        p++;
    }
    return p;
}

short adscript_channel_dispatch_loop(unsigned short script_obj_id) {
    unsigned char far *saved;
    unsigned char far *cur;
    short bi;
    unsigned short id_a;
    unsigned short cx;
    unsigned short dx;

    id_a = 0;
    if (adscript_select_object(script_obj_id) && g_pCurScriptObject != (ScriptObject far *)0L &&
        g_pCurScriptObject->pTt3_data != (unsigned char far *)0L) {

        saved = cur = g_pCurScriptObject->pTt3_data;

        for (bi = 0; g_pCurScriptObject->nBlockCount >= bi; bi++) {
            g_pCurScriptObject->pBlocks[bi] = (ScriptBlock far *)0L;
        }

        for (bi = 0; g_pCurScriptObject->nBlockCount > bi; bi++) {
            g_pCurScriptObject->pBlocks[bi] = (ScriptBlock far *)cur;

            for (;;) {
                if (FP_OFF(g_pCurScriptObject->pTt3_end) <= FP_OFF(cur))
                    return 0;
                FP_OFF(cur) += 2;
                cx = *(unsigned short far *)saved;

                if (cx == 0xff0) {

                    id_a++;
                    saved = cur;
                    break;
                }

                dx = cx & 0xf;
                switch (dx) {
                case 15:

                    if (cx == 0xaf1f || cx == 0xaf2f) {
                        dx = *(unsigned short far *)cur;
                        dx <<= 1;
                        do {
                            FP_OFF(cur) += 2;
                        } while (dx--);
                    } else {
                        cur = (unsigned char far *)adscript_skip_aligned_cstring((char far *)cur);
                    }
                    break;

                case 1:

                    dx = *(unsigned short far *)cur;
                    FP_OFF(cur) += 2;
                    if (cx == 0x1111)
                        adscript_object_chain_append(id_a, script_obj_id, dx);
                    break;

                case 2:
                case 3:
                case 4:
                case 5:
                case 6:
                case 7:

                    FP_OFF(cur) += dx * 2;
                    break;

                default:

                    return (short)-1;

                case 0:

                    break;
                }

                saved = cur;
            }
        }
        return 1;
    }
    return 0;
}

int adscript_run_then_apply_palette(int block_index) {
    int result;
    result = adscript_run_by_index(block_index);
    adscript_apply_pending_palette();
    return result;
}

int adscript_run_by_index(int block_index) {
    int result = 0;
    if (g_pCurScriptObject != 0 && g_pCurScriptObject->nBlockCount > block_index &&
        block_index >= 0 && g_pCurScriptObject->pBlocks[block_index] != 0)
        result = ttmscript_interpret_loop(block_index);
    return result;
}

void adscript_apply_pending_palette(void) {
    if (g_pPendingPalette != (unsigned char far *)0) {
        palette_set(g_pPendingPalette);
        g_pPendingPalette = (unsigned char far *)0;
    }
}

void adscript_drain_object_list(void) {
    while (g_pScriptObjectListHead != (ScriptObject far *)0x0) {
        adscript_object_unload(g_pScriptObjectListHead->wResourceId);
    }
    g_pCurScriptAnimNode = g_pScriptObjectChainHead;
    while (g_pCurScriptAnimNode != (ScriptAnimNode *)0x0) {
        g_pScriptObjectChainHead = g_pCurScriptAnimNode->pNext;
        my_free(g_pCurScriptAnimNode);
        g_pCurScriptAnimNode = g_pScriptObjectChainHead;
    }
}

void adscript_object_unload(int resourceId) {
    int i;
    ScriptObject far *pCur;
    ScriptObject far *pPrev;

    g_bPaletteCycleEbActive = 0;

    if (adscript_select_object(resourceId) != 0) {
        ttmscript_sfx_channels_stop_all();

        for (i = 0; i < 6; i++) {
            if (g_pCurScriptObject->pAhFont[i] != 0) {
                font_unload(g_pCurScriptObject->pAhFont[i]);
                g_pCurScriptObject->pAhFont[i] = 0;
            }
        }

        for (i = 0; i < 6; i++) {
            if (g_pCurScriptObject->pAhPagedImage[i] != 0) {
                emsimg_free_paged((void *)g_pCurScriptObject->pAhPagedImage[i]);
                g_pCurScriptObject->pAhPagedImage[i] = 0;
            }
        }

        for (i = 0; i < 6; i++) {
            if (g_pCurScriptObject->pCachedResource[i] != 0) {
                if (g_pCurScriptObject->pCachedResource[i] == g_pPendingPalette)
                    g_pPendingPalette = 0;
                cache_release(g_pCurScriptObject->pCachedResource[i]);
                g_pCurScriptObject->pCachedResource[i] = 0;
            }
        }

        for (i = 0; i < 12; i++) {
            if (g_pCurScriptObject->pFreemem[i] != 0) {
                _freemem(g_pCurScriptObject->pFreemem[i]);
                g_pCurScriptObject->pFreemem[i] = 0;
            }
        }

        if (g_pCurScriptObject->pBlocks != 0)
            _freemem(g_pCurScriptObject->pBlocks);
        g_pCurScriptObject->pBlocks = 0;

        if (g_pCurScriptObject->pTt3_data != 0)
            _freemem(g_pCurScriptObject->pTt3_data);
        g_pCurScriptObject->pTt3_data = 0;

        if (g_pCurScriptObject == g_pScriptObjectListHead) {
            g_pScriptObjectListHead = (ScriptObject far *)g_pCurScriptObject->pNext;
        } else {
            pPrev = 0;
            pCur = g_pScriptObjectListHead;
            while (pCur != 0) {
                if (pCur == g_pCurScriptObject)
                    break;
                pPrev = pCur;
                pCur = (ScriptObject far *)pCur->pNext;
            }
            pPrev->pNext = pCur->pNext;
        }

        g_pCurScriptObject->pNext = 0;
        _freemem(g_pCurScriptObject);
    }
}

void adscript_renderer_reset(void) {
    adscript_drain_object_list();
    return;
}

void adscript_blit_full_other_page(void) {
    adscript_rndr_blit_other_page(0, 0, 320, 200);
}

void adscript_rndr_blit_other_page(int x, int y, int w, int h) {
    unsigned short savedSrcPage;
    unsigned short savedDstPage;

    savedSrcPage = g_graphics_context.wGfxBlitSrcPage;
    savedDstPage = g_graphics_context.wGfxBlitDstPage;
    g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wVgaPage2Base;
    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    gfx_present_dispatch(x, y, w, h);
    g_graphics_context.wGfxBlitSrcPage = savedSrcPage;
    g_graphics_context.wGfxBlitDstPage = savedDstPage;
    return;
}

void adscript_op_noop(int a, int b, int c, int d) {
    return;
}
