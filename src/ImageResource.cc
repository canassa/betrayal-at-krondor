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
#include "ImageResource.h"

ImageResource::ImageResource()
        : compression(COMPRESSION_LZW)
        , numImages(0)
{}

ImageResource::~ImageResource()
{
    Clear();
}

unsigned int
ImageResource::GetCompression() const
{
    return compression;
}

void
ImageResource::SetCompression(const unsigned int c)
{
    compression = c;
}

unsigned int
ImageResource::GetNumImages() const
{
    return numImages;
}

Image *
ImageResource::GetImage(unsigned int n) const
{
    return images[n];
}

void
ImageResource::Clear()
{
    for (std::vector<Image*>::iterator it = images.begin(); it != images.end(); ++it)
    {
        delete (*it);
    }
    images.clear();
}

void
ImageResource::Load(FileBuffer *buffer)
{
    try
    {
        Clear();
        if (buffer->GetUint16LE() != 0x1066 )
        {
            throw DataCorruption(__FILE__, __LINE__);
        }
        compression = (unsigned int)buffer->GetUint16LE();
        numImages = (unsigned int)buffer->GetUint16LE();
        unsigned int *imageSize = new unsigned int[numImages];
        buffer->Skip(2);
        unsigned int size = buffer->GetUint32LE();
        for (unsigned int i = 0; i < numImages; i++)
        {
            imageSize[i] = (unsigned int)buffer->GetUint16LE();
            unsigned int flags = (unsigned int)buffer->GetUint16LE();
            unsigned int width = (unsigned int)buffer->GetUint16LE();
            unsigned int height = (unsigned int)buffer->GetUint16LE();
            Image *img = new Image(width, height, flags);
            images.push_back(img);
        }
        FileBuffer *decompressed = new FileBuffer(size);
        buffer->Decompress(decompressed, compression);
        for (unsigned int i = 0; i < numImages; i++)
        {
            FileBuffer *imageBuffer = new FileBuffer(imageSize[i]);
            imageBuffer->Fill(decompressed);
            (images[i])->Load(imageBuffer);
            delete imageBuffer;
        }
        delete decompressed;
        delete[] imageSize;
    }
    catch (Exception &e)
    {
        e.Print("ImageResource::Load");
        throw;
    }
}

void
ImageResource::Save(FileBuffer *buffer)
{
    try
    {
        buffer->PutUint16LE(0x1066);
        buffer->PutUint16LE(compression);
        buffer->PutUint16LE(numImages);
        buffer->PutUint16LE(0);
        unsigned int size = 0;
        for (unsigned int i = 0; i < numImages; i++)
        {
            size += (images[i])->GetSize();
        }
        buffer->PutUint32LE(size);
        for (unsigned int i = 0; i < numImages; i++)
        {
            Image* img = images[i];
            buffer->PutUint16LE(img->GetSize());
            buffer->PutUint16LE(img->GetFlags());
            buffer->PutUint16LE(img->GetWidth());
            buffer->PutUint16LE(img->GetHeight());
        }
        FileBuffer *decompressed = new FileBuffer(size);
        for (unsigned int i = 0; i < numImages; i++)
        {
            (images[i])->Save(decompressed);
        }
        decompressed->Rewind();
        FileBuffer *compressed = new FileBuffer(size);
        size = decompressed->Compress(compressed, compression);
        buffer->CopyFrom(compressed, size);
        delete compressed;
        delete decompressed;
    }
    catch (Exception &e)
    {
        e.Print("ImageResource::Save");
        throw;
    }
}
