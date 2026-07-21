/* clion_shim.h — Borland-dialect compatibility shim for IDE indexing ONLY.
 *
 * This header is FORCE-INCLUDED (clang `-include`) into every translation unit
 * listed in the generated `compile_commands.json` (see `bak compdb`). It exists
 * solely so a modern clang/clangd indexer — the engine behind CLion's code
 * intelligence — can PARSE the 16-bit Borland C sources under bak/SRC.
 *
 * It is NOT part of the real build. `bak build` compiles the sources with the
 * period Borland toolchain (bcc/bccx) inside a FreeDOS qemu VM; that path never
 * sees this file. Nothing here changes a single emitted byte — it only makes
 * the dialect grammatical to clang so go-to-definition / completion / call
 * hierarchy work. Pointer widths under clang won't match real-mode segmented
 * pointers, which is irrelevant for navigation.
 *
 * Hand-written and stable. Guarded by __BAK_CLION__ (defined by `bak compdb`)
 * so it is inert if it ever leaks into a non-IDE compile.
 */
#ifndef BAK_CLION_SHIM_H
#define BAK_CLION_SHIM_H

#ifdef __BAK_CLION__

/* --- Core types, owned here and force-included first ----------------------- *
 * The reconstructed bak/INCLUDE/structs.h defines its own DOS-width `size_t`
 * (unsigned short) and friends. If a compiler/glibc header (pulled by a real
 * <stdio.h> etc.) defines the 64-bit host `size_t` / `__gnuc_va_list` /
 * `ssize_t` first, structs.h then conflicts on every file. So we never let a
 * host libc header in (all system headers are stubbed beside this file), and we
 * define `size_t` HERE — before structs.h — under its own `_SIZE_T` guard so
 * structs.h skips its copy and everything agrees. Width is irrelevant to a
 * parse; agreement is what matters. */
#ifndef _SIZE_T
#define _SIZE_T
typedef unsigned short size_t;
#endif
#ifndef NULL
#define NULL ((void *)0)
#endif

/* --- Borland memory-model & calling-convention keywords ------------------- *
 * The DOS compiler understands these as type/decl qualifiers; clang does not.
 * Define them away — for indexing, a `far`/`near`/`huge` pointer is just a
 * pointer, and the calling convention doesn't affect symbol resolution.
 * Both the bare and single-underscore spellings are covered. */
#define far
#define near
#define huge
#define cdecl
#define pascal
#define interrupt
#define _far
#define _near
#define _huge
#define _cdecl
#define _pascal
#define _interrupt
#define _export
#define _loadds
#define _saveregs
#define _seg
/* Double-underscore spellings (Borland accepts both `far` and `__far`). */
#define __far
#define __near
#define __huge
#define __cdecl
#define __pascal
#define __interrupt
#define __export
#define __loadds
#define __saveregs
#define __seg
/* Segment-override qualifiers used as pointer modifiers, e.g. `char _es *p`.
 * For navigation an ES-relative pointer is just a pointer. */
#define _cs
#define _ds
#define _es
#define _ss

/* --- Borland pseudo-registers --------------------------------------------- *
 * `_AX = 0x30;` etc. read/write CPU registers in the real compiler. Declaring
 * them as plain externs lets the assignments and reads parse; the values are
 * meaningless under clang but the surrounding code resolves. The full register
 * file is declared (not just the few currently used) so new sources index
 * without touching this shim. */
extern unsigned _AX, _BX, _CX, _DX, _SI, _DI, _BP, _SP;
extern unsigned _CS, _DS, _ES, _SS, _FLAGS;
extern unsigned char _AH, _AL, _BH, _BL, _CH, _CL, _DH, _DL;
/* 32-bit pseudo-registers (386+; used by a few segment-arithmetic routines). */
extern unsigned long _EAX, _EBX, _ECX, _EDX, _ESI, _EDI, _EBP, _ESP;

#endif /* __BAK_CLION__ */
#endif /* BAK_CLION_SHIM_H */
