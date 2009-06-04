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

#ifndef BOOK_RESOURCE_H
#define BOOK_RESOURCE_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <vector>

#include "ResourceData.h"

class Decoration
{
    public:
        int xpos;
        int ypos;
        int id;
};

class TextBlock
{
    public:
        bool paragraph;
        bool italic;
        std::string txt;
};

class PageData
{
    public:
        int xpos;
        int ypos;
        int width;
        int height;
        int number;
        int id;
        int prevId;
        int nextId;
        unsigned int flag;
        bool showNumber;
        std::vector<Decoration> decorations;
        std::vector<TextBlock> textBlocks;
};

class BookResource: public ResourceData
{
    private:
        std::vector<PageData> pages;
    public:
        BookResource();
        virtual ~BookResource();
        unsigned int GetNumPages() const;
        PageData& GetPage ( const unsigned int i );
        void Clear();
        void Load ( FileBuffer *buffer );
        unsigned int Save ( FileBuffer *buffer );
};

#endif
