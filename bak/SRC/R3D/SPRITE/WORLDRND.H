#ifndef BAK_WORLDRND_H
#define BAK_WORLDRND_H

#include "structs.h"

extern unsigned short g_spriteBankCount;
extern PagedArrayEntry *g_spriteBanks;
extern ImageRecord *g_pBillboardSpriteImg;
extern short g_nBillboardScrX;
extern short g_nBillboardScrY;
extern short g_nBillboardW;
extern short g_nBillboardH;
extern unsigned short g_nFogRemapTableCount;
extern unsigned short g_wSpriteFogBucketWidth;
extern unsigned long g_lSpriteFogOnsetDist;
extern long g_lSpriteFogFarDist;
extern unsigned short g_nLodBucketWidth;
extern unsigned long g_dwLodNearThreshold;
extern unsigned long g_lFarCullDist;

extern ImageRecord **worldrender_table_swap(int slot, ImageRecord **new_table_ptr);
extern void worldrender_swap_record_table(int slot_a, int slot_b);
extern ImageRecord **worldrender_table_load(int slot, char *fname);
extern void worldrender_table_unload(int slot);
extern ImageRecord *worldrender_paged_array_get(int index);
extern int *worldrender_mesh_vertex_to_world(unsigned char idx, int *out_vec3);
extern void worldrender_sprite_billboard(unsigned char far *entry);
extern void worldrender_textured_quad_lod(int texture_index, int *xs, int *ys);
extern void worldrender_world_point_as_circ(CircObj far *obj);

#endif
