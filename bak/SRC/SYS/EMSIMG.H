#ifndef BAK_EMSIMG_H
#define BAK_EMSIMG_H

#include "structs.h"

extern ImageRecord **emsimg_migrate_to_ems(ImageRecord **image_record_list);
extern int *emsimg_load_to_ems(char *fname);
extern void emsimg_free_paged(void *pImgRecord);
extern void emsimg_polygon_quad_canonicalize();
extern void emsimg_gouraud_blit_paged(unsigned int *page_ptr, int *xs, int *ys);
extern void emsimg_sprite_blit_scaled_paged(ImageRecord *sprite, int dst_x, int dst_y, unsigned int frame,
                                            int width, int height);
extern void emsimg_putsprite_ems_swap(unsigned int *img_ptr, int x, int y);
extern void emsimg_map_then_call_180c(unsigned int *p_id_or_ptr, int x, int y, unsigned int flip_flags);

#endif
