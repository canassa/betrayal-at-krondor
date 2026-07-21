#ifndef BAK_PANIC_H
#define BAK_PANIC_H

#include "structs.h"

extern int panic_fatal_error_exit(char far *module, int line, char *msg);
extern void panic_assert_fail_report(char far *file, int line);

#endif
