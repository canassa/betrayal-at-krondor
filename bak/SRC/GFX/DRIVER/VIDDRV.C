#include "globals.h"
#include "structs.h"
#include "SRC/GFX/DRIVER/VIDDRV.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/STREAM/RESLOAD/IFFREAD.H"
#include "SRC/STREAM/CODEC/STREAM.H"

void huge *g_pVideoDriverTemplate = {0};
char g_szDrvSuffix_BAD[3] = {'B', 'A', 'D'};
unsigned short g_apVideoDriverChunkNames[13] = {0x003a,
                                                (unsigned short)g_szDrvSuffix_CGA,
                                                (unsigned short)g_szDrvSuffix_EGA,
                                                (unsigned short)g_szDrvSuffix_TAN,
                                                (unsigned short)g_szDrvSuffix_HER,
                                                (unsigned short)g_szDrvSuffix_MCG,
                                                (unsigned short)g_szDrvSuffix_BAD,
                                                (unsigned short)g_szDrvSuffix_EVA,
                                                (unsigned short)g_szDrvSuffix_VGA,
                                                (unsigned short)g_szDrvSuffix_EVG,
                                                (unsigned short)g_szDrvSuffix_HVG,
                                                (unsigned short)g_szDrvSuffix_HEG,
                                                (unsigned short)g_szDrvSuffix_NEW};
char g_szVideoChunkName[10] = "OVL:     ";
char g_szDrvSuffix_CGA[5] = "CGA:";
char g_szDrvSuffix_EGA[5] = "EGA:";
char g_szDrvSuffix_TAN[5] = "TAN:";
char g_szDrvSuffix_HER[5] = "HER:";
char g_szDrvSuffix_MCG[5] = "MCG:";
char g_szDrvSuffix_EVA[5] = "EVA:";
char g_szDrvSuffix_VGA[5] = "VGA:";
char g_szDrvSuffix_EVG[5] = "EVG:";
char g_szDrvSuffix_HVG[5] = "HVG:";
char g_szDrvSuffix_HEG[5] = "HEG:";
char g_szDrvSuffix_NEW[5] = "NEW:";

ulong far *video_driver_load(int mode, BakFileRef *file) {
    long size;
    int stream_id;
    int did_open;
    BakFile *handle;

    did_open = 0;

    switch (mode) {
    case 12:
        mode = 0xb;
        g_wScreen_height = 0x15e;
        break;
    case 13:
        mode = 0xb;
        g_wScreen_height = 0x1e0;
        break;
    case 14:
        mode = 0xb;
        goto set_height_400;
    case 4:
        mode = 1;
        g_wScreen_width = 0x280;
    case 15:
        mode = 8;
    set_height_400:
        g_wScreen_height = 400;
        break;
    }

    if (is_file_cached(file) == 0) {
        did_open = 1;
        handle = cached_file_open(file);
    } else {
        handle = file;
    }
    if (handle == 0) {
        goto fail;
    }

    my_strcpy(g_szVideoChunkName + 4, (char *)g_apVideoDriverChunkNames[mode]);
    if (chunk_seek(handle, g_szVideoChunkName, 0) == -1L) {
        goto fail;
    }

    if ((stream_id = stream_open(-1, handle, "r", cached_file_chunk_size(handle))) < 0) {
        goto fail;
    }

    size = stream_size(stream_id);

    if (g_pVideoDriverTemplate != 0) {
        _freemem(g_pVideoDriverTemplate);
    }
    if ((g_pVideoDriverTemplate = alloc_far(size, 0L)) == 0) {
        goto fail;
    }

    stream_read(stream_id, (void far *)g_pVideoDriverTemplate, (uint)size);
    stream_close(stream_id);

    if (did_open != 0) {
        cached_file_close(handle);
    }
    return (ulong far *)g_pVideoDriverTemplate;

fail:
    return 0;
}
