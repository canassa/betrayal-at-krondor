#ifndef BAK_INT00_H
#define BAK_INT00_H

#include "structs.h"

extern void install_int00_handler(void);
extern uint near int00_divide_recovery(ushort ret_cs);
extern void restore_int00_handler(void);

#endif
