/*
 * This file is part of xBaK.
 *
 * xBaK is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * xBaK is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with xBaK.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Copyright (C) Guido de Jong <guidoj@users.sf.net>
 */

#ifndef BOOK_RESOURCE_H
#define BOOK_RESOURCE_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <vector>

#include "ResourceData.h"

static const unsigned DECO_HORIZONTAL_FLIP = 0x01;
static const unsigned DECO_VERTICAL_FLIP   = 0x02;

class ImageInfo
{
public:
    int xpos;
    int ypos;
    unsigned int id;
    unsigned int flag;
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
    unsigned int number;
    unsigned int id;
    unsigned int prevId;
    unsigned int nextId;
    unsigned int flag;
    bool showNumber;
    std::vector<ImageInfo> decorations;
    std::vector<ImageInfo> firstLetters;
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
