#ifndef BAK_BOOKVIEW_H
#define BAK_BOOKVIEW_H

#include "structs.h"

extern void bookview_init(void);
extern void bookview_shutdown(void);
extern BookPage far *bookview_find_page_by_number(PageDirectory far *page_directory,
                                                  int page_number);
extern int bookview_show(char *filename, int page_number);

#endif
