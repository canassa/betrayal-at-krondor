#ifndef BAK_LZWDEC_H
#define BAK_LZWDEC_H

#include "structs.h"

extern void near lzw_decompress();
extern void near lzw_decode_step(void);
extern unsigned int near lzw_get_next_code(void);

#endif
