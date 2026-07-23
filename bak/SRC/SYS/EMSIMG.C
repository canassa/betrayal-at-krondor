#include <dos.h>
#include "SRC/GFX/FONT/FONT.H"
#include "structs.h"
#include "SRC/SYS/EMSIMG.H"
#include "SRC/GFX/RASTER/POLYRAST.H"
#include "SRC/SYS/DOSMEM.H"
#include "SRC/SYS/FARPTR.H"
#include "SRC/STREAM/RESLOAD/IMGLOAD.H"
#include "SRC/GFX/SPRITE/SPRTHNKS.H"
#include "SRC/SYS/EMS.H"

ImageRecord **emsimg_migrate_to_ems(ImageRecord **image_record_list) {
    unsigned long sizeBytes;
    int i;
    int page_id;
    unsigned char far *firstbuf;
    unsigned char far *dst;
    unsigned long linear_base;
    unsigned long linear_cur;

    sizeBytes = (*(unsigned long(far *)(unsigned short *,
                                        unsigned short *))g_renderer_vtable.pfn_image_install)(
        (unsigned short *)image_record_list, (unsigned short *)&i);

    if ((page_id = ems_alloc_pages(sizeBytes)) != 0) {

        dst = ems_map_resource_pages(page_id);

        firstbuf =
            (unsigned char far *)MK_FP(image_record_list[0]->wImageData, image_record_list[0]->wImageOff);

        fmemcpy_far((unsigned long)dst, (unsigned long)firstbuf, (unsigned int)sizeBytes);

        linear_base =
            ((unsigned long)image_record_list[0]->wImageData << 4) | image_record_list[0]->wImageOff;

        i = null_terminated_count(image_record_list) - 1;
        while (i >= 0) {

            linear_cur =
                ((unsigned long)image_record_list[i]->wImageData << 4) | image_record_list[i]->wImageOff;

            image_record_list[i]->wImageData = page_id;
            image_record_list[i]->wImageOff = linear_cur - linear_base;
            i--;
        }

        _freemem(firstbuf);
        return image_record_list;

    } else {
        return image_record_list;
    }
}

int *far emsimg_load_to_ems(char *fname) {
    int *image_record_list;

    image_record_list = (int *)bak_load_image_record_chunked(fname);
    if (image_record_list != (int *)0x0) {
        emsimg_migrate_to_ems((ImageRecord **)image_record_list);
    }
    return image_record_list;
}

void far emsimg_free_paged(void *pImgRecord) {
    void far *freshBlock;
    ImageRecord **list;

    list = (ImageRecord **)pImgRecord;

    if ((*list)->wImageData < 300) {
        ems_free_pages((*list)->wImageData);
        freshBlock = alloc_far(0x10L, 0L);
        (*list)->wImageData = FP_SEG(freshBlock);
    }
    free_image_record(list);
}

void emsimg_polygon_quad_canonicalize(int *xs, int *ys) {
    int tmp;
    int i;
    int tmpY;

    if ((*xs == xs[1]) && (xs[2] == xs[3])) {
        tmp = *xs;
        tmpY = *ys;
        for (i = 1; i < 4; i++) {
            xs[i - 1] = xs[i];
            ys[i - 1] = ys[i];
        }
        xs[3] = tmp;
        ys[3] = tmpY;
    }
    if ((*xs == xs[3]) && (xs[1] == xs[2])) {
        if (*ys > ys[3]) {
            tmp = *xs;
            *xs = xs[3];
            xs[3] = tmp;
            tmp = *ys;
            *ys = ys[3];
            ys[3] = tmp;
        }
        if (ys[1] > ys[2]) {
            tmp = xs[1];
            xs[1] = xs[2];
            xs[2] = tmp;
            tmp = ys[1];
            ys[1] = ys[2];
            ys[2] = tmp;
        }
    }
}

void emsimg_gouraud_blit_paged(unsigned int *page_ptr, int *xs, int *ys) {
    unsigned int page_id;
    unsigned char far *mapped;

    page_id = *page_ptr;
    if (page_id < 300) {
        mapped = ems_map_resource_pages(page_id);
        *page_ptr = FP_SEG(mapped);
    }
    emsimg_polygon_quad_canonicalize(xs, ys);
    polyrast_gouraud_blit_clipped(page_ptr, xs, ys);
    *page_ptr = page_id;
}

void emsimg_sprite_blit_scaled_paged(ImageRecord *sprite, int dst_x, int dst_y, unsigned int frame,
                                     int width, int height) {
    unsigned int page_id;
    unsigned char far *mapped;

    page_id = sprite->wImageData;
    if (page_id < 300) {
        mapped = ems_map_resource_pages(page_id);
        sprite->wImageData = FP_SEG(mapped);
    }

    (*(void (*)(void *, int, int, unsigned int, int, int))polyrast_spr_scaled_blit_planar)(
        sprite, dst_x, dst_y, frame, width, height);
    sprite->wImageData = page_id;
}

void emsimg_putsprite_ems_swap(unsigned int *img_ptr, int x, int y) {
    unsigned int page_id;
    unsigned char far *mapped;

    page_id = *img_ptr;
    if (page_id < 300) {
        mapped = ems_map_resource_pages(page_id);
        *img_ptr = FP_SEG(mapped);
    }
    gfx_putsprite_fp((ImageRecord *)img_ptr, x, y);
    *img_ptr = page_id;
}

void emsimg_map_then_call_180c(unsigned int *p_id_or_ptr, int x, int y, unsigned int flip_flags) {
    unsigned int page_id;
    unsigned char far *mapped;

    page_id = *p_id_or_ptr;
    if (page_id < 300) {
        mapped = ems_map_resource_pages(page_id);
        *p_id_or_ptr = FP_SEG(mapped);
    }
    blit_sprite_indirect((int)p_id_or_ptr, x, y, flip_flags);
    *p_id_or_ptr = page_id;
}
