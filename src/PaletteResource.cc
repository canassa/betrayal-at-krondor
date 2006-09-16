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
#include "PaletteResource.h"

PaletteResource::PaletteResource()
: TaggedResource()
{
  palette = new Palette(0);
}

PaletteResource::~PaletteResource()
{
  if (palette) {
    delete palette;
  }
}

Palette *
PaletteResource::GetPalette() const
{
  return palette;
}

void
PaletteResource::Load(FileBuffer *buffer)
{
  try {
    Split(buffer);
    FileBuffer *vgabuf;
    if (!Find(TAG_VGA, vgabuf)) {
      Clear();
      throw DataCorruption(__FILE__, __LINE__);
    }
    unsigned int size = vgabuf->GetSize() / 3;
    if (palette) {
      delete palette;
    }
    palette = new Palette(size);
    for (unsigned int i = 0; i < size; i++) {
      Color c;
      c.r = (vgabuf->GetUint8() << 2) + 0x03;
      c.g = (vgabuf->GetUint8() << 2) + 0x03;
      c.b = (vgabuf->GetUint8() << 2) + 0x03;
      palette->SetColor(i, c);
    }
    Clear();
  } catch (Exception &e) {
    e.Print("PaletteResource::Load");
    Clear();
  }
}
