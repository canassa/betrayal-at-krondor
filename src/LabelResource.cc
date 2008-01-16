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
 * Copyright (C) 2005-2008 Guido de Jong <guidoj@users.sf.net>
 */

#include "Exception.h"
#include "LabelResource.h"

LabelResource::LabelResource()
        : data()
{}

LabelResource::~LabelResource()
{
    Clear();
}

unsigned int
LabelResource::GetSize() const
{
    return data.size();
}

LabelData&
LabelResource::GetLabelData(const unsigned int n)
{
    return data[n];
}

void
LabelResource::Clear()
{
    data.clear();
}

void
LabelResource::Load(FileBuffer *buffer)
{
    try
    {
        Clear();
        unsigned int numRecords = buffer->GetUint16LE();
        int *offset = new int[numRecords];
        for (unsigned int i = 0; i < numRecords; i++)
        {
            LabelData lblData;
            offset[i] = buffer->GetSint16LE();
            lblData.xpos = buffer->GetSint16LE();
            lblData.ypos = buffer->GetSint16LE();
            lblData.type = buffer->GetSint16LE();
            lblData.color = buffer->GetSint8();
            lblData.shadow = buffer->GetSint8();
            data.push_back(lblData);
        }
        buffer->Skip(2);
        unsigned int start = buffer->GetBytesDone();
        for (unsigned int i = 0; i < numRecords; i++)
        {
            if (offset[i] >= 0)
            {
                buffer->Seek(start + offset[i]);
                data[i].label = buffer->GetString();
            }
        }
        delete[] offset;
    }
    catch (Exception &e)
    {
        e.Print("LabelResource::Load");
        throw;
    }
}

unsigned int
LabelResource::Save(FileBuffer *buffer)
{
    try
    {
        // TODO
        buffer = buffer;
        return 0;
    }
    catch (Exception &e)
    {
        e.Print("LabelResource::Save");
        throw;
    }
}
