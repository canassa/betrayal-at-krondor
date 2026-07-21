/* io.h — IDE-indexing stub (NOT Borland's real io.h). See clion_shim.h.
 * Declares the Borland low-level (handle-based) file-I/O vocabulary so
 * `#include <io.h>` sources index without a missing-include error. Declarations
 * only. */
#ifndef BAK_IDE_IO_H
#define BAK_IDE_IO_H
int open(const char *path, int access, ...);
int close(int handle);
int read(int handle, void *buf, unsigned len);
int write(int handle, const void *buf, unsigned len);
long lseek(int handle, long offset, int whence);
long tell(int handle);
long filelength(int handle);
int eof(int handle);
int setmode(int handle, int mode);
int creat(const char *path, int amode);
int access(const char *path, int amode);
int chsize(int handle, long size);
int dup(int handle);
int dup2(int oldhandle, int newhandle);
int isatty(int handle);
int unlink(const char *path);
#endif
