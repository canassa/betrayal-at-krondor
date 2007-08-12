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

#ifndef IMAGE_H
#define IMAGE_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "FileBuffer.h"

class Image {
  private:
    int width;
    int height;
    unsigned int flags;
    uint8_t *pixel;
  public:
    Image(const int w, const int h);
    Image(const int w, const int h, const unsigned int f);
    Image(const int w, const int h, const uint8_t *p);
    Image(Image *img);
    Image(const int w, const int h, Image *img);
    ~Image();
    int GetWidth() const;
    int GetHeight() const;
    unsigned int GetSize() const;
    unsigned int GetFlags() const;
    void SetFlags(const unsigned int f);
    uint8_t GetPixel(const int x, const int y) const;
    uint8_t * GetPixels() const;
    void SetPixel(const int x, const int y, const uint8_t color);
    void SetPixels(uint8_t *data, unsigned int size = 0);
    void HorizontalFlip();
    void VerticalFlip();
    void Fill(const uint8_t color);
    void Load(FileBuffer *buffer);
    void Save(FileBuffer *buffer);
    void Read(const int x, const int y);
    void Draw(const int x, const int y);
    void Draw(const int x, const int y, const uint8_t transparent);
    void Draw(const int x, const int y, const int xoff, const int yoff, const int w, const int h);
    void Draw(const int x, const int y, const int xoff, const int yoff, const int w, const int h, const uint8_t transparent);
};

#endif
