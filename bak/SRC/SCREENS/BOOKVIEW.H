#ifndef BAK_BOOKVIEW_H
#define BAK_BOOKVIEW_H

#include "structs.h"

extern unsigned short g_wTextWrapXAccum;
extern unsigned short g_wTextWrapLinesDrawn;
extern unsigned short g_wTextWrapLinesRemaining;
extern BookViewerState *g_pBookViewer;

extern void bookview_init(void);
extern void bookview_shutdown(void);
extern int bookview_show(char *filename, int page_number);
extern BookPage far *bookview_find_page_by_number(PageDirectory far *page_directory,
                                                  int page_number);

#endif
