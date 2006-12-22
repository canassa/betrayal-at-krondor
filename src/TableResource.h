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
 * Copyright (C) 2005-2006  Guido de Jong <guidoj@users.sf.net>
 */

#ifndef TABLE_RESOURCE_H
#define TABLE_RESOURCE_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "TaggedResource.h"

/* Object Class */
static const unsigned int OC_TERRAIN      = 0x00;
static const unsigned int OC_LARGE_OBJECT = 0x40;
static const unsigned int OC_SMALL_OBJECT = 0x60;

/* Object Type */
static const unsigned int OT_TERRAIN    =  0;
static const unsigned int OT_EXTERIOR   =  1;
static const unsigned int OT_BRIDGE     =  2;
static const unsigned int OT_INTERIOR   =  3;
static const unsigned int OT_LANDSCAPE1 =  4;
static const unsigned int OT_TREE       =  5;
static const unsigned int OT_CHEST      =  6;
static const unsigned int OT_DEADBODY1  =  7;
static const unsigned int OT_FENCE      =  8;
static const unsigned int OT_GATE       =  9;
static const unsigned int OT_BUILDING   = 10;
static const unsigned int OT_TOMBSTONE  = 12;
static const unsigned int OT_SIGN       = 13;
static const unsigned int OT_ROOM       = 14;
static const unsigned int OT_PIT        = 15;
static const unsigned int OT_DEADBODY2  = 16;
static const unsigned int OT_DIRTPILE   = 17;
static const unsigned int OT_CORN       = 18;
static const unsigned int OT_FIRE       = 19;
static const unsigned int OT_ENTRANCE   = 20;
static const unsigned int OT_GROVE      = 21;
static const unsigned int OT_FERN       = 22;
static const unsigned int OT_DOOR       = 23;
static const unsigned int OT_CRYST      = 24;
static const unsigned int OT_ROCKPILE   = 25;
static const unsigned int OT_BUSH1      = 26;
static const unsigned int OT_BUSH2      = 27;
static const unsigned int OT_BUSH3      = 28;
static const unsigned int OT_SLAB       = 29;
static const unsigned int OT_STUMP      = 30;
static const unsigned int OT_WELL       = 31;
static const unsigned int OT_ENGINE     = 33;
static const unsigned int OT_SCARECROW  = 34;
static const unsigned int OT_TRAP       = 35;
static const unsigned int OT_CATAPULT   = 36;
static const unsigned int OT_COLUMN     = 37;
static const unsigned int OT_LANDSCAPE2 = 38;
static const unsigned int OT_MOUNTAIN   = 39;
static const unsigned int OT_BAG        = 41;
static const unsigned int OT_LADDER     = 42;

/* Terrain Class */
static const unsigned int TC_NULL      = 0;
static const unsigned int TC_MAP       = 1;
static const unsigned int TC_LANDSCAPE = 1;

/* Terrain Type */
static const unsigned int TT_NULL      = 0;
static const unsigned int TT_INTERIOR  = 6;
static const unsigned int TT_EXTERIOR  = 7;
static const unsigned int TT_LANDSCAPE = 8;

typedef struct _AppInfo {
  unsigned int size;
  uint8_t data[8];
} AppInfo;

typedef struct _GidInfo {
  unsigned int xsize;
  unsigned int ysize;
  bool more;
  unsigned int flags;
} GidInfo;

typedef struct _DatInfo {
  unsigned int objectClass;
  unsigned int objectType;
  unsigned int terrainClass;
  unsigned int terrainType;
  bool more;
  unsigned int sprite;
} DatInfo;

class TableResource
: public TaggedResource {
  private:
    std::vector<std::string> mapItems;
    std::vector<AppInfo> appItems;
    std::vector<DatInfo> datItems;
    std::vector<GidInfo> gidItems;
  public:
    TableResource();
    virtual ~TableResource();
    unsigned int GetMapSize() const;
    std::string& GetMapItem(const unsigned int i);
    unsigned int GetAppSize() const;
    AppInfo& GetAppItem(const unsigned int i);
    unsigned int GetDatSize() const;
    DatInfo& GetDatItem(const unsigned int i);
    unsigned int GetGidSize() const;
    GidInfo& GetGidItem(const unsigned int i);
    void Clear();
    void Load(FileBuffer *buffer);
    void Save(FileBuffer *buffer);
};

#endif
