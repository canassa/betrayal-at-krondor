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

#ifndef TILE_WORLD_RESOURCE_H
#define TILE_WORLD_RESOURCE_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "ResourceData.h"

static const unsigned int TILE_SIZE   = 64000;
static const unsigned int TILE_SIZE_2 = TILE_SIZE / 2;

static const unsigned int OBJECT_CENTER = 0;

struct TileWorldItem
{
    unsigned int type;
    unsigned int flags;
    unsigned int xloc;
    unsigned int yloc;
};

class TileWorldResource
            : public ResourceData
{
    private:
        unsigned int xCenter;
        unsigned int yCenter;
        std::vector<TileWorldItem> items;
    public:
        TileWorldResource();
        virtual ~TileWorldResource();
        unsigned int GetMinX() const;
        unsigned int GetMaxX() const;
        unsigned int GetMinY() const;
        unsigned int GetMaxY() const;
        unsigned int GetSize() const;
        TileWorldItem& GetItem ( unsigned int i );
        void Clear();
        void Load ( FileBuffer *buffer );
        unsigned int Save ( FileBuffer *buffer );
};

#endif

