#define unpack_2bpp_to_byte_per_pixel _proto_suppressed_unpack_2bpp
#include "SRC/GEN/GFXCTX.H"
#include "SRC/GEN/RNDVTBL.H"
#include "SRC/GFX/FONT/FONT.H"
#include "SRC/STREAM/CODEC/CODEC.H"
#include "structs.h"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/IO/IO.H"
#include "SRC/SYS/FARTHUNK.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/SYS/FARPTR.H"
#include "SRC/STREAM/RESLOAD/IFFREAD.H"
#include "SRC/STREAM/CODEC/STREAM.H"
#undef unpack_2bpp_to_byte_per_pixel

void unpack_2bpp_to_byte_per_pixel(unsigned char huge *src, unsigned char huge *dst, unsigned count);

int iff_chunk_loader_2f1c(IoFile *file, unsigned short *count, unsigned short *out_handle) {

    unsigned short *width;
    unsigned short *height;
    int i;
    unsigned short n;
    int *slot;
    unsigned short *buf;
    int rec;

    buf = 0;
    *out_handle = 0;
    if (chunk_seek(file, "BMP:INF:", 0) == -1L)
        goto L_fail;
    if (bak_fread(count, 2, 1, file) != 1)
        goto L_fail;
    if (!(*out_handle = (unsigned short)my_calloc((*count + 1) * 2, 1)))
        goto L_cleanup;
    if (!(*(unsigned short *)*out_handle = (unsigned short)my_calloc(10, *count)))
        goto L_cleanup;
    if ((long)(cached_file_chunk_size(file) + (-2L)) < (long)(int)(*count << 2))
        n = 1;
    else
        n = *count;
    if (!(buf = (unsigned short *)my_malloc(n << 2)))
        goto L_cleanup;
    if (bak_fread(buf, n << 2, 1, file) != 1)
        goto L_cleanup;
    width = buf;
    height = buf + n;
    rec = *(int *)*out_handle;
    slot = (int *)*out_handle;
    for (i = 0; i < (int)*count; i++) {
        *slot = rec;
        *(unsigned short *)(rec + 6) = *width;
        *(unsigned short *)(rec + 8) = *height;
        if (*count == n) {
            width++;
            height++;
        }
        rec += 10;
        slot++;
    }
    *slot = 0;
    my_free(buf);
    return 1;
L_cleanup:
    if (buf != 0)
        my_free(buf);
    if (*out_handle != 0) {
        if (*(int *)*out_handle != 0)
            my_free((void *)*(unsigned short *)*out_handle);
        my_free((void *)*out_handle);
    }
L_fail:
    return 0;
}

unsigned short bak_load_image_record_chunked(FileRef *fname) {
    unsigned short *image;
    int stream;
    unsigned char huge *buf;
    unsigned char huge *walk;
    unsigned char huge *aux;
    void *scratch;
    unsigned short record_count;
    int nread;
    int aux_size;
    int opened;
    int mode;
    long size;

    mode = 0;
    opened = 0;
    image = 0;
    aux = buf = 0;
    scratch = 0;
    stream = 0;

    if (!is_file_cached(fname)) {
        opened = 1;
        if ((unsigned)(fname = cached_file_open(fname)) < 0)
            goto cleanup;
    }
    if (iff_chunk_loader_2f1c(fname, &record_count, (unsigned short *)&image)) {
        size =
            (*(unsigned long(far *)(unsigned short *, int *))g_renderer_vtable.pfn_image_install)(
                image, &aux_size);
        if (!(buf = alloc_far(size, 0L)))
            goto cleanup;
        if (aux_size != 0) {
            if (!(aux = alloc_far((long)aux_size, 0L)))
                goto cleanup;
        }

        if (*(long *)&g_pCodecScratchFp == 0) {

            if ((scratch = my_malloc(0x3cc4)) != 0) {
                my_free(scratch);

                if ((scratch = my_malloc(0x3ac4)) != 0) {
                    g_pCodecScratchFp = (unsigned char huge *)scratch;
                    g_pCodecScratchFp += 0x10;
                    g_pCodecScratchFp = normalize_far_ptr_thunk(
                        (unsigned char far *)((unsigned long)g_pCodecScratchFp & 0xfffffff0L));
                }
            }
        }
        if (chunk_seek(fname, "BMP:BIN:", 0) != -1L) {
            if ((stream = stream_open(0, fname, "r", cached_file_chunk_size(fname))) >= 0) {
                walk = buf;
                while (stream_read(stream, walk, 0x7fff) == 0x7fff)
                    walk += 0x7fff;
                (*(void(far *)(unsigned short *, unsigned char far *, unsigned long,
                               unsigned char far *,
                               unsigned long))g_renderer_vtable.pfn_image_decode)(
                    image, buf, stream_size(stream), aux, size);
                stream_close(stream);
                mode = 1;
                if (g_graphics_context.bGfxRenderStateFlag != 0) {
                    if (chunk_seek(fname, "BMP:VGA:", 0) != -1L)
                        mode = 5;
                    else if (chunk_seek(fname, "BMP:AMG:", 0) != -1L)
                        mode = 6;
                    if (mode >= 5) {
                        if ((stream = stream_open(0, fname, "r", cached_file_chunk_size(fname))) >=
                            0) {
                            size = 0x7fff;
                            while (!(aux = alloc_far(size, 0L)))
                                size >>= 1;
                            walk = buf;
                            while ((nread = stream_read(stream, aux, (unsigned)size)) > 0) {
                                if (mode == 6) {
                                    unpack_2bpp_to_byte_per_pixel(aux, aux, nread);
                                    nread <<= 2;
                                }
                                (*(void(far *)(
                                    unsigned char far *, unsigned char far *,
                                    unsigned short))g_renderer_vtable.pfn_unpack_nibbles_to_planes)(
                                    aux, walk, nread);
                                walk += (unsigned long)size * 2;
                            }
                            stream_close(stream);
                        }
                    }
                }
            }
        }
    }
cleanup:
    if (aux != 0)
        _freemem(aux);
    if (scratch != 0) {
        my_free(scratch);
        g_pCodecScratchFp = 0;
    }
    if (mode == 0) {
        if (buf != 0)
            _freemem(buf);
        if (stream != 0)
            stream_close(stream);
        free_container_pair((int *)image);
        image = 0;
    }
    if (opened)
        cached_file_close(fname);
    return (unsigned short)image;
}

void free_container_pair(int *container) {
    if (*container != 0)
        my_free((void *)*container);
    if (container != 0)
        my_free(container);
}

void far free_image_record(register ImageRecord **record) {
    int *inner;
    if (record) {
        inner = (int *)*record;
        _freemem((unsigned char far *)(((unsigned long)inner[0] << 16) + (unsigned int)inner[1]));
        free_container_pair((int *)record);
    }
}

int null_terminated_count(ImageRecord **table) {
    register int i;

    i = 0;
    if (table != 0) {
        for (; table[i] != 0; i++) {
        }
    }
    return i;
}

void unpack_2bpp_to_byte_per_pixel(unsigned char huge *src, unsigned char huge *dst, unsigned count) {
    unsigned char b;
    unsigned si;

    src += count - 1;
    dst += count * 4 - 1;

    while (count--) {
        b = *src--;
        for (si = 1; si & 0xff; si <<= 1) {
            if (si & 0xaa) {
                *dst |= ((int)(char)b & si) ? 0x10 : 0;
                dst--;
            } else {
                *dst = ((int)(char)b & si) ? 1 : 0;
            }
        }
    }
}
