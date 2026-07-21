#ifndef BAK_LZW_H
#define BAK_LZW_H

#include "structs.h"

extern int near lzw_reset_state(void);
extern int near lzw_decompressor_init(void);
extern int near lzw_compress_input(int flush);
extern void near lzw_emit_code(int code);
extern long thunk_LDIV_at(long numer, long denom);
extern void near lzw_check_ratio(void);
extern void near lzw_clear_code_table(long count);

#endif
