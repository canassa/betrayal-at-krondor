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

#include "Exception.h"
#include "Font.h"
#include "MediaToolkit.h"

Font::Font()
        : first(0)
        , height(0)
{}

Font::~Font()
{
    fontGlyphs.clear();
}

unsigned int
Font::GetFirst() const
{
    return first;
}

void
Font::SetFirst(const unsigned int n)
{
    first = n;
}

unsigned int
Font::GetHeight() const
{
    return height;
}

void
Font::SetHeight(const unsigned int h)
{
    height = h;
}

unsigned int
Font::GetWidth(const unsigned int n) const
{
    if (n < fontGlyphs.size())
    {
        return fontGlyphs[n].width;
    }
    else
    {
        throw IndexOutOfRange(__FILE__, __LINE__);
    }
}

unsigned int
Font::GetSize() const
{
    return fontGlyphs.size();
}

FontGlyph&
Font::GetGlyph(const unsigned int n)
{
    if (n < fontGlyphs.size())
    {
        return fontGlyphs[n];
    }
    else
    {
        throw IndexOutOfRange(__FILE__, __LINE__);
    }
}

void
Font::AddGlyph(FontGlyph& glyph)
{
    fontGlyphs.push_back(glyph);
}

void
Font::DrawChar(const unsigned int x, const unsigned int y, const unsigned int ch, const unsigned int color, const bool italic)
{
    Video *video = MediaToolkit::GetInstance()->GetVideo();
    if ((int)(ch - first) >= 0)
    {
        if (italic)
        {
            video->DrawGlyphItalic(x, y, fontGlyphs[ch - first].width, height, color, fontGlyphs[ch - first].data);
        }
        else
        {
            video->DrawGlyph(x, y, fontGlyphs[ch - first].width, height, color, fontGlyphs[ch - first].data);
        }
    }
}
