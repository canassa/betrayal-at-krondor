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

#ifndef FONT_RESOURCE_H
#define FONT_RESOURCE_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "TaggedResource.h"
#include "Video.h"

static const unsigned int MAX_FONT_HEIGHT = 16;

typedef uint16_t GlyphData[MAX_FONT_HEIGHT]; 

typedef struct _FontGlyph {
  unsigned int width;
  GlyphData data;
} FontGlyph;

class FontResource: public TaggedResource {
  private:
    unsigned int first;
    unsigned int height;
    std::vector<FontGlyph*> fontGlyphs;
  public:
    FontResource();
    virtual ~FontResource();
    unsigned int GetFirst() const;
    unsigned int GetHeight() const;
    unsigned int GetWidth(const unsigned int n) const;
    unsigned int GetSize() const;
    FontGlyph* GetGlyph(const unsigned int n);
    void Load(FileBuffer *buffer);
    void DrawChar(Video *video, const unsigned int x, const unsigned int y, const unsigned int ch, const unsigned int color);
};

#endif

