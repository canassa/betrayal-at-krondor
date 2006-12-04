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

#ifndef ZONE_TABLE_RESOURCE_H
#define ZONE_TABLE_RESOURCE_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "TaggedResource.h"

typedef struct _AppInfo {
  unsigned int size;
  uint8_t *data;
} AppInfo;

typedef struct _GidInfo {
  unsigned int xsize;
  unsigned int ysize;
  bool more;
  unsigned int flags;
} GidInfo;

typedef struct _DatInfo {
  unsigned int type;
  bool more;
} DatInfo;

class ZoneTableResource
: public TaggedResource {
  private:
    std::vector<std::string> mapItems;
    std::vector<AppInfo> appItems;
    std::vector<DatInfo> datItems;
    std::vector<GidInfo> gidItems;
  public:
    ZoneTableResource();
    virtual ~ZoneTableResource();
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
