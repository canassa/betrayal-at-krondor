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
#include "SDL_Video.h"

SDL_Video::SDL_Video()
: Video()
, info(SDL_GetVideoInfo())
, disp(0)
, stretched(0)
, buffer(0)
{
}

SDL_Video::~SDL_Video()
{
  if (disp) {
    SDL_FreeSurface(disp);
  }
  if (stretched) {
    SDL_FreeSurface(stretched);
  }
  if (buffer) {
    SDL_FreeSurface(buffer);
  }
}

void
SDL_Video::CreateScreen(const int w, const int h)
{
  SDL_ShowCursor(SDL_DISABLE);
  SDL_WarpMouse(0, 0);
  SDL_WM_SetCaption("xBaK", 0);
  if (SDL_EnableKeyRepeat(0, 0) < 0) {
    throw SDL_Exception(SDL_GetError());
  }
  int width = w * scaling;
  int height = h * scaling;
  unsigned int flags = SDL_ANYFORMAT;
  if (info->hw_available) {
    flags |= SDL_HWSURFACE;
  } else {
    flags |= SDL_SWSURFACE;
  }
  int bpp = SDL_VideoModeOK(width, height, VIDEO_BPP, flags);
  if (bpp <= 0) {
    throw SDL_Exception(SDL_GetError());
  }
  disp = SDL_SetVideoMode(width, height, bpp, flags);
  if (!disp) {
    throw SDL_Exception(SDL_GetError());
  }
  stretched = SDL_CreateRGBSurface(SDL_SWSURFACE, width, height, VIDEO_BPP, 0, 0, 0, 0);
  if (!stretched) {
    throw SDL_Exception(SDL_GetError());
  }
  buffer = SDL_CreateRGBSurface(SDL_SWSURFACE, w, h, VIDEO_BPP, 0, 0, 0, 0);
  if (!buffer) {
    throw SDL_Exception(SDL_GetError());
  }
}

void
SDL_Video::Clear()
{
  SDL_FillRect(buffer, 0, 0);
  SDL_UpdateRect(buffer, 0, 0, 0, 0);
}

void
SDL_Video::Clear(int x, int y, int w, int h)
{
  SDL_Rect rect = {x, y, w, h};
  SDL_FillRect(buffer, &rect, 0);
  SDL_UpdateRect(buffer, x, y, w, h);
}

unsigned int
SDL_Video::GetPixel(const int x, const int y)
{
  if ((x >= 0) && (x < buffer->w) && (y >= 0) && (y < buffer->h)) {
    uint8_t *p = (uint8_t *)buffer->pixels + y * buffer->pitch + x;
    return (unsigned int)(*p);
  }
  return 0;
}

void
SDL_Video::PutPixel(const int x, const int y, const unsigned int c)
{
  if ((x >= 0) && (x < buffer->w) && (y >= 0) && (y < buffer->h)) {
    uint8_t *p = (uint8_t *)buffer->pixels + y * buffer->pitch + x;
    *p = (uint8_t)c;
  }
}

void
SDL_Video::DrawHLine(const int x, const int y, const int w, const unsigned int c)
{
  SDL_Rect rect = {x, y, w, 1};
  SDL_FillRect(buffer, &rect, c);
  SDL_UpdateRect(buffer, x, y, w, 1);
}

void
SDL_Video::DrawVLine(const int x, const int y, const int h, const unsigned int c)
{
  SDL_Rect rect = {x, y, 1, h};
  SDL_FillRect(buffer, &rect, c);
  SDL_UpdateRect(buffer, x, y, 1, h);
}

#define swap(a,b) { int h = a; a = b; b = h; }

void
SDL_Video::DrawLine(int x1, int y1, int x2, int y2, const unsigned int c)
{
  // Bresenham's line algorithm
  bool steep = abs(y2 - y1) > abs(x2 - x1);
  if (steep) {
    swap(x1, y1);
    swap(x2, y2);
  }
  if (x1 > x2) {
    swap(x1, x2);
    swap(y1, y2);
  }
  int dx = x2 - x1;
  int dy = abs(y2 - y1);
  int err = 0;
  int yy;
  if (y1 < y2) {
    yy = 1;
  } else {
    yy = -1;
  }
  int y = y1;
  for (int x = x1; x <= x2; x++) {
    if (steep) {
      PutPixel(y, x, c);
    } else {
      PutPixel(x, y, c);
    }
    err += dy;
    if ((err + err) >= dx) {
      y += yy;
      err -= dx;
    }
  }
  SDL_UpdateRect(buffer, x1, y1, x2 - x1 + 1, y2 - y1 + 1);
}

