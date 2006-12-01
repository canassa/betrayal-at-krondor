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
#include "ObjectResource.h"

ObjectResource::ObjectResource()
: data()
{
}

ObjectResource::~ObjectResource()
{
  Clear();
}

unsigned int
ObjectResource::GetSize() const {
  return data.size();
}

ObjectInfo *
ObjectResource::GetData(unsigned int n) const {
  return data[n];
}

void
ObjectResource::Clear()
{
  for (unsigned int i = 0; i < data.size(); i++){
    delete data[i];
  }
  data.clear();
}

void
ObjectResource::Load(FileBuffer *buffer)
{
  try {
    Clear();
    while (buffer->GetBytesLeft() > 80) {
      ObjectInfo *obj = new ObjectInfo;
      obj->name = buffer->GetString(32);
      buffer->Skip(8);
      obj->strengthSwing = buffer->GetSint16LE();
      obj->strengthThrust = buffer->GetSint16LE();
      obj->accuracySwing = buffer->GetSint16LE();
      obj->accuracyThrust = buffer->GetSint16LE();
      buffer->Skip(32);
      data.push_back(obj);
    }
  } catch (Exception &e) {
    e.Print("ObjectResource::Load");
    throw;
  }
}

void
ObjectResource::Save(FileBuffer *buffer)
{
  try {
    // TODO
    buffer = buffer;
  } catch (Exception &e) {
    e.Print("ObjectResource::Save");
    throw;
  }
}
