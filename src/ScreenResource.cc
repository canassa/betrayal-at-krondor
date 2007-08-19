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
#include "ScreenResource.h"

ScreenResource::ScreenResource()
        : image(0)
{}

ScreenResource::~ScreenResource()
{
    Clear();
}

Image *
ScreenResource::GetImage()
{
    return image;
}

void
ScreenResource::Clear()
{
    if (image)
    {
        delete image;
        image = 0;
    }
}

void
ScreenResource::Load(FileBuffer *buffer)
{
    try
    {
        Clear();
        if (buffer->GetUint16LE() != 0x27b6)
        {
            buffer->Rewind();
        }
        if (buffer->GetUint8() != 0x02)
        {
            throw DataCorruption(__FILE__, __LINE__);
        }
        FileBuffer *decompressed = new FileBuffer(buffer->GetUint32LE());
        buffer->DecompressLZW(decompressed);
        image = new Image(SCREEN_WIDTH, SCREEN_HEIGHT);
        image->Load(decompressed);
        delete decompressed;
    }
    catch (Exception &e)
    {
        e.Print("ScreenResource::Load");
        throw;
    }
}

void
ScreenResource::Save(FileBuffer *buffer)
{
    try
    {
        // TODO
        buffer = buffer;
    }
    catch (Exception &e)
    {
        e.Print("ScreenResource::Save");
        throw;
    }
}
