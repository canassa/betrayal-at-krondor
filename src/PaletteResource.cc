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
, size(0)
, colors(0)
{
}

PaletteResource::~PaletteResource()
{
  if (colors) {
    delete[] colors;
  }
}

unsigned int
PaletteResource::GetSize() const
{
  return size;
}

Color*
PaletteResource::GetColors() const
{
  return colors;
}

void
PaletteResource::Fill()
{
  size = VIDEO_COLORS;
  colors = new Color[size];
  memset(colors, 0, size * sizeof(Color));
  colors[0].r = 0;
  colors[0].g = 0;
  colors[0].b = 0;
  colors[15].r = 255;
  colors[15].g = 255;
  colors[15].b = 255;
}

void
PaletteResource::Load(FileBuffer *buffer)
{
  try {
    Split(buffer);
    FileBuffer *vgabuf;
    if (!Find(TAG_VGA, vgabuf)) {
      Clear();
      throw DataCorruption("PaletteResource::Load");
    }
    size = vgabuf->GetSize() / 3;
    colors = new Color[size];
    for (unsigned int i = 0; i < size; i++) {
      colors[i].r = vgabuf->GetUint8() << 2;
      colors[i].g = vgabuf->GetUint8() << 2;
      colors[i].b = vgabuf->GetUint8() << 2;
    }
    Clear();
  } catch (Exception &e) {
    e.Print("PaletteResource::Load");
    Clear();
  }
}

void
PaletteResource::Activate(Video *video, const unsigned int first, const unsigned int n)
{
  video->SetPalette(colors, first, n);
}

void
PaletteResource::Retrieve(Video *video, const unsigned int first, const unsigned int n)
{
  if ((colors != 0) && (size < (first + n))) {
    delete colors;
    colors = 0;
  }
  if (!colors) {
    size = first + n;
    colors = new Color[size];
  }
  video->GetPalette(colors, first, n);
}

void
PaletteResource::FadeFrom(Video *video, Color* from, const unsigned int first, const unsigned int n, const unsigned int steps, const unsigned int delay, Clock *clock)
{
  Color* tmp = new Color[VIDEO_COLORS];
  for (unsigned int i = 0; i <= steps; i++) {
    float x = (float)i / (float)steps;
    for (unsigned int j = first; j < first + n; j++) {
      tmp[j].r = from[j].r + (int)((colors[j].r - from[j].r) * x);
      tmp[j].g = from[j].g + (int)((colors[j].g - from[j].g) * x);
      tmp[j].b = from[j].b + (int)((colors[j].b - from[j].b) * x);
    }
    video->SetPalette(&tmp[first], first, n);
    video->Refresh();
    clock->Delay(delay);
  }
  delete[] tmp;
}

void
PaletteResource::FadeTo(Video *video, Color* to, const unsigned int first, const unsigned int n, const unsigned int steps, const unsigned int delay, Clock *clock)
{
  Color* tmp = new Color[VIDEO_COLORS];
  video->GetPalette(tmp, 0, VIDEO_COLORS);
  for (unsigned int i = 0; i <= steps; i++) {
    float x = (float)i / (float)steps;
    for (unsigned int j = first; j < first + n; j++) {
      tmp[j].r = colors[j].r + (int)((to[j].r - colors[j].r) * x);
      tmp[j].g = colors[j].g + (int)((to[j].g - colors[j].g) * x);
      tmp[j].b = colors[j].b + (int)((to[j].b - colors[j].b) * x);
    }
    video->SetPalette(&tmp[first], first, n);
    video->Refresh();
    clock->Delay(delay);
  }
  delete[] tmp;
}

void
PaletteResource::FadeIn(Video *video, const unsigned int first, const unsigned int n, const unsigned int steps, const unsigned int delay, Clock *clock)
{
  Color* from = new Color[VIDEO_COLORS];
  memset(from, 0, VIDEO_COLORS * sizeof(Color));
  FadeFrom(video, from, first, n, steps, delay, clock);
  delete[] from;
}

void
PaletteResource::FadeOut(Video *video, const unsigned int first, const unsigned int n, const unsigned int steps, const unsigned int delay, Clock *clock)
{
  Color* to = new Color[VIDEO_COLORS];
  memset(to, 0, VIDEO_COLORS * sizeof(Color));
  FadeTo(video, to, first, n, steps, delay, clock);
  delete[] to;
}

