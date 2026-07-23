#ifndef BAK_IO_H
#define BAK_IO_H

#include "structs.h"

extern unsigned char g_bak_initialized;
extern short g_bak_io_error;
extern void far *g_int24_old_vector;
extern BakHandle g_bak_handles[10];
extern BakArchive g_bak_archives[11];
extern BakFile *g_pBakFgetcLastStream;
extern FILE *g_pBakActiveFgetcStream;
extern unsigned char g_bak_in_fopen;
extern unsigned char g_bak_fopen_retry;
extern unsigned char g_bak_archives_dirty;
extern unsigned char g_bak_open_handles;
extern unsigned long g_bak_lookup_hash;
extern short g_bak_current_archive;
extern short g_bak_archive_count;
extern short g_bak_hash_seed;
extern unsigned short g_bak_hash_rotate;
extern BakHandle *g_pBakFindHandleCacheVal;
extern BakFile *g_pBakFindHandleCacheKey;

extern BakFile *bak_fopen(char *filename, char *mode);
extern int bak_fclose(BakFile *stream);
extern int bak_fread(void *ptr, int size, int count, BakFile *stream);
extern int bak_fseek(BakFile *stream, long offset, int whence);
extern long bak_ftell(BakFile *stream);
extern long bak_filelength(BakFile *stream);
extern void bak_rewind(BakFile *stream);
extern int bak_fgetc(BakFile *stream);
extern int bak_feof(BakFile *stream);
extern int bak_fwrite(void *ptr, int size, int count, BakFile *stream);
extern int bak_putc(int c, BakFile *stream);
extern void bak_setbuf(BakFile *stream, char *buffer);
extern void bak_init_resources(void);
extern void bak_shutdown_resources(void);
extern void bak_invalidate_archives(void);
extern unsigned long bak_filename_hash(char *filename);
extern int bak_resource_lookup(BakHandle *slot);
extern void bak_select_archive(int archive_index);
extern void bak_archive_seek(unsigned long absolute_offset);
extern BakHandle *bak_find_handle(BakFile *stream);

extern void interrupt far bak_int24_critical_handler();

extern long far dos_read(unsigned char far *buf, long count, int fd);
extern long far dos_write(unsigned char far *buf, long count, int fd);

#endif
