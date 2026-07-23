#ifndef BAK_SAVEGAME_H
#define BAK_SAVEGAME_H

#include "structs.h"

extern char *g_pChapDatFilename;

extern int savegame_write(char *filename);
extern int savegame_read(char *filename);
extern void savegame_chapter_start_dispatch(int chapter);

#endif
