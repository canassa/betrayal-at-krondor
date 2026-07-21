/* stdarg.h — IDE-indexing stub (NOT the compiler's real stdarg.h). See
 * clion_shim.h. Routed through the compiler's own varargs builtins (both clang
 * and gcc provide them) so `va_list`/`va_start`/… resolve without pulling any
 * host libc header — and without defining `__gnuc_va_list`, which the
 * reconstructed structs.h already owns. */
#ifndef BAK_IDE_STDARG_H
#define BAK_IDE_STDARG_H
typedef __builtin_va_list va_list;
#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_arg(ap, type) __builtin_va_arg(ap, type)
#define va_end(ap) __builtin_va_end(ap)
#define va_copy(dst, src) __builtin_va_copy(dst, src)
#endif
