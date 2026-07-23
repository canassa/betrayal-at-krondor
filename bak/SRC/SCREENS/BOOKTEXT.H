#ifndef BAK_BOOKTEXT_H
#define BAK_BOOKTEXT_H

#include "structs.h"

extern char g_szRomanDigits[7];
extern short g_anRomanValues[7];
extern short g_anRomanSubPair[7];

extern int booktext_render_page(PageDirectory far *page_directory, BookPage far *page,
                                int redraw_bg);
extern int booktext_layout_next_run(BookPage far *page, int y0, int y1, int y_bot);
extern int booktext_is_break_char(char c);

#endif
