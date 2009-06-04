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
 * Copyright (C) 2005-2009 Guido de Jong <guidoj@users.sf.net>
 */

#include "Exception.h"
#include "BookResource.h"

BookResource::BookResource()
: pages()
{
}

BookResource::~BookResource()
{
    Clear();
}

unsigned int
BookResource::GetNumPages() const
{
    return pages.size();
}

PageData&
BookResource::GetPage(const unsigned int i)
{
    return pages[i];
}

void
BookResource::Clear()
{
    pages.clear();
}

void
BookResource::Load(FileBuffer *buffer)
{
    try
    {
        Clear();
        buffer->Skip(4);
        unsigned int numPages = buffer->GetUint16LE();
        unsigned int *pageOffset = new unsigned int [numPages];
        for (unsigned int i = 0; i < numPages; i++)
        {
            pageOffset[i] = buffer->GetUint32LE();
        }
        for (unsigned int i = 0; i < numPages; i++)
        {
            buffer->Seek(4 + pageOffset[i]);
            PageData pd;
            pd.xpos = buffer->GetSint16LE();
            pd.ypos = buffer->GetSint16LE();
            pd.width = buffer->GetSint16LE();
            pd.height = buffer->GetSint16LE();
            pd.number = buffer->GetSint16LE();
            pd.id = buffer->GetSint16LE();
            pd.prevId = buffer->GetSint16LE();
            buffer->Skip(2);
            pd.nextId = buffer->GetSint16LE();
            pd.flag = buffer->GetUint16LE();
            unsigned int numDecorations = buffer->GetUint16LE();
            unsigned int numFirstLetters = buffer->GetUint16LE();
            pd.showNumber = buffer->GetUint16LE() > 0;
            buffer->Skip(30);
            for (unsigned int j = 0; j < numDecorations; j++)
            {
                Decoration deco;
                deco.xpos = buffer->GetSint16LE();
                deco.ypos = buffer->GetSint16LE();
                deco.id = buffer->GetSint16LE();
                buffer->Skip(2);
                pd.decorations.push_back(deco);
            }
            for (unsigned int j = 0; j < numFirstLetters; j++)
            {
                Decoration deco;
                deco.xpos = buffer->GetSint16LE();
                deco.ypos = buffer->GetSint16LE();
                deco.id = buffer->GetSint16LE();
                buffer->Skip(2);
                pd.decorations.push_back(deco);
            }
            bool endOfPage = false;
            TextBlock tb;
            tb.italic = false;
            while (!endOfPage && !buffer->AtEnd())
            {
                unsigned char c = buffer->GetUint8();
                if ((c & 0xf0) == 0xf0)
                {
                    switch (c)
                    {
                        case 0xf0:
                            endOfPage = true;
                            break;
                        case 0xf1:
                            buffer->Skip(16);
                            break;
                        case 0xf2:
                            break;
                        case 0xf3:
                            break;
                        case 0xf4:
                            buffer->Skip(8);
                            switch (buffer->GetUint16LE())
                            {
                                case 1:
                                    tb.italic = false;
                                    break;
                                case 5:
                                    tb.italic = true;
                                    break;
                                default:
                                    break;
                            }
                            break;
                        default:
                            break;
                    }
                    pd.textBlocks.push_back(tb);
                    tb.italic = false;
                    tb.txt.clear();
                }
                else
                {
                    tb.txt.push_back(c);
                }
            }
            pd.textBlocks.push_back(tb);
            pages.push_back(pd);
        }
        delete[] pageOffset;
    }
    catch (Exception &e)
    {
        e.Print("BookResource::Load");
        throw;
    }
}

unsigned int
BookResource::Save(FileBuffer *buffer)
{
    try
    {
        // TODO
        buffer = buffer;
        return 0;
    }
    catch (Exception &e)
    {
        e.Print("BookResource::Save");
        throw;
    }
}
