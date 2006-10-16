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
#include "RequestResource.h"

RequestResource::RequestResource()
: popup(false)
, xpos(0)
, ypos(0)
, width(0)
, height(0)
, xoff(0)
, yoff(0)
, data()
{
}

RequestResource::~RequestResource()
{
  Clear();
}

bool
RequestResource::IsPopup() const {
  return popup;
}

int
RequestResource::GetXPos() const {
  return xpos;
}

int
RequestResource::GetYPos() const {
  return ypos;
}

int
RequestResource::GetWidth() const {
  return width;
}

int
RequestResource::GetHeight() const {
  return height;
}

int
RequestResource::GetXOff() const {
  return xoff;
}

int
RequestResource::GetYOff() const {
  return yoff;
}

unsigned int
RequestResource::GetSize() const {
  return data.size();
}

RequestData
RequestResource::GetRequestData(const unsigned int n) const {
  return data[n];
}

void
RequestResource::Clear()
{
  data.clear();
}

void
RequestResource::Load(FileBuffer *buffer)
{
  try {
    Clear();
    buffer->Skip(2);
    popup = (buffer->GetSint16LE() != 0);
    buffer->Skip(2);
    xpos = buffer->GetSint16LE();
    ypos = buffer->GetSint16LE();
    width = buffer->GetUint16LE();
    height = buffer->GetUint16LE();
    buffer->Skip(2);
    xoff = buffer->GetSint16LE();
    yoff = buffer->GetSint16LE();
    buffer->Skip(2);
    buffer->Skip(2);
    buffer->Skip(2);
    buffer->Skip(2);
    unsigned int numRecords = buffer->GetUint16LE();
    int *offset = new int[numRecords];
    for (unsigned int i = 0; i < numRecords; i++) {
      RequestData reqData;
      reqData.widget = buffer->GetUint16LE();
      reqData.action = buffer->GetSint16LE();
      reqData.visible = (buffer->GetUint8() > 0);
      buffer->Skip(2);
      buffer->Skip(2);
      buffer->Skip(2);
      reqData.xpos = buffer->GetSint16LE();
      reqData.ypos = buffer->GetSint16LE();
      reqData.width = buffer->GetUint16LE();
      reqData.height = buffer->GetUint16LE();
      buffer->Skip(2);
      offset[i] = buffer->GetSint16LE();
      reqData.teleport = buffer->GetSint16LE();
      reqData.image = buffer->GetUint16LE();
      reqData.image = (reqData.image >> 1) + (reqData.image & 1);
      buffer->Skip(2);
      reqData.group = buffer->GetUint16LE();
      buffer->Skip(2);
      data.push_back(reqData);
    }
    buffer->Skip(2);
    unsigned int start = buffer->GetBytesDone();
    for (unsigned int i = 0; i < numRecords; i++) {
      if (offset[i] >= 0) {
        buffer->Seek(start + offset[i]);
        data[i].label = buffer->GetString();
      }
    }
    delete[] offset;
  } catch (Exception &e) {
    e.Print("RequestResource::Load");
  }
}
