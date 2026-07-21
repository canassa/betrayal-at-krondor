/* ctype.h — IDE-indexing stub (NOT a real libc header). See clion_shim.h.
 * clang ships freestanding headers but no hosted libc; this satisfies the few
 * `#include <ctype.h>` sources so the indexer resolves the classification
 * functions instead of erroring on a missing include. */
#ifndef BAK_IDE_CTYPE_H
#define BAK_IDE_CTYPE_H
int isalnum(int c);
int isalpha(int c);
int iscntrl(int c);
int isdigit(int c);
int isgraph(int c);
int islower(int c);
int isprint(int c);
int ispunct(int c);
int isspace(int c);
int isupper(int c);
int isxdigit(int c);
int tolower(int c);
int toupper(int c);

/* Borland's ctype.h implements the is*() macros against a classification table
 * (`_ctype`) and per-class bitmasks (`_IS_*`). Some sources expand that macro
 * form inline — e.g. `((unsigned char *)_ctype)[c + 1] & _IS_DIG`. These
 * declarations exist ONLY so that expression type-checks for the indexer; the
 * mask values here are NOT load-bearing (nothing is executed — see clion_shim.h)
 * and are not guaranteed to equal Borland's real bit assignments. */
extern char _ctype[];
#define _IS_SP 0x01
#define _IS_DIG 0x02
#define _IS_UPP 0x04
#define _IS_LOW 0x08
#define _IS_HEX 0x10
#define _IS_CTL 0x20
#define _IS_PUN 0x40
#define _IS_BLK 0x80
#endif
