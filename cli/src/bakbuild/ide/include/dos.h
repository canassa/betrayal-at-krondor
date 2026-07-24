/* dos.h — IDE-indexing stub (NOT Borland's real dos.h). See clion_shim.h.
 * Declares the common Borland DOS-interface vocabulary so `#include <dos.h>`
 * sources index without a missing-include error. Declarations only — no real
 * semantics; this never enters the DOS build. (The vendored authentic header
 * lives at toolchain/bc31/INCLUDE/DOS.H, but its uppercase name and Borland
 * pragmas make it unusable as a clang include on a case-sensitive host.) */
#ifndef BAK_IDE_DOS_H
#define BAK_IDE_DOS_H

union REGS;
struct SREGS;

/* far-pointer construction / decomposition. These are macros in Borland, and
 * FP_SEG/FP_OFF are *lvalue* macros — code does `FP_OFF(p) += 2;` — so they must
 * expand to an lvalue here too, not a function call. The bit layout is bogus
 * under a flat-pointer host but nothing is executed (see clion_shim.h); this
 * only has to parse and type-check. */
#define MK_FP(seg, ofs) ((void *)(((unsigned long)(seg) << 16) | (unsigned)(ofs)))
#define FP_OFF(p) (*((unsigned *)&(p)))
#define FP_SEG(p) (*((unsigned *)&(p) + 1))

/* memory peek/poke */
unsigned peek(unsigned seg, unsigned ofs);
unsigned char peekb(unsigned seg, unsigned ofs);
void poke(unsigned seg, unsigned ofs, unsigned val);
void pokeb(unsigned seg, unsigned ofs, unsigned char val);

/* port I/O */
unsigned char inportb(unsigned port);
unsigned inport(unsigned port);
void outportb(unsigned port, unsigned char val);
void outport(unsigned port, unsigned val);

/* interrupts / vectors. get/setvect exchange interrupt-handler pointers; the
 * `interrupt`/`far` keywords are defined away in clion_shim.h, so the ISR type
 * reduces to a plain `void (*)()`. */
void geninterrupt(int intno);
void enable(void);
void disable(void);
void delay(unsigned ms);
void (*getvect(int intno))();
void setvect(int intno, void (*isr)());

#endif