void
SDL_Video::FillRect(const int x, const int y, const int w, const int h, const unsigned int c)
{
  SDL_Rect rect = {x, y, w, h};
  SDL_FillRect(buffer, &rect, c);
  SDL_UpdateRect(buffer, x, y, w, h);
}

void
SDL_Video::ReadImage(const int x, const int y, const int w, const int h, uint8_t *p)
{
  for (int j = y; j < y + h; j++) {
    for (int i = x; i < x + w; i++) {
      *p++ = GetPixel(i, j);
    }
  }
}

void
SDL_Video::DrawImage(const int x, const int y, const int w, const int h, uint8_t *p)
{
  for (int j = y; j < y + h; j++) {
    for (int i = x; i < x + w; i++) {
      PutPixel(i, j, *p++);
    }
  }
  SDL_UpdateRect(buffer, x, y, w, h);
}

void
SDL_Video::DrawImage(const int x, const int y, const int w, const int h,
                     const int xx, const int yy, const int ww, const int hh, uint8_t *p)
{
  for (int j = y; j < y + h; j++) {
    for (int i = x; i < x + w; i++) {
      if ((i >= xx) && (i < (x + ww)) && (j >= yy) && (j < (y + hh))) {
        PutPixel(i, j, *p);
      }
      p++;
    }
  }
  SDL_UpdateRect(buffer, x, y, w, h);
}

void
SDL_Video::DrawImage(const int x, const int y, const int w, const int h, uint8_t *p, const uint8_t transparant)
{
  for (int j = y; j < y + h; j++) {
    for (int i = x; i < x + w; i++) {
      if (*p != transparant) {
        PutPixel(i, j, *p);
      }
      p++;
    }
  }
  SDL_UpdateRect(buffer, x, y, w, h);
}

void
SDL_Video::DrawGlyph(const int x, const int y, const int w, const int h, const uint8_t c, uint16_t *p)
{
  for (int j = 0; j < h; j++) {
    for (int i = 0; i < w; i++) {
      if (*p & (0x8000 >> i)) {
        PutPixel(x + i, y + j, c);
      }
    }
    p++;
  }
  SDL_UpdateRect(buffer, x, y, w, h);
}

void
SDL_Video::DrawGlyphItalic(const int x, const int y, const int w, const int h, const uint8_t c, uint16_t *p)
{
  for (int j = 0; j < h; j++) {
    for (int i = 0; i < w; i++) {
      if (*p & (0x8000 >> i)) {
        PutPixel(x + i + 4 - (j / 3), y + j, c);
      }
    }
    p++;
  }
  SDL_UpdateRect(buffer, x, y, w, h);
}

void
SDL_Video::GetPalette(Color *color, const unsigned int first, const unsigned int n)
{
  if (buffer->format->palette) {
    memcpy(color, &(buffer->format->palette->colors[first]), n * sizeof(SDL_Color));
  }
}

void
SDL_Video::SetPalette(Color *color, const unsigned int first, const unsigned int n)
{
  if (buffer->format->palette) {
    SDL_SetPalette(buffer, SDL_LOGPAL, (SDL_Color *)color, first, n);
  }
  if (stretched->format->palette) {
    SDL_SetPalette(stretched, SDL_LOGPAL, (SDL_Color *)color, first, n);
  }
}

void
SDL_Video::SetPointerPosition(int x, int y)
{
  SDL_WarpMouse(x * scaling, y * scaling);
}

void
SDL_Video::Refresh()
{
  for (int y = 0; y < buffer->h; y++) {
    for (int x = 0; x < buffer->w; x++) {
      memcpy((uint8_t *)stretched->pixels + y * scaling * stretched->pitch + x * scaling,
             (uint8_t *)buffer->pixels + y * buffer->pitch + x, scaling);
    }
    for (unsigned int i = 1; i < scaling; i++) {
      memcpy((uint8_t *)stretched->pixels + (y * scaling + i) * stretched->pitch,
             (uint8_t *)stretched->pixels + y * scaling * stretched->pitch, stretched->w);
    }
  }
  SDL_UpdateRect(stretched, 0, 0, 0, 0);
  SDL_BlitSurface(stretched, 0, disp, 0);
  SDL_Flip(disp);
}

void
SDL_Video::GrabInput(const bool toggle)
{
  SDL_WM_GrabInput(toggle ? SDL_GRAB_ON : SDL_GRAB_OFF);
}

void
SDL_Video::SaveScreenShot(const std::string& filename)
{
  SDL_SaveBMP(buffer, filename.c_str());
}
