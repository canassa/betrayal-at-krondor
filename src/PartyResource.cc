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
#include "PartyResource.h"

PartyResource::PartyResource()
: data()
{
}

PartyResource::~PartyResource()
{
  for (unsigned int i = 0; i < data.size(); i++) {
    delete data[i];
  }
  data.clear();
}

PartyData *
PartyResource::GetData(const unsigned int n)
{
  return data[n];
}

void
PartyResource::Load(FileBuffer *buffer)
{
  try {
    unsigned int offset[PARTY_SIZE];
    for (unsigned int i = 0; i < PARTY_SIZE; i++) {
      offset[i] = buffer->GetUint16();
      buffer->Skip(93);
    }
    buffer->Skip(2);
    unsigned int start = buffer->GetBytesDone();
    for (unsigned int i = 0; i < PARTY_SIZE; i++) {
      buffer->Rewind();
      buffer->Skip(start + offset[i]);
      PartyData *pd = new PartyData;
      pd->name = buffer->GetString();
      data.push_back(pd);
    }
  } catch (Exception &e) {
    e.Print("PartyResource::Load");
    throw;
  }
}
