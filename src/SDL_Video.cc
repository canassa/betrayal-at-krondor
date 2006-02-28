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
, disp(0)
, buffer(0)
{
}

SDL_Video::~SDL_Video()
{
  if (disp) {
    SDL_FreeSurface(disp);
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
  SDL_WM_GrabInput(SDL_GRAB_ON);
  if (SDL_EnableKeyRepeat(0, 0) < 0) {
    throw SDL_Exception(SDL_GetError());
  }
  int width = w * scaling;
  int height = h * scaling;
  unsigned int flags = SDL_HWSURFACE | SDL_ANYFORMAT;
  int bpp = SDL_VideoModeOK(width, height, VIDEO_BPP, flags);
  if (bpp <= 0) {
    throw SDL_Exception(SDL_GetError());
  }
  disp = SDL_SetVideoMode(width, height, bpp, flags);
  if (!disp) {
    throw SDL_Exception(SDL_GetError());
  }
  if (SDL_BYTEORDER == SDL_BIG_ENDIAN) {
    buffer = SDL_CreateRGBSurface(
                 SDL_SWSURFACE, width, height, VIDEO_BPP,
                 0x000000ff, 0x0000ff00, 0x00ff0000, 0xff000000);
  } else {
    buffer = SDL_CreateRGBSurface(
                 SDL_SWSURFACE, width, height, VIDEO_BPP,
                 0xff000000, 0x00ff0000, 0x0000ff00, 0x000000ff);
  }
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
  SDL_UpdateRect(buffer, x * scaling, y * scaling, w * scaling, h * scaling);
}

unsigned int
SDL_Video::GetScaledPixel(const int x, const int y)
{
  if ((x >= 0) && (x < buffer->w) && (y >= 0) && (y < buffer->h)) {
    unsigned int bpp = buffer->format->BytesPerPixel;
    uint8_t *p = (uint8_t *)buffer->pixels + y * buffer->pitch + x * bpp;
    switch (bpp) {
      case 1:
        return (unsigned int)(*p);
        break;
      case 2:
        return (unsigned int)(*(uint16_t *)p);
        break;
      case 3:
        if (SDL_BYTEORDER == SDL_BIG_ENDIAN) {
          return ((unsigned int)p[2] + ((unsigned int)p[1] << 8) + ((unsigned int)p[0] << 16));
        } else {
          return ((unsigned int)p[0] + ((unsigned int)p[1] << 8) + ((unsigned int)p[2] << 16));
        }
        break;
      case 4:
        return (unsigned int)(*(uint32_t *)p);
        break;
      default:
        break;
    }
  }
  return 0;
}

void
SDL_Video::PutScaledPixel(const int x, const int y, const unsigned int c)
{
  if ((x >= 0) && (x < buffer->w) && (y >= 0) && (y < buffer->h)) {
    unsigned int bpp = buffer->format->BytesPerPixel;
    uint8_t *p = (uint8_t *)buffer->pixels + y * buffer->pitch + x * bpp;
    switch (bpp) {
      case 1:
        *p = (uint8_t)c;
        break;
      case 2:
        *(uint16_t *)p = (uint16_t)c;
        break;
      case 3:
        if (SDL_BYTEORDER == SDL_BIG_ENDIAN) {
          p[0] = (uint8_t)(c >> 16) & 0xff;
          p[1] = (uint8_t)(c >> 8) & 0xff;
          p[2] = (uint8_t)c & 0xff;
        } else {
          p[0] = (uint8_t)c & 0xff;
          p[1] = (uint8_t)(c >> 8) & 0xff;
          p[2] = (uint8_t)(c >> 16) & 0xff;
        }
        break;
      case 4:
        *(uint32_t *)p = (uint32_t)c;
        break;
      default:
        break;
    }
  }
}

unsigned int
SDL_Video::GetPixel(const int x, const int y)
{
  return GetScaledPixel(x * scaling, y * scaling);
}

void
SDL_Video::PutPixel(const int x, const int y, const unsigned int c)
{
  for (unsigned int i = 0; i < scaling; i++) {
    for (unsigned int j = 0; j < scaling; j++) {
      PutScaledPixel(x * scaling + i, y * scaling + j, c);
    }
  }
}

void
SDL_Video::DrawHLine(const int x, const int y, const int w, const unsigned int c)
{
  for (int i = x; i < x + w; i++) {
    PutPixel(i, y, c);
  }
  SDL_UpdateRect(buffer, x * scaling, y * scaling, w * scaling, scaling);
}

void
SDL_Video::DrawVLine(const int x, const int y, const int h, const unsigned int c)
{
  for (int j = y; j < y + h; j++) {
    PutPixel(x, j, c);
  }
  SDL_UpdateRect(buffer, x * scaling, y * scaling, scaling, h * scaling);
}

void
SDL_Video::FillRect(const int x, const int y, const int w, const int h, const unsigned int c)
{
  for (int j = y; j < y + h; j++) {
    for (int i = x; i < x + w; i++) {
      PutPixel(i, j, c);
    }
  }
  SDL_UpdateRect(buffer, x * scaling, y * scaling, w * scaling, h * scaling);
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
  SDL_UpdateRect(buffer, x * scaling, y * scaling, w * scaling, h * scaling);
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
  SDL_UpdateRect(buffer, x * scaling, y * scaling, w * scaling, h * scaling);
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
  SDL_UpdateRect(buffer, x * scaling, y * scaling, w * scaling, h * scaling);
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
  SDL_UpdateRect(buffer, x * scaling, y * scaling, w * scaling, h * scaling);
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
}

void
SDL_Video::SetPointerPosition(int x, int y)
{
  SDL_WarpMouse(x * scaling, y * scaling);
}

void
SDL_Video::Refresh()
{
  SDL_BlitSurface(buffer, 0, disp, 0);
  SDL_Flip(disp);
}

void
SDL_Video::SaveScreenShot(const std::string& filename)
{
  SDL_SaveBMP(buffer, filename.c_str());
}
