#ifndef BAK_CODEC_H
#define BAK_CODEC_H

#include "structs.h"
#include "SRC/IO/IO.H"

extern unsigned char huge *g_pCodecScratchFp;
extern CodecVtable g_codec_vtable[4];
extern unsigned char g_abLowBitMaskByWidth[9];
extern StreamDesc *g_pCurStreamDesc;
extern unsigned char *g_pCurStreamRingBuf;
extern unsigned char g_bCurStreamCodecId;
extern IoFile *g_pCurStreamFp;
extern unsigned char huge *g_pStreamReadDst;
extern unsigned char huge *g_pCurCodecScratch;
extern StreamDesc *g_apStreamSlots[100];
extern int g_nStreamBytesWritten;
extern unsigned short g_wCodecBytesRemaining;
extern unsigned char g_bCurStreamOpMode;
extern unsigned char g_bCurStreamDescFlags;
extern char huge *g_pCurStreamSrcCursor;
extern unsigned char g_codecRawTransitBuf[50];
extern unsigned char g_bssgap_5de5;
extern IffResReader g_chunkSeekSaveIffReader;
extern IffResReader g_iff_reader_pool[4];

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
