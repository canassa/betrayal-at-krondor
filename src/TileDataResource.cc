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
#include "TileDataResource.h"

TileDataResource::TileDataResource()
{}

TileDataResource::~TileDataResource()
{
    Clear();
}

void
TileDataResource::Clear()
{}

void
TileDataResource::Load(FileBuffer *buffer)
{
    try
    {
        Clear();
        while (!buffer->AtEnd())
        {
            buffer->Skip(4);
        }
    }
    catch (Exception &e)
    {
        e.Print("TileDataResource::Load");
        throw;
    }
}

void
TileDataResource::Save(FileBuffer *buffer)
{
    try
    {
        // TODO
        buffer = buffer;
    }
    catch (Exception &e)
    {
        e.Print("TileDataResource::Load");
        throw;
    }
}
