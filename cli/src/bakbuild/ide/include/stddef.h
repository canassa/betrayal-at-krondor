/* stddef.h — IDE-indexing stub (NOT the compiler's real stddef.h). See
 * clion_shim.h. `size_t` and `NULL` come from the force-included shim (DOS width,
 * kept consistent with structs.h); we deliberately do NOT fall through to the
 * compiler's stddef.h, whose 64-bit host `size_t` would conflict with the
 * reconstructed headers. */
#ifndef BAK_IDE_STDDEF_H
#define BAK_IDE_STDDEF_H
typedef int ptrdiff_t;
#define offsetof(type, member) ((size_t) & (((type *)0)->member))
#endif
