#ifndef BAK_LZHUF_H
#define BAK_LZHUF_H

#include "structs.h"

extern void near lzh_init_huffman_freq_tables(void);
extern void near lzss_insert_node(int r);
extern void near lzss_delete_node(int p);
extern int near lzh_get_bit(void);
extern int near lzh_get_byte(void);
extern void near lzh_put_bits(char nbits, unsigned int bits);
extern void near lzh_start_huff(void);
extern void near lzh_huff_update_leaf(int leaf_index);
extern void near lzh_encode_char(int code);
extern void near lzh_encode_position(unsigned int position);
extern void near lzh_encode_end(void);
extern unsigned short near lzh_decode_char(void);
extern int near lzh_encode(int flush);
extern int near lzh_decode(void);
extern int near lzh_ring_buffer_write(void);
extern int near lzh_decode_match_emit(void);

#endif
