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
#include "ResourceTag.h"

ResourceTag::ResourceTag()
{}

ResourceTag::~ResourceTag()
{
    tagMap.clear();
}

void
ResourceTag::Load(FileBuffer *buffer)
{
    try
    {
        unsigned int n = buffer->GetUint16LE();
        for (unsigned int i = 0; i < n; i++)
        {
            unsigned int id = buffer->GetUint16LE();
            std::string name = buffer->GetString();
            tagMap.insert(std::pair<const unsigned int, std::string>(id, name));
        }
    }
    catch (Exception &e)
    {
        e.Print("ResourceTag::Load");
    }
}

bool
ResourceTag::Find(const unsigned int id, std::string &name)
{
    try
    {
        name = tagMap[id];
    }
    catch (...)
    {
        return false;
    }
    return true;
}

