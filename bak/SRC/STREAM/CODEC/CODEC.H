#ifndef BAK_CODEC_H
#define BAK_CODEC_H

#include "structs.h"

extern int near codec_passthrough_bytes(void);
extern int near codec_rle_read(void);
extern int near codec_flush_ring(void);
extern int near codec_raw_read(unsigned char huge *dst, unsigned int count);
extern int near stream_getc(void);
extern int near codec_raw_block_read(void *dest, unsigned int count);
extern int near codec_rle_literal_run(unsigned int param_1);
extern int near codec_rle_repeat_byte(int value, int count);
extern int near codec_emit_byte(int byte_val);
extern int near stream_putc(int c);
extern int near stream_select(int stream_id);
extern int near mode_has_read(char *mode);
extern void near free_if_not_null(void *ptr);
extern int near stream_release_slot(int slot);
extern int near stream_alloc_slot(char *mode);
extern int near codec_init(int codec_id, char *mode);
extern void near stream_drain_chunk_window(void);
extern unsigned int near stream_consume(int stream_id, unsigned int count);

#endif
