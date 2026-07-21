#ifndef BAK_DISTDIR_H
#define BAK_DISTDIR_H

#include "structs.h"

extern ulong distdir_vec3_distance_dir_approx(long *a, ulong b, ushort dir_in);
extern long distdir_octagonal_distance(long *p1, long *p2);
extern long distdir_octagonal_distance_dxdy(long dx, long dy);

#endif
