#ifndef BAK_FONTLOAD_H
#define BAK_FONTLOAD_H

#include "structs.h"
#include "SRC/IO/IO.H"

extern unsigned short g_font_chunk_tag_ptr;

extern int font_load(FileRef *filename);
extern void font_unload(int slot);

#endif
