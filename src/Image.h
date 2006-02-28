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

#ifndef IMAGE_H
#define IMAGE_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "FileBuffer.h"
#include "Video.h"

class Image {
  private:
    int width;
    int height;
    uint8_t *pixel;
  public:
    Image(const int w, const int h);
    virtual ~Image();
    int GetWidth() const;
    int GetHeight() const;
    unsigned int GetSize() const;
    uint8_t GetPixel(const int x, const int y) const;
    uint8_t * GetPixels() const;
    void SetPixel(const int x, const int y, const uint8_t color);
    void SetPixels(uint8_t *data, unsigned int size = 0);
    void Fill(const uint8_t color);
    void Load(FileBuffer *buffer, const unsigned int flags);
    void Read(Video *video, const int x, const int y);
    void Draw(Video *video, const int x, const int y);
    void Draw(Video *video, const int x, const int y, const int xoff, const int yoff, const int w, const int h);
    void Draw(Video *video, const int x, const int y, const uint8_t transparent);
};

#endif

