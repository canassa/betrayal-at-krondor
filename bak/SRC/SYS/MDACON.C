#include <stdio.h>

#include "structs.h"
#include "SRC/SYS/MDACON.H"

unsigned short g_bMdaEnabled = 0x0000;

void mdacon_clear_screen(void) {
    unsigned short far *p;
    int i;

    p = (unsigned short far *)0xb0000000L;

    for (i = 0; i < 0x780; i++) {
        *p++ = 7;
    }
}

void far mdacon_write_string(int col, int row, char *str) {
    int off;
    char far *p;
    char *s;

    off = col;
    s = str;
    p = (char far *)0xb0000000L;
    off += row * 0x50;
    p += off * 2;
    while (*s != '\0') {
        *p++ = *s++;
        *p++ = '\x18';
    }
    return;
}

void far mdacon_printf(int col, int row, char *fmt, ...) {
    char buf[100];
    char *args;

    args = (char *)(&fmt + 1);
    vsprintf(buf, fmt, args);
    mdacon_write_string(col, row, buf);
    return;
}

void far mdacon_draw_window_frame(int x, int y, int w, int h, int fill_interior) {
    int i;
    int row;

    mdacon_printf(x, y, "\xda");
    i = x + 1;
    while (x + w - 1 > i) {
        mdacon_printf(i, y, "\xc4");
        i++;
    }
    mdacon_printf(i, y, "\xb7");
    row = y + 1;
    while (y + h - 1 > row) {
        mdacon_printf(x, row, "\xb3");
        if (fill_interior != 0) {
            i = x + 1;
            while (x + w - 1 > i) {
                mdacon_printf(i, row, " ");
                i++;
            }
        }
        i = x + w - 1;
        mdacon_printf(i, row, "\xba");
        row++;
    }
    mdacon_printf(x, row, "\xd4");
    i = x + 1;
    while (x + w - 1 > i) {
        mdacon_printf(i, row, "\xcd");
        i++;
    }
    mdacon_printf(i, row, "\xbc");
    return;
}
