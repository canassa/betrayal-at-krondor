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
 * Copyright (C) 2005-2006  Guido de Jong <guidoj@users.sf.net>
 */

#include "TextArea.h"

TextArea::TextArea(const unsigned int w, const unsigned int h, FontResource &fnt)
: width(w)
, height(h)
, font(fnt)
, text("")
, color(0)
{
}

TextArea::~TextArea()
{
}

void
TextArea::SetText(const std::string &s)
{
  text = s;
}

void
TextArea::SetColor(const unsigned int c)
{
  color = c;
}

void
TextArea::Draw(const unsigned int x, const unsigned int y, const bool italic)
{
  unsigned int i = 0;
  unsigned int h = 0;
  while ((i < text.length()) && (h + font.GetHeight() < height)) {
    unsigned int w = 0;
    while ((i < text.length()) && (w + font.GetWidth(text[i] - font.GetFirst()) < width)) {
      font.DrawChar(x + w, y + h, text[i], color, italic);
      w += font.GetWidth((unsigned int)text[i] - font.GetFirst());
      i++;
    }
    h += font.GetHeight();
  }
}

