#ifndef BAK_AUDRESIN_H
#define BAK_AUDRESIN_H

#include "structs.h"

#define SNDDRV_STD 0
#define SNDDRV_TAN 1
#define SNDDRV_ADL 2
#define SNDDRV_M32 3
#define SNDDRV_SBP 4
#define SNDDRV_PS1 5
#define SNDDRV_PRO 6
#define SNDDRV_GMD 7
#define SNDDRV_NONE 8

extern int audio_resource_install_by_id(char *file, int *p_resource_id, int load_mode);

#endif
