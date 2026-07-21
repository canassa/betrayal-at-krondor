/* conio.h — IDE-indexing stub (NOT Borland's real conio.h). See clion_shim.h.
 * Declares the common Borland console-I/O vocabulary so `#include <conio.h>`
 * sources index without a missing-include error. Declarations only. */
#ifndef BAK_IDE_CONIO_H
#define BAK_IDE_CONIO_H
int getch(void);
int getche(void);
int kbhit(void);
int putch(int c);
int cputs(const char *s);
int cprintf(const char *fmt, ...);
void clrscr(void);
void gotoxy(int x, int y);
int wherex(void);
int wherey(void);
int inp(unsigned port);
unsigned outp(unsigned port, int val);
#endif
