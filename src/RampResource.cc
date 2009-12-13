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
 * Copyright (C) 2009 Guido de Jong <guidoj@users.sf.net>
 */

#include "Exception.h"
#include "RampResource.h"

RampResource::RampResource()
: ramp()
{
}

RampResource::~RampResource()
{
    Clear();
}

unsigned int RampResource::GetSize() const
{
    return ramp.size();
}

std::vector<unsigned char>& RampResource::GetRamp(unsigned int rmp)
{
    return ramp[rmp];
}

unsigned char RampResource::GetColor(unsigned int rmp, unsigned int n) const
{
    return ramp[rmp][n];
}

void RampResource::Clear()
{
    ramp.clear();
}

void RampResource::Load(FileBuffer *buffer)
{
    try
    {
        Clear();
        while (buffer->GetBytesLeft() > 0)
        {
            std::vector<unsigned char> colors(256);
            for (unsigned int i = 0; i < 256; i++)
            {
                colors[i] = buffer->GetUint8();
            }
            ramp.push_back(colors);
        }
    }
    catch (Exception &e)
    {
        e.Print("RampResource::Load");
        throw;
    }
}

unsigned int RampResource::Save(FileBuffer *buffer)
{
    try
    {
        // TODO
        buffer = buffer;
        return 0;
    }
    catch (Exception &e)
    {
        e.Print("RampResource::Save");
        throw;
    }
}
