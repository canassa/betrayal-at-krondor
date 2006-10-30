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

#ifndef PARTY_RESOURCE_H
#define PARTY_RESOURCE_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "ResourceData.h"

static const unsigned int PARTY_LOCKLEAR = 0;
static const unsigned int PARTY_GORATH   = 1;
static const unsigned int PARTY_OWYN     = 2;
static const unsigned int PARTY_PUG      = 3;
static const unsigned int PARTY_JAMES    = 4;
static const unsigned int PARTY_PATRUS   = 5;
static const unsigned int PARTY_SIZE     = 6;

typedef struct _PartyData {
  std::string name;
} PartyData;

class PartyResource
: public ResourceData {
  private:
    std::vector<PartyData *> data;
  public:
    PartyResource();
    virtual ~PartyResource();
    unsigned int GetSize() const;
    PartyData* GetData(const unsigned int n);
    void Clear();
    void Load(FileBuffer *buffer);
    void Save(FileBuffer *buffer);
};

#endif

