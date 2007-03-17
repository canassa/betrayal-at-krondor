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
 * Copyright (C) 2005-2007  Guido de Jong <guidoj@users.sf.net>
 */

#include "Exception.h"
#include "PaletteResource.h"

PaletteResource::PaletteResource()
: TaggedResource()
{
  palette = new Palette(0);
}

PaletteResource::~PaletteResource()
{
  Clear();
}

Palette *
PaletteResource::GetPalette() const
{
  return palette;
}

void
PaletteResource::Clear()
{
  if (palette) {
    delete palette;
    palette = 0;
  }
}

void
PaletteResource::Load(FileBuffer *buffer)
{
  try {
    Clear();
    Split(buffer);
    FileBuffer *vgabuf;
    if (!Find(TAG_VGA, vgabuf)) {
      ClearTags();
      throw DataCorruption(__FILE__, __LINE__);
    }
    unsigned int size = vgabuf->GetSize() / 3;
    palette = new Palette(size);
    for (unsigned int i = 0; i < size; i++) {
      Color c;
      c.r = (vgabuf->GetUint8() << 2);
      c.g = (vgabuf->GetUint8() << 2);
      c.b = (vgabuf->GetUint8() << 2);
      palette->SetColor(i, c);
    }
    ClearTags();
  } catch (Exception &e) {
    e.Print("PaletteResource::Load");
    ClearTags();
    throw;
  }
}

void
PaletteResource::Save(FileBuffer *buffer)
{
  try {
    // TODO
    buffer = buffer;
  } catch (Exception &e) {
    e.Print("PaletteResource::Save");
    throw;
  }
}
