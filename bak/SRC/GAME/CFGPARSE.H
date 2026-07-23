#ifndef BAK_CFGPARSE_H
#define BAK_CFGPARSE_H

#include "structs.h"

extern void parse_krondor_cfg(void);

#ifdef V102CD
extern char *g_base_dir;
extern char g_cd_drive_letter;
extern int g_bNonRotatingMap;
#endif

#endif
