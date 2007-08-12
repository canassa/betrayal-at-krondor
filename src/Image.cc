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
#include "Image.h"
#include "MediaToolkit.h"

static const unsigned int FLAG_XYSWAPPED  = 0x20;
static const unsigned int FLAG_UNKNOWN    = 0x40;
static const unsigned int FLAG_COMPRESSED = 0x80;

Image::Image(const int w, const int h)
: width(w)
, height(h)
, flags(0)
, pixel(0)
{
  if ((width > 0) && (height > 0)) {
    pixel = new uint8_t[width * height];
    memset(pixel, 0, width * height);
  } else {
    width = 0;
    height = 0;
  }
}

Image::Image(const int w, const int h, const unsigned int f)
: width(w)
, height(h)
, flags(f)
, pixel(0)
{
  if ((width > 0) && (height > 0)) {
    pixel = new uint8_t[width * height];
    memset(pixel, 0, width * height);
  } else {
    width = 0;
    height = 0;
  }
}

Image::Image(const int w, const int h, const uint8_t *p)
: width(w)
, height(h)
, flags(0)
, pixel(0)
{
  if ((width > 0) && (height > 0)) {
    pixel = new uint8_t[width * height];
    memcpy(pixel, p, width * height);
  } else {
    width = 0;
    height = 0;
  }
}

Image::Image(Image *img)
: width(img->width)
, height(img->height)
, flags(0)
, pixel(0)
{
  if ((width > 0) && (height > 0)) {
    pixel = new uint8_t[width * height];
    memcpy(pixel, img->pixel, width * height);
  } else {
    width = 0;
    height = 0;
  }
}

Image::Image(const int w, const int h, Image *img)
: width(w)
, height(h)
, flags(0)
, pixel(0)
{
  if ((width > 0) && (height > 0)) {
    pixel = new uint8_t[width * height];
    uint8_t *p = pixel;
    float fx = (float)img->width / (float)width;
    float fy = (float)img->height / (float)height;
    for (int y = 0; y < height; y++) {
      uint8_t *prow = img->pixel + (int)(y * fy) * img->width;
      for (int x = 0; x < width; x++) {
        *p++ = *(prow + (int)(x * fx));
      }
    }
  } else {
    width = 0;
    height = 0;
  }
}

Image::~Image()
{
  if (pixel) {
    delete [] pixel;
  }
}

int
Image::GetWidth() const
{
  return width;
}

int
Image::GetHeight() const
{
  return height;
}

unsigned int
Image::GetSize() const
{
  return (unsigned int)width * height;
}

unsigned int
Image::GetFlags() const
{
  return flags;
}

void
Image::SetFlags(const unsigned int f)
{
  flags = f;
}

uint8_t
Image::GetPixel(const int x, const int y) const
{
  if ((pixel) && (x >= 0) && (x < width) && (y >= 0) && (y < height)) {
    return pixel[x + width * y];
  }
  return 0;
}

uint8_t *
Image::GetPixels() const
{
  return pixel;
}

void
Image::SetPixel(const int x, const int y, const uint8_t color)
{
  if ((pixel) && (x >= 0) && (x < width) && (y >= 0) && (y < height)) {
    pixel[x + width * y] = color;
  }
}

void
Image::SetPixels(uint8_t *data, unsigned int size)
{
  if ((pixel) && (data)) {
    if (size == 0) {
      size = (unsigned int)width * height;
    }
    memcpy(pixel, data, size);
  }
}

void
Image::Fill(const uint8_t color)
{
  if (pixel) {
    memset(pixel, color, width * height);
  }
}

void
Image::HorizontalFlip()
{
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width / 2; x++) {
      uint8_t h = pixel[x + width * y];
      pixel[x + width * y] = pixel[width - x - 1 + width * y];
      pixel[width - x - 1 + width * y] = h;
    }
  }
}

void
Image::VerticalFlip()
{
  uint8_t *row = new uint8_t[width];
  for (int y = 0; y < height / 2; y++) {
    memcpy(row, pixel + width * y, width);
    memcpy(pixel + width * y, pixel + width * (height - y - 1), width);
    memcpy(pixel + width * (height - y - 1), row, width);
  }
  delete[] row;
}

void
Image::Load(FileBuffer *buffer)
{
  try {
    if (pixel) {
      FileBuffer *imgbuf;
      if (flags & FLAG_COMPRESSED) {
        imgbuf = new FileBuffer(width * height);
        buffer->DecompressRLE(imgbuf);
      } else {
        imgbuf = buffer;
      }
      if (flags & FLAG_XYSWAPPED) {
        for (int x = 0; x < width; x++) {
          for (int y = 0; y < height; y++) {
            SetPixel(x, y, imgbuf->GetUint8());
          }
        }
      } else {
        imgbuf->GetData(pixel, width * height);
      }
      if (flags & FLAG_COMPRESSED) {
        delete imgbuf;
      }
    }
  } catch (Exception &e) {
    e.Print("Image::Load");
  }
}

void
Image::Save(FileBuffer *buffer)
{
  try {
    if (pixel) {
      FileBuffer *imgbuf = new FileBuffer(width * height);
      if (flags & FLAG_XYSWAPPED) {
        for (int x = 0; x < width; x++) {
          for (int y = 0; y < height; y++) {
            SetPixel(x, y, imgbuf->GetUint8());
          }
        }
      } else {
        imgbuf->GetData(pixel, width * height);
      }
      if (flags & FLAG_COMPRESSED) {
        FileBuffer *compressed = new FileBuffer(width * height);
        unsigned int size = compressed->CompressRLE(imgbuf);
        buffer->Copy(compressed, size);
        delete compressed;
      } else {
        buffer->Copy(imgbuf, width * height);
      }
      delete imgbuf;
    }
  } catch (Exception &e) {
    e.Print("Image::Save");
  }
}

void
Image::Read(const int x, const int y)
{
  MediaToolkit::GetInstance()->GetVideo()->ReadImage(x, y, width, height, pixel);
}

void
Image::Draw(const int x, const int y)
{
  MediaToolkit::GetInstance()->GetVideo()->DrawImage(x, y, width, height, pixel);
}

void
Image::Draw(const int x, const int y, const uint8_t transparent)
{
  MediaToolkit::GetInstance()->GetVideo()->DrawImage(x, y, width, height, pixel, transparent);
}

void
Image::Draw(const int x, const int y, const int xoff, const int yoff, const int w, const int h)
{
  MediaToolkit::GetInstance()->GetVideo()->DrawImage(x, y, width, height, xoff, yoff, w, h, pixel);
}

void
Image::Draw(const int x, const int y, const int xoff, const int yoff, const int w, const int h, const uint8_t transparent)
{
  MediaToolkit::GetInstance()->GetVideo()->DrawImage(x, y, width, height, xoff, yoff, w, h, pixel, transparent);
}
