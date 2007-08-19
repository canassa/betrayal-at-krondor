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
#include "BookResource.h"

BookResource::BookResource()
        : paragraphs()
{}

BookResource::~BookResource()
{
    Clear();
}

unsigned int
BookResource::GetNumParagraphs() const
{
    return paragraphs.size();
}

std::string&
BookResource::GetParagraph(const unsigned int i)
{
    return paragraphs[i];
}

void
BookResource::Clear()
{
    paragraphs.clear();
}

void
BookResource::Load(FileBuffer *buffer)
{
    try
    {
        Clear();
        buffer->Skip(4);
        for (unsigned int i = 0; i < buffer->GetUint16LE(); i++)
        {
            buffer->Skip(4);
        }
        for (unsigned int i = 0; i < 40; i++)
        {
            buffer->Skip(2);
        }
        while (!buffer->AtEnd())
        {
            unsigned int code = buffer->GetUint8();
            std::string s = "";
            while ((code & 0xf0) != 0xf0)
            {
                s += (char)code;
                code = buffer->GetUint8();
            }
            if (s.length())
            {
                paragraphs.push_back(s);
            }
            switch (code)
            {
            case 0xf0:
                do
                {
                    buffer->Skip(2);
                    if (!buffer->AtEnd())
                    {
                        code = buffer->GetUint8();
                        buffer->Skip(-1);
                    }
                }
                while ((code != 0xf0) && (!buffer->AtEnd()));
                break;
            case 0xf1:
                for (unsigned int i = 0; i < 8; i++)
                {
                    buffer->Skip(2);
                }
                break;
            case 0xf4:
                for (unsigned int i = 0; i < 5; i++)
                {
                    buffer->Skip(2);
                }
                break;
            default:
                break;
            }
        }
    }
    catch (Exception &e)
    {
        e.Print("BookResource::Load");
        throw;
    }
}

void
BookResource::Save(FileBuffer *buffer)
{
    try
    {
        // TODO
        buffer = buffer;
    }
    catch (Exception &e)
    {
        e.Print("BookResource::Save");
        throw;
    }
}
