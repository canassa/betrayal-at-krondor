/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, GOOD TITLE or
 * NON INFRINGEMENT.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * Copyright (C) 2005-2008 Guido de Jong <guidoj@users.sf.net>
 */

#ifndef FONT_H
#define FONT_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#ifdef HAVE_STDINT_H
#include <stdint.h>
#else
#include "alt_stdint.h"
#endif

static const unsigned int MAX_FONT_HEIGHT = 16;

typedef uint16_t GlyphData[MAX_FONT_HEIGHT];

struct FontGlyph
{
    unsigned int width;
    GlyphData data;
};

class Font
{
private:
    unsigned int first;
    unsigned int height;
    std::vector<FontGlyph> fontGlyphs;
public:
    Font();
    virtual ~Font();
    unsigned int GetFirst() const;
    void SetFirst ( const unsigned int n );
    unsigned int GetHeight() const;
    void SetHeight ( const unsigned int h );
    unsigned int GetWidth ( const unsigned int n ) const;
    unsigned int GetSize() const;
    FontGlyph& GetGlyph ( const unsigned int n );
    void AddGlyph ( FontGlyph& glyph );
    void DrawChar ( const unsigned int x, const unsigned int y, const unsigned int ch, const unsigned int color, const bool italic );
};

#endif
