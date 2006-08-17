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

#include "Exception.h"
#include "ZoneTableResource.h"

ZoneTableResource::ZoneTableResource()
: TaggedResource()
, mapItems()
, appItems()
{
}

ZoneTableResource::~ZoneTableResource()
{
  mapItems.clear();
  for (unsigned int i = 0; i < appItems.size(); i++) {
    delete[] appItems[i].data;
  }
  appItems.clear();
}

unsigned int
ZoneTableResource::GetMapSize() const
{
  return mapItems.size();
}

std::string&
ZoneTableResource::GetMapItem(const unsigned int i)
{
  return mapItems[i];
}

unsigned int
ZoneTableResource::GetAppSize() const
{
  return appItems.size();
}

AppData&
ZoneTableResource::GetAppItem(const unsigned int i)
{
  return appItems[i];
}

void
ZoneTableResource::Load(FileBuffer *buffer)
{
  try {
    Split(buffer);
    FileBuffer *mapbuf;
    FileBuffer *appbuf;
    FileBuffer *gidbuf;
    FileBuffer *datbuf;
    if (!Find(TAG_MAP, mapbuf) ||
        !Find(TAG_APP, appbuf) ||
        !Find(TAG_GID, gidbuf) ||
        !Find(TAG_DAT, datbuf)) {
      Clear();
      throw DataCorruption(__FILE__, __LINE__);
    }
    mapbuf->Skip(2);
    unsigned int numMapItems = mapbuf->GetUint16LE() + 1;
    unsigned int *mapOffset = new unsigned int [numMapItems];
    for (unsigned int i = 0; i < numMapItems; i++) {
      mapOffset[i] = mapbuf->GetUint16LE();
    }
    unsigned int mapDataStart = mapbuf->GetBytesDone();
    for (unsigned int i = 0; i < numMapItems; i++) {
      mapbuf->Seek(mapDataStart + mapOffset[i]);
      std::string item = mapbuf->GetString();
      mapItems.push_back(item);
    }
    delete[] mapOffset;
    unsigned int numAppItems = appbuf->GetUint16LE();
    unsigned int appDataSize = appbuf->GetUint16LE();
    for (unsigned int i = 0; i< numAppItems; i++) {
      AppData item;
      item.size = appDataSize;
      item.data = new uint8_t[appDataSize];
      appbuf->GetData(item.data, item.size);
      appItems.push_back(item);
    }
    Clear();
  } catch (Exception &e) {
    e.Print("ZoneTableResource::Load");
  }
}

