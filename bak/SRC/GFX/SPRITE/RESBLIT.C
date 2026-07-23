#include <dos.h>
#include <stdlib.h>
#include <string.h>

#include "globals.h"
#include "SRC/GAME/GMAIN.H"
#include "SRC/GEN/GFXCTX.H"
#include "SRC/SCREENS/INVENTOR.H"
#include "structs.h"
#include "SRC/GFX/SPRITE/RESBLIT.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/GFX/SPRITE/DECOMP.H"
#include "SRC/GFX/DRIVER/VTHUNKS.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/GFX/DRIVER/VIDINIT.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/STREAM/CODEC/STREAM.H"
#include "SRC/SYS/EMS.H"
#include "SRC/SYS/EMSIMG.H"

int g_nDialogScxEmsHandle = 0;
int g_nInventorScxEmsHandle = 0;
int g_nFrameScxEmsHandle = 0;

ImageRecord **g_pHeadsBmxAssetTable = 0;

void resblit_alloc_ems_64k(char *path, int *out_handle) {
    unsigned char far *dest_far;
    unsigned short saved_src_page;

    g_graphics_context.wGfxBlitDstPage = g_graphics_context.wVgaPage1Base;
    resblit_load_pal_or_stream(path);
    if ((*out_handle = ems_alloc_pages(65000)) != 0) {
        saved_src_page = g_graphics_context.wGfxBlitSrcPage;
        g_graphics_context.wGfxBlitSrcPage = g_graphics_context.wGfxBlitDstPage;
        dest_far = ems_map_resource_pages(*out_handle);
        cga_save_rect_to_buffer(dest_far, 0, 0, 320, 200);
        g_graphics_context.wGfxBlitSrcPage = saved_src_page;
    }
    return;
}

void resblit_load_resource_set_1ec(int flags) {
    g_pInvSpriteLoAssetTable = resblit_load_asset_table("INVSHP1.BMX", 1);
    g_pInvSpriteHiAssetTable = resblit_load_asset_table("INVSHP2.BMX", 1);
    g_pHeadsBmxAssetTable = resblit_load_asset_table("HEADS.BMX", 1);
    resblit_alloc_ems_64k("DIALOG.SCX", &g_nDialogScxEmsHandle);
    if (flags != 0) {
        resblit_alloc_ems_64k("FRAME.SCX", &g_nFrameScxEmsHandle);
        resblit_alloc_ems_64k("INVENTOR.SCX", &g_nInventorScxEmsHandle);
    }
    return;
}

ImageRecord **resblit_load_asset_table(char *path, int storage_mode) {
    int i;
    ImageRecord **tbl = 0;
    BakFile *fp;
    unsigned char huge *pPayload;
    unsigned char huge *cursor;
    int published = 0;
    int ems_handle;
    unsigned ems_off;
    unsigned chunk;
    char *scratch;
    struct BmxHeader hdr;

    path[strlen(path) - 1] = 'x';
    if ((fp = bak_fopen(path, "rb")) != 0) {
        bak_fread(&hdr, 12, 1, fp);

        if (hdr.wImageCount != 0 && hdr.wMagic == 0x1066) {
            if ((tbl = my_calloc((hdr.wImageCount + 1) * 2, 1)) != 0) {
                if ((tbl[0] = my_calloc(10, hdr.wImageCount)) != 0) {
                    i = 0;
                    while (i < hdr.wImageCount) {
                        i++;
                        tbl[i] = tbl[0] + i;
                    }
                    i = 0;
                    while (i < hdr.wImageCount) {
                        bak_fread(&tbl[i]->wImageOff, 2, 4, fp);
                        i++;
                    }
                    tbl[hdr.wImageCount] = 0;
                    if (storage_mode == 2) {
                        if ((long)hdr.dwDecompressedSize < 0xffdcL &&
                            (ems_handle = ems_alloc_pages(hdr.dwDecompressedSize)) != 0) {
                            pPayload = ems_map_resource_pages(ems_handle);
                        } else {
                            pPayload = alloc_far(hdr.dwDecompressedSize, 0);
                            storage_mode = 0;
                        }

                        if (!pPayload)
                            goto cleanup;
                    } else if (storage_mode != 0) {
                        if ((ems_handle = ems_alloc_pages(hdr.dwDecompressedSize)) != 0)
                            pPayload = ems_map_resource_pages(ems_handle);
                        if (!pPayload)
                            goto cleanup;
                    } else {
                        if ((pPayload = alloc_far(hdr.dwDecompressedSize, 0)) == 0)
                            goto cleanup;
                    }
                    i = ems_off = 0;
                    cursor = pPayload;
                    while (i < hdr.wImageCount) {
                        ImageRecord *rec = tbl[i];
                        chunk = rec->wImageOff;
                        if (storage_mode != 0) {
                            rec->wImageData = ems_handle;
                            rec->wImageOff = ems_off;
                            ems_off += chunk;
                        } else {
                            rec->wImageData = FP_SEG(cursor);
                            rec->wImageOff = FP_OFF(cursor);
                            cursor += chunk;
                        }
                        i++;
                    }
                    if (hdr.wCompression != 0) {

                        i = 5000;
                        do {
                            i /= 2;
                            scratch = malloc(i);
                        } while (scratch == 0 && i > 50);
                        if (hdr.wCompression == 2)
                            decomp_rle((unsigned char far *)pPayload, hdr.wCompressedSize, (int)scratch, i,
                                       fp);
                        else
                            decomp_lzss((unsigned char far *)pPayload, hdr.wCompressedSize, scratch, i, fp);
                        free(scratch);
                        published = 1;
                    } else {
                        i = stream_open(-1, fp, "r", hdr.dwDecompressedSize);
                        if (i == -1)
                            goto cleanup;
                        while ((long)hdr.dwDecompressedSize > 0) {
                            chunk = ((long)hdr.dwDecompressedSize > 0xfa00L)
                                        ? 0xfa00U
                                        : (unsigned)hdr.dwDecompressedSize;
                            stream_read(i, (unsigned char far *)pPayload, chunk);
                            pPayload += chunk;
                            hdr.dwDecompressedSize -= chunk;
                        }
                        stream_close(i);
                        published = 1;
                    }
                }
            }
        }
    cleanup:
        if (published == 0 && tbl != 0) {
            emsimg_free_paged(tbl);
            tbl = 0;
        }
        bak_fclose(fp);
    }
    return tbl;
}

