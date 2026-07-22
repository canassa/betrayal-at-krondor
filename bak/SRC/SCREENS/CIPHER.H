#ifndef BAK_CIPHER_H
#define BAK_CIPHER_H

#include "structs.h"

extern int cipher_dial_puzzle_run(int nPuzzleId);
extern void cipher_puzzle_parse_table(unsigned char far *pTableData);
extern void cipher_puzzle_layout_letters(MenuPage *page);
extern int cipher_puzzle_is_solved(void);
extern void cipher_anim_bevel_text_dropin(MenuEntry *pEntry, int nCol);
extern void cipher_menu_draw_hotkey_labels(MenuPage *page);
extern void cipher_draw_bevelled_box(int x, int y, int w, int h);

#endif
