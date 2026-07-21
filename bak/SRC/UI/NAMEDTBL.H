#ifndef BAK_NAMEDTBL_H
#define BAK_NAMEDTBL_H

#include "structs.h"

extern int *namedtbl_load(char *filename);
extern int namedtbl_free(int *table);
extern void namedtbl_labels_draw_all(int *table);
extern void namedtbl_label_draw(int *label);

#endif
