#ifndef BAK_ACTRENDR_H
#define BAK_ACTRENDR_H

#include "structs.h"

extern char actorrender_frustum_cull(void);
extern int actorrender_mesh_parts_cull_sort(int part_off, int part_count, int *parts);
extern int actorrender_mesh_part_ptr_arr(int extra, int count, int base, int *output);
extern void actorrender_mesh_parts(int part_off, int part_count, int *part_ptr_array);
extern void actorrender_entity(WorldObject far *entry);

#endif
