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

#ifndef VIDEO_H
#define VIDEO_H

#ifdef HAVE_CONFIG
#include "config.h"
#endif

#ifdef HAVE_STDINT_H
#include <stdint.h>
#else
#include "alt_stdint.h"
#endif

#include <string>

static const unsigned int VIDEO_WIDTH  = 320;
static const unsigned int VIDEO_HEIGHT = 200;
static const unsigned int VIDEO_COLORS = 256;
static const unsigned int VIDEO_BPP    = 8;

#ifdef PACKAGE_STRING
static const char WINDOW_TITLE[] = PACKAGE_STRING;
#else
static const char WINDOW_TITLE[] = "xbak";
#endif

struct Color
{
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
};

class Video
{
protected:
    unsigned int scaling;
public:
    Video();
    virtual ~Video();
    unsigned int GetScaling() const;
    void SetScaling ( const unsigned int n );
    virtual void CreateScreen ( const int w, const int h ) = 0;
    virtual void Clear() = 0;
    virtual void Clear ( int x, int y, int w, int h ) = 0;
    virtual unsigned int GetPixel ( const int x, const int y ) = 0;
    virtual void PutPixel ( const int x, const int y, const unsigned int c ) = 0;
    virtual void DrawHLine ( const int x, const int y, const int w, const unsigned int c ) = 0;
    virtual void DrawVLine ( const int x, const int y, const int h, const unsigned int c ) = 0;
    virtual void DrawLine ( int x1, int y1, int x2, int y2, const unsigned int c ) = 0;
    virtual void DrawRect ( const int x, const int y, const int w, const int h, const unsigned int c ) = 0;
    virtual void FillRect ( const int x, const int y, const int w, const int h, const unsigned int c ) = 0;
    virtual void DrawPolygon ( const int *x, const int *y, const unsigned int n, const unsigned int c ) = 0;
    virtual void FillPolygon ( const int *x, const int *y, const unsigned int n, const unsigned int c ) = 0;
    virtual void DrawCircle ( const int x, const int y, const unsigned int r, const unsigned int c ) = 0;
    virtual void FillCircle ( const int x, const int y, const unsigned int r, const unsigned int c ) = 0;
    virtual void ReadImage ( const int x, const int y, const int w, const int h, uint8_t *p ) = 0;
    virtual void DrawImage ( const int x, const int y, const int w, const int h, uint8_t *p ) = 0;
    virtual void DrawImage ( const int x, const int y, const int w, const int h, uint8_t *p, const uint8_t transparant ) = 0;
    virtual void DrawImage ( const int x, const int y, const int w, const int h,
                             const int xx, const int yy, const int ww, const int hh, uint8_t *p ) = 0;
    virtual void DrawImage ( const int x, const int y, const int w, const int h,
                             const int xx, const int yy, const int ww, const int hh,
                             uint8_t *p, const uint8_t transparant ) = 0;
    virtual void DrawGlyph ( const int x, const int y, const int w, const int h, const uint8_t c, uint16_t *p ) = 0;
    virtual void DrawGlyphItalic ( const int x, const int y, const int w, const int h, const uint8_t c, uint16_t *p ) = 0;
    virtual void GetPalette ( Color *color, const unsigned int first, const unsigned int n ) = 0;
    virtual void SetPalette ( Color *color, const unsigned int first, const unsigned int n ) = 0;
    virtual void Refresh() = 0;
    virtual void GrabInput ( const bool toggle ) = 0;
    virtual void SaveScreenShot ( const std::string& filename ) = 0;
};

#endif

