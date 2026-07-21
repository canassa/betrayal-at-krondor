#ifndef BAK_WORLDRND_H
#define BAK_WORLDRND_H

#include "structs.h"

extern ImageRecord **worldrender_table_swap(int slot, ImageRecord **new_table_ptr);
extern void worldrender_swap_record_table(int slot_a, int slot_b);
extern ImageRecord **worldrender_table_load(int slot, char *fname);
extern void worldrender_table_unload(int slot);
extern ImageRecord *worldrender_paged_array_get(int index);
extern int *worldrender_mesh_vertex_to_world(uchar idx, int *out_vec3);
extern void worldrender_sprite_billboard(unsigned char far *entry);
extern void worldrender_textured_quad_lod(int texture_index, int *xs, int *ys);
extern void worldrender_world_point_as_circ(CircObj far *obj);

#endif
