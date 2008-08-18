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

#ifndef TABLE_RESOURCE_H
#define TABLE_RESOURCE_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Geometry.h"
#include "TaggedResource.h"

/* Entity Flags */
static const unsigned int EF_TERRAIN   = 0x00;
static const unsigned int EF_UNBOUNDED = 0x20;
static const unsigned int EF_2D_OBJECT = 0x40;

/* Entity Type */
static const unsigned int ET_TERRAIN    =  0;
static const unsigned int ET_EXTERIOR   =  1;
static const unsigned int ET_BRIDGE     =  2;
static const unsigned int ET_INTERIOR   =  3;
static const unsigned int ET_HILL       =  4;
static const unsigned int ET_TREE       =  5;
static const unsigned int ET_CHEST      =  6;
static const unsigned int ET_DEADBODY1  =  7;
static const unsigned int ET_FENCE      =  8;
static const unsigned int ET_GATE       =  9;
static const unsigned int ET_BUILDING   = 10;
static const unsigned int ET_TOMBSTONE  = 12;
static const unsigned int ET_SIGN       = 13;
static const unsigned int ET_ROOM       = 14;
static const unsigned int ET_PIT        = 15;
static const unsigned int ET_DEADBODY2  = 16;
static const unsigned int ET_DIRTPILE   = 17;
static const unsigned int ET_CORN       = 18;
static const unsigned int ET_FIRE       = 19;
static const unsigned int ET_ENTRANCE   = 20;
static const unsigned int ET_GROVE      = 21;
static const unsigned int ET_FERN       = 22;
static const unsigned int ET_DOOR       = 23;
static const unsigned int ET_CRYST      = 24;
static const unsigned int ET_ROCKPILE   = 25;
static const unsigned int ET_BUSH1      = 26;
static const unsigned int ET_BUSH2      = 27;
static const unsigned int ET_BUSH3      = 28;
static const unsigned int ET_SLAB       = 29;
static const unsigned int ET_STUMP      = 30;
static const unsigned int ET_WELL       = 31;
static const unsigned int ET_ENGINE     = 33;
static const unsigned int ET_SCARECROW  = 34;
static const unsigned int ET_TRAP       = 35;
static const unsigned int ET_CATAPULT   = 36;
static const unsigned int ET_COLUMN     = 37;
static const unsigned int ET_LANDSCAPE  = 38;
static const unsigned int ET_MOUNTAIN   = 39;
static const unsigned int ET_BAG        = 41;
static const unsigned int ET_LADDER     = 42;

/* Terrain Type */
static const unsigned int TT_NULL      = 0;
static const unsigned int TT_INTERIOR  = 6;
static const unsigned int TT_EXTERIOR  = 7;
static const unsigned int TT_LANDSCAPE = 8;

/* Terrain Class */
static const unsigned int TC_FIELD     = 0;
static const unsigned int TC_LANDSCAPE = 1;
static const unsigned int TC_OTHER     = 2;

class GidInfo
{
    public:
        unsigned int xradius;
        unsigned int yradius;
        unsigned int flags;
        std::vector <Vector2D *> textureCoords;
        std::vector <Vector2D *> otherCoords;
        GidInfo();
        ~GidInfo();
};

class DatInfo
{
    public:
        unsigned int entityFlags;
        unsigned int entityType;
        unsigned int terrainType;
        unsigned int terrainClass;
        unsigned int sprite;
        Vector3D min;
        Vector3D max;
        Vector3D pos;
        std::vector<Vector3D *> vertices;
        DatInfo();
        ~DatInfo();
};

class TableResource
    : public TaggedResource
{
    private:
        std::vector<std::string> mapItems;
        std::vector<DatInfo *> datItems;
        std::vector<GidInfo *> gidItems;
    public:
        TableResource();
        virtual ~TableResource();
        unsigned int GetMapSize() const;
        std::string& GetMapItem ( const unsigned int i );
        unsigned int GetDatSize() const;
        DatInfo* GetDatItem ( const unsigned int i );
        unsigned int GetGidSize() const;
        GidInfo* GetGidItem ( const unsigned int i );
        void Clear();
        void Load ( FileBuffer *buffer );
        unsigned int Save ( FileBuffer *buffer );
};

#endif
