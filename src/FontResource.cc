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

#include "Exception.h"
#include "FontResource.h"
#include "MediaToolkit.h"

FontResource::FontResource()
: TaggedResource()
, first(0)
, height(0) {
}

FontResource::~FontResource()
{
  for (unsigned int i = 0; i < fontGlyphs.size(); i++) {
    delete fontGlyphs[i];
  }
  fontGlyphs.clear();
}

unsigned int
FontResource::GetFirst() const
{
  return first;
}

unsigned int
FontResource::GetHeight() const
{
  return height;
}

unsigned int
FontResource::GetWidth(const unsigned int n) const
{
  return fontGlyphs[n]->width;
}

unsigned int
FontResource::GetSize() const
{
  return fontGlyphs.size();
}

FontGlyph*
FontResource::GetGlyph(const unsigned int n)
{
  return fontGlyphs[n];
}

void
FontResource::Load(FileBuffer *buffer)
{
  try {
    Split(buffer);
    FileBuffer *fntbuf;
    if (!Find(TAG_FNT, fntbuf)) {
      Clear();
      throw DataCorruption(__FILE__, __LINE__);
    }
    fntbuf->Skip(2);
    height = (unsigned int)fntbuf->GetUint8();
    fntbuf->Skip(1);
    first = (unsigned int)fntbuf->GetUint8();
    unsigned int numChars = (unsigned int)fntbuf->GetUint8();
    fntbuf->Skip(2);
    if (fntbuf->GetUint8() != 0x01) {
      Clear();
      throw CompressionError(__FILE__, __LINE__);
    }
    unsigned int size = (unsigned int)fntbuf->GetUint32LE();
    FileBuffer *glyphbuf = new FileBuffer(size);
    fntbuf->DecompressRLE(glyphbuf);
    unsigned int *glyphOffset = new unsigned int [numChars];
    for (unsigned int i = 0; i < numChars; i++) {
      glyphOffset[i] = glyphbuf->GetUint16LE();
    }
    for (unsigned int i = 0; i < numChars; i++) {
      FontGlyph *glyph = new FontGlyph;
      glyph->width = (unsigned int)glyphbuf->GetUint8();
      fontGlyphs.push_back(glyph);
    }
    unsigned int glyphDataStart = glyphbuf->GetBytesDone();
    for (unsigned int i = 0; i < numChars; i++) {
      glyphbuf->Seek(glyphDataStart + glyphOffset[i]);
      for (unsigned int j = 0; j < height; j++) {
        fontGlyphs[i]->data[j] = (uint16_t)glyphbuf->GetUint8() << 8;
        if (fontGlyphs[i]->width > 8) {
          fontGlyphs[i]->data[j] += (uint16_t)glyphbuf->GetUint8();
        }
      }
    }
    delete[] glyphOffset;
    delete glyphbuf;
    Clear();
  } catch (Exception &e) {
    e.Print("FontResource::Load");
    Clear();
  }
}

void
FontResource::DrawChar(const unsigned int x, const unsigned int y, const unsigned int ch, const unsigned int color, const bool italic)
{
  Video *video = MediaToolkit::GetInstance()->GetVideo();
  if ((int)(ch - first) >= 0) {
    if (italic) {
      video->DrawGlyphItalic(x, y, fontGlyphs[ch - first]->width, height, color, fontGlyphs[ch - first]->data);
    } else {
      video->DrawGlyph(x, y, fontGlyphs[ch - first]->width, height, color, fontGlyphs[ch - first]->data);
    }
  }
}
