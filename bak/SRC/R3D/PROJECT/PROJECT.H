#ifndef BAK_PROJECT_H
#define BAK_PROJECT_H

#include "structs.h"

extern void project_perspective_xy(int x, int depth, int y, int *out_vec3);
extern void project_world_to_screen(int x, int y, int z, int *out_screen_xy, ViewContext *widget);
extern void project_tile_to_screen(int tile_x, int tile_y, int *out_screen);
extern void project_cursor_to_world_tile(long *out_world_xyz);

#endif
