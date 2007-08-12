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

#ifndef IMAGE_RESOURCE_H
#define IMAGE_RESOURCE_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Image.h"
#include "ResourceData.h"

class ImageResource
: public ResourceData {
  private:
    unsigned int compression;
    unsigned int numImages;
    std::vector<Image *> images;
    void DecompressLZW(FileBuffer *from, FileBuffer *to);
    void DecompressLZ(FileBuffer *from, FileBuffer *to);
    void DecompressRLE(FileBuffer *from, FileBuffer *to);
  public:
    ImageResource();
    virtual ~ImageResource();
    unsigned int GetCompression() const;
    void SetCompression(const unsigned int c);
    unsigned int GetNumImages() const;
    Image * GetImage(unsigned int n) const;
    void Clear();
    void Load(FileBuffer *buffer);
    void Save(FileBuffer *buffer);
};

#endif

