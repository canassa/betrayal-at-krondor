#include <ctype.h>

#include "structs.h"
#include "globals.h"
#include "SRC/SCREENS/BOOKVIEW.H"
#include "SRC/UI/TEXTWRAP.H"
#include "SRC/GFX/FONT/FONT.H"

struct textline {
    int start;
    int end;
};

static int far textwrap_is_break_point(long text, int line_start, int pos) {
    char ch;
    int i;

    ch = toupper(*((char far *)((char huge *)text + pos)));
    if (ch == ' ')
        return 1;
    if (isalpha(ch) == 0)
        goto fail;
    if (pos - line_start <= 3)
        goto fail;
    i = 0;
    do {
        if (*((char far *)((char huge *)text + (pos + i - 3))) != '.')
            goto fail;
        i++;
    } while (i < 3);
    return 1;
fail:
    return 0;
}

int far textwrap_compute_lines(long text, int max_width, int *out_lines, int max_lines) {
    int pos;
    int line_start;
    char no_break;
    int line_width;
    int count;
    unsigned int width;
    unsigned int height;

#define CH(i) (*((char far *)((char huge *)text + (i))))

    line_start = 0;
    count = 0;
    while (count < max_lines && CH(line_start) != '\0') {
        pos = line_start;
        line_width = 0;
        no_break = 1;
        while (CH(pos) != '\0' && CH(pos) != '\n') {
            font_glyph_metrics(CH(pos), &width, &height);
            if (max_width < (int)(line_width + width))
                break;
            line_width += (int)width;
            if (textwrap_is_break_point(text, line_start, pos))
                no_break = 0;
            pos++;
        }
        if (CH(pos) != '\0' && CH(pos) != '\n' && !no_break) {
            while (pos != line_start && textwrap_is_break_point(text, line_start, pos) == 0)
                pos--;
            do {
                if (pos == line_start)
                    break;
            } while (textwrap_is_break_point(text, line_start, --pos) != 0);
            pos++;
        }
        if (out_lines != 0) {
            ((struct textline *)out_lines)[count].start = line_start;
            ((struct textline *)out_lines)[count].end = pos;
        }
        count++;
        line_start = pos;
        if (CH(line_start) == '\n') {
            line_start = line_start + 1;
        } else {
            while (CH(line_start) != '\0' && CH(line_start) == ' ')
                line_start++;
        }
    }
    if (count < max_lines && out_lines != 0) {
        ((struct textline *)out_lines)[count].start = -1;
        ((struct textline *)out_lines)[count].end = -1;
    }
    return count;
}

#undef CH

#pragma option -Od

void textwrap_draw_aligned(long text, int x, int y, int max_width, int max_height, int line_spacing,
                           unsigned int flags, int first_line) {
    struct textline lines[90];
    int line_height;
    int count;
    int hoff;
    int voff;
    char saved;
    register unsigned int f = flags;
    register int fl = first_line;

    line_height = g_graphics_context.pFont_height[0];
    hoff = 0;
    voff = 0;
    if ((f & 0) != 0)

        count = textwrap_compute_lines(text, 999, (int *)lines, 0x5a);
    else
        count = textwrap_compute_lines(text, max_width, (int *)lines, 0x5a);

    for (g_wTextWrapLinesRemaining = 0;
         max_height <
         (int)((line_height + line_spacing) * ((count - fl) - g_wTextWrapLinesRemaining) -
               line_spacing);
         g_wTextWrapLinesRemaining++) {
    }
    if (g_wTextWrapLinesRemaining == 1) {
        g_wTextWrapLinesRemaining++;
    }
    g_wTextWrapXAccum = 0;
    g_wTextWrapLinesDrawn = (count - g_wTextWrapLinesRemaining) - fl;

    if (((f & 0x20) != 0) || ((f & 0x10) != 0)) {
        voff = max_height - (line_height + line_spacing) * g_wTextWrapLinesDrawn;
        if ((f & 0x10) != 0) {
            voff = voff / 2;
        }
    }

    while (fl < (int)(count - g_wTextWrapLinesRemaining)) {
        if ((voff + line_height) > max_height)
            break;
        saved = *((char huge *)text + lines[fl].end);
        *((char huge *)text + lines[fl].end) = 0;
        if (((f & 2) != 0) || ((f & 4) != 0)) {
            hoff = max_width - font_text_pixel_width((char far *)text + lines[fl].start);
            if ((f & 2) != 0) {
                hoff = hoff / 2;
            }
        }
        g_wTextWrapXAccum += (lines[fl].end - lines[fl].start);
        font_draw_text_far((char far *)text + lines[fl].start, x + hoff, y + voff);
        *((char huge *)text + lines[fl].end) = saved;
        voff += line_height + line_spacing;
        fl++;
    }
}
