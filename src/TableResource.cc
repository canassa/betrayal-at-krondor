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
#include "TableResource.h"

DatInfo::DatInfo()
{}

DatInfo::~DatInfo()
{}

TableResource::TableResource()
        : TaggedResource()
        , mapItems()
{}

TableResource::~TableResource()
{
    Clear();
}

unsigned int
TableResource::GetMapSize() const
{
    return mapItems.size();
}

std::string&
TableResource::GetMapItem(const unsigned int i)
{
    return mapItems[i];
}

unsigned int
TableResource::GetDatSize() const
{
    return datItems.size();
}

DatInfo*
TableResource::GetDatItem(const unsigned int i)
{
    return datItems[i];
}

unsigned int
TableResource::GetGidSize() const
{
    return gidItems.size();
}

GidInfo&
TableResource::GetGidItem(const unsigned int i)
{
    return gidItems[i];
}

void
TableResource::Clear()
{
    mapItems.clear();
    for (std::vector<DatInfo *>::iterator it = datItems.begin(); it != datItems.end(); ++it)
    {
        delete (*it);
    }
    datItems.clear();
    gidItems.clear();
}

void
TableResource::Load(FileBuffer *buffer)
{
    try
    {
        Clear();
        Split(buffer);
        FileBuffer *mapbuf;
        FileBuffer *appbuf;
        FileBuffer *gidbuf;
        FileBuffer *datbuf;
        if (!Find(TAG_MAP, mapbuf) ||
                !Find(TAG_APP, appbuf) ||
                !Find(TAG_GID, gidbuf) ||
                !Find(TAG_DAT, datbuf))
        {
            ClearTags();
            throw DataCorruption(__FILE__, __LINE__);
        }
        mapbuf->Skip(2);
        unsigned int numMapItems = mapbuf->GetUint16LE();
        unsigned int *mapOffset = new unsigned int [numMapItems];
        for (unsigned int i = 0; i < numMapItems; i++)
        {
            mapOffset[i] = mapbuf->GetUint16LE();
        }
        mapbuf->Skip(2);
        unsigned int mapDataStart = mapbuf->GetBytesDone();
        for (unsigned int i = 0; i < numMapItems; i++)
        {
            mapbuf->Seek(mapDataStart + mapOffset[i]);
            std::string item = mapbuf->GetString();
            mapItems.push_back(item);
        }
        delete[] mapOffset;

        unsigned int numAppItems = appbuf->GetUint16LE();
        unsigned int appDataSize = appbuf->GetUint16LE();
        for (unsigned int i = 0; i< numAppItems; i++)
        {
            appbuf->Skip(appDataSize);
        }

        unsigned int *gidOffset = new unsigned int [numMapItems];
        for (unsigned int i = 0; i < numMapItems; i++)
        {
            gidOffset[i] = (gidbuf->GetUint16LE() & 0x000f) + (gidbuf->GetUint16LE() << 4);
        }
        for (unsigned int i = 0; i < numMapItems; i++)
        {
            gidbuf->Seek(gidOffset[i]);
            GidInfo item;
            item.xoffset = gidbuf->GetUint16LE();
            item.yoffset = gidbuf->GetUint16LE();
            bool more = gidbuf->GetUint16LE() > 0;
            item.flags = gidbuf->GetUint16LE();
            if (more)
            {
                // TODO
            }
            gidItems.push_back(item);
        }
        delete[] gidOffset;

        unsigned int *datOffset = new unsigned int [numMapItems];
        for (unsigned int i = 0; i < numMapItems; i++)
        {
            datOffset[i] = (datbuf->GetUint16LE() & 0x000f) + (datbuf->GetUint16LE() << 4);
        }
        for (unsigned int i = 0; i < numMapItems; i++)
        {
            datbuf->Seek(datOffset[i]);
            DatInfo *item = new DatInfo();
            item->objectClass = datbuf->GetUint8();
            item->objectType = datbuf->GetUint8();
            item->terrainClass = datbuf->GetUint8();
            item->terrainType = datbuf->GetUint8();
            datbuf->Skip(4);
            bool more = datbuf->GetUint16LE() > 0;
            datbuf->Skip(4);
            if (more)
            {
                switch (item->objectType)
                {
                case OT_TREE:
                case OT_TOMBSTONE:
                case OT_SIGN:
                case OT_DEADBODY2:
                case OT_DIRTPILE:
                case OT_FIRE:
                case OT_FERN:
                case OT_ROCKPILE:
                case OT_BUSH1:
                case OT_BUSH2:
                case OT_BUSH3:
                case OT_SLAB:
                case OT_STUMP:
                case OT_WELL:
                case OT_ENGINE:
                case OT_SCARECROW:
                case OT_TRAP:
                case OT_COLUMN:
                case OT_BAG:
                case OT_LADDER:
                {
                    datbuf->Skip(22);
                    item->sprite = datbuf->GetUint16LE();
                    datbuf->Skip(4);
                }
                break;
                case OT_TERRAIN:
                case OT_EXTERIOR:
                case OT_INTERIOR:
                case OT_BRIDGE:
                case OT_LANDSCAPE1:
                case OT_CHEST:
                case OT_DEADBODY1:
                case OT_FENCE:
                case OT_GATE:
                case OT_BUILDING:
                case OT_ROOM:
                case OT_PIT:
                case OT_CORN:
                case OT_ENTRANCE:
                case OT_GROVE:
                case OT_DOOR:
                case OT_CRYST:
                case OT_CATAPULT:
                case OT_LANDSCAPE2:
                case OT_MOUNTAIN:
                {
                    item->sprite = (unsigned int) -1;
                    item->min.SetX(datbuf->GetSint16LE());
                    item->min.SetY(datbuf->GetSint16LE());
                    item->min.SetZ(datbuf->GetSint16LE());
                    item->max.SetX(datbuf->GetSint16LE());
                    item->max.SetY(datbuf->GetSint16LE());
                    item->max.SetZ(datbuf->GetSint16LE());
                    datbuf->Skip(16);
                    // TODO
                }
                break;
                default:
                    throw DataCorruption(__FILE__, __LINE__);
                    break;
                }
            }
            datItems.push_back(item);
        }
        delete[] datOffset;

        ClearTags();
    }
    catch (Exception &e)
    {
        e.Print("TableResource::Load");
        ClearTags();
        throw;
    }
}

unsigned int
TableResource::Save(FileBuffer *buffer)
{
    try
    {
        // TODO
        buffer = buffer;
        return 0;
    }
    catch (Exception &e)
    {
        e.Print("TableResource::Save");
        throw;
    }
}