void resblit_list_remap_palette(ResourceRemapDesc **resource_list, unsigned char *palette_lut) {
    register int i;
    unsigned char far *p;

    for (i = 0; null_terminated_count((ImageRecord **)resource_list) > i; i++) {
        if (resource_list[i]->wFlags & 0x80) {

            if (resource_list[i]->wIdOrSeg < 300) {
                p = ems_map_resource_pages(resource_list[i]->wIdOrSeg);
                p += resource_list[i]->wOffset;
            } else {
                p = MK_FP(resource_list[i]->wIdOrSeg, resource_list[i]->wOffset);
            }
            while (*p) {
                if (*p & 0x80) {
                    p++;
                    *p = palette_lut[*p];
                    p++;
                } else {
                    int n, j;
                    n = *p & 0x7f;
                    p++;
                    for (j = 0; j < n; j++) {
                        *p = palette_lut[*p];
                        p++;
                    }
                }
            }
        }
    }
}

void resblit_sprite(ImageRecord *sprite, int dst_x, int dst_y) {
    g_polyRasterState.nRemapTableOff = 0;
    emsimg_sprite_blit_scaled_paged(sprite, dst_x, dst_y, 0, sprite->nWidth, sprite->nHeight);
    return;
}

void resblit_sprite_frame(ImageRecord *sprite, int dst_x, int dst_y, int frame) {
    g_polyRasterState.nRemapTableOff = 0;
    emsimg_sprite_blit_scaled_paged(sprite, dst_x, dst_y, frame, sprite->nWidth, sprite->nHeight);
    return;
}

#define PORTRAIT_ROW_X0 0xe
#define PORTRAIT_PANEL_STRIDE 0x3a
void resblit_hud_draw_party_icons_row(char *filename) {
    int i;
    int dst_y;

    dst_y = 0;
    if (g_pHeadsBmxAssetTable != 0) {
        if (stricmp(filename, "frame.scx") == 0) {
            dst_y = 0x8f;
        } else if (stricmp(filename, "inventor.scx") == 0) {
            dst_y = 0x94;
        }
        if (dst_y != 0) {
            for (i = 0; i < g_gameState.party_count; i++) {
                resblit_sprite(g_pHeadsBmxAssetTable[g_gameState.party_roster[i]],
                               i * PORTRAIT_PANEL_STRIDE + PORTRAIT_ROW_X0, dst_y);
            }
            for (; i < 3; i++) {
                resblit_sprite(g_pHeadsBmxAssetTable[6],
                               i * PORTRAIT_PANEL_STRIDE + PORTRAIT_ROW_X0, dst_y);
            }
        }
    }
    return;
}

void resblit_load_pal_or_stream(char *filename) {
    register char *fn = filename;
    int *pHandle;
    int rows;
    int local;
    int sHandle;
    BakFile *stream;
    unsigned char huge *buf = 0;

    pHandle = 0;
    fn[strlen(fn) - 1] = 'x';
    if (stricmp(fn, "dialog.scx") == 0)
        pHandle = &g_nDialogScxEmsHandle;
    else if (stricmp(fn, "inventor.scx") == 0)
        pHandle = &g_nInventorScxEmsHandle;
    else if (stricmp(fn, "frame.scx") == 0)
        pHandle = &g_nFrameScxEmsHandle;

    if (pHandle != 0 && *pHandle != 0) {
        unsigned char far *dest_far = ems_map_resource_pages(*pHandle);

        cga_rect_paste_from_buffer(dest_far, 0, 0, 0x140, 200);
    } else {
        if ((stream = bak_fopen(fn, "rb")) != 0) {
            bak_fread(&local, 2, 1, stream);

            if (local == 0x27b6) {
                int size;
                rows = 0x28;
                do {
                    rows /= 2;
                    size = rows * 0x140;
                    buf = alloc_far((long)size, 0);
                } while (!buf && 1 < rows);
                if ((sHandle = stream_open(-1, stream, "r", 64000UL)) != -1) {
                    local = 0;
                    do {
                        stream_read(sHandle, buf, size);
                        cga_rect_paste_from_buffer((unsigned char far *)buf, 0, local, 0x140, rows);
                        local += rows;
                    } while (local < 200);
                    stream_close(sHandle);
                }
                _freemem(buf);
            }
            bak_fclose(stream);
        } else
            return;
    }
    resblit_hud_draw_party_icons_row(fn);
}
