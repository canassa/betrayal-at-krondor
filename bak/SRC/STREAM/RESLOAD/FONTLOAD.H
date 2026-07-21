#ifndef BAK_FONTLOAD_H
#define BAK_FONTLOAD_H

#include "structs.h"

extern int font_load(BakFileRef *filename);
extern void font_unload(int slot);

#endif
