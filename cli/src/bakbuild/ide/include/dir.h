/* dir.h — IDE-indexing stub (NOT Borland's real dir.h). See clion_shim.h.
 * Declares the Borland directory / path-manipulation vocabulary so
 * `#include <dir.h>` sources index without a missing-include error. Declarations
 * only; the `ffblk` layout is approximate and NOT load-bearing (nothing here is
 * executed — see clion_shim.h). */
#ifndef BAK_IDE_DIR_H
#define BAK_IDE_DIR_H
struct ffblk {
    char ff_reserved[21];
    char ff_attrib;
    unsigned ff_ftime;
    unsigned ff_fdate;
    long ff_fsize;
    char ff_name[13];
};
int findfirst(const char *pathname, struct ffblk *ffblk, int attrib);
int findnext(struct ffblk *ffblk);
int chdir(const char *path);
int mkdir(const char *path);
int rmdir(const char *path);
char *getcwd(char *buf, int len);
int getcurdir(int drive, char *directory);
void fnsplit(const char *path, char *drive, char *dir, char *name, char *ext);
void fnmerge(char *path, const char *drive, const char *dir, const char *name, const char *ext);
int getdisk(void);
int setdisk(int drive);
#endif
