#ifndef BAK_IO_H
#define BAK_IO_H

#include "structs.h"

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
extern ulong bak_filename_hash(char *filename);
extern int bak_resource_lookup(BakHandle *slot);
extern void bak_select_archive(int archive_index);
extern void bak_archive_seek(ulong absolute_offset);
extern BakHandle *bak_find_handle(BakFile *stream);

extern void interrupt far bak_int24_critical_handler();

extern long far dos_read(unsigned char far *buf, long count, int fd);
extern long far dos_write(unsigned char far *buf, long count, int fd);

#endif
