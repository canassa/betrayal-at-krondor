#ifndef BAK_INT00_H
#define BAK_INT00_H

#include "structs.h"

extern unsigned char g_int00_installed;
extern unsigned short g_wInt00SaveSeg;
extern unsigned short g_wInt00SaveOff;

extern void install_int00_handler(void);
extern unsigned int near int00_divide_recovery(unsigned short ret_cs);
extern void restore_int00_handler(void);

#endif
