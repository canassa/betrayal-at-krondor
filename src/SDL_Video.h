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

#ifndef SDL_VIDEO_H
#define SDL_VIDEO_H

#ifdef HAVE_CONFIG
#include "config.h"
#endif

#include "SDL.h"

#include "Video.h"

typedef struct _PolygonEdge {
  int x0;
  int y0;
  int x1;
  int y1;
  float dxdy;
} PolygonEdge;

class SDL_Video
: public Video {
  private:
    const SDL_VideoInfo *info;
    SDL_Surface* disp;
    SDL_Surface* stretched;
    SDL_Surface* buffer;
    bool CreateEdge(PolygonEdge &edge, const int x1, const int y1, const int x2, const int y2);
    void SortEdges(PolygonEdge* &edges, const unsigned int n);
  public:
    SDL_Video();
    ~SDL_Video();
    void CreateScreen(const int w, const int h);
    unsigned int GetPixel(const int x, const int y);
    void PutPixel(const int x, const int y, const unsigned int c);
    void DrawHLine(const int x, const int y, const int w, const unsigned int c);
    void DrawVLine(const int x, const int y, const int h, const unsigned int c);
    void DrawLine(int x1, int y1, int x2, int y2, const unsigned int c);
    void DrawPolygon(const int *x, const int *y, const unsigned int n, const unsigned int c);
    void FillPolygon(const int *x, const int *y, const unsigned int n, const unsigned int c);
    void DrawRect(const int x, const int y, const int w, const int h, const unsigned int c);
    void FillRect(const int x, const int y, const int w, const int h, const unsigned int c);
    void ReadImage(const int x, const int y, const int w, const int h, uint8_t *p);
    void DrawImage(const int x, const int y, const int w, const int h, uint8_t *p);
    void DrawImage(const int x, const int y, const int w, const int h, uint8_t *p, const uint8_t transparant);
    void DrawImage(const int x, const int y, const int w, const int h,
                   const int xx, const int yy, const int ww, const int hh, uint8_t *p);
    void DrawImage(const int x, const int y, const int w, const int h,
                   const int xx, const int yy, const int ww, const int hh,
                   uint8_t *p, const uint8_t transparant);
    void DrawGlyph(const int x, const int y, const int w, const int h, const uint8_t c, uint16_t*p);
    void DrawGlyphItalic(const int x, const int y, const int w, const int h, const uint8_t c, uint16_t*p);
    void GetPalette(Color *color, const unsigned int first, const unsigned int n);
    void SetPalette(Color *color, const unsigned int first, const unsigned int n);
    void SetPointerPosition(int x, int y);
    void Clear();
    void Clear(int x, int y, int w, int h);
    void Refresh();
    void GrabInput(const bool toggle);
    void SaveScreenShot(const std::string& filename);
};

#endif
