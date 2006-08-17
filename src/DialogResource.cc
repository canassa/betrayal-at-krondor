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
#include "DialogResource.h"

DialogResource::DialogResource()
: dialogMap()
{
}

DialogResource::~DialogResource()
{
  for (std::map<const unsigned int, DialogData*>::iterator it = dialogMap.begin(); it != dialogMap.end(); ++it) {
    DialogData* data = it->second;
    data->text.clear();
    for (unsigned int i = 0; i < data->subdata.size(); i++) {
      delete data->subdata[i];
    }
    data->subdata.clear();
  }
  dialogMap.clear();
}

unsigned int
DialogResource::GetSize() const {
  return dialogMap.size();
}

bool
DialogResource::Find(const unsigned int n, DialogData*& data) {
  std::map<const unsigned int, DialogData*>::iterator it = dialogMap.find(n);
  if (it != dialogMap.end()) {
    data = it->second;
    return true;
  }
  return false;
}

typedef struct _DialogPageOffset {
  int type;
  unsigned int offset;
} DialogPageOffset;

void
DialogResource::ReadDialogData(FileBuffer *buffer, DialogData *data)
{
  try {
    buffer->Skip(5);
    data->subdialogs = buffer->GetUint8();
    unsigned int n = buffer->GetUint8();
    buffer->Skip(2);
    std::vector<DialogPageOffset> pageOffset;
    for (unsigned int i = 0; i < data->subdialogs; i++) {
      DialogPageOffset dpo;
      buffer->Skip(4);
      dpo.type = buffer->GetSint16LE();
      dpo.offset = buffer->GetUint32LE();
      pageOffset.push_back(dpo);
    }
    bool done = false;
    for (unsigned int i = 0; i < data->subdialogs; i++) {
      if (pageOffset[i].type >= 0) {
        buffer->Seek(pageOffset[i].offset);
        DialogData* sub = new DialogData;
        ReadDialogData(buffer, sub);
        data->subdata.push_back(sub);
        done = true;
      }
    }
    if (!done) {
      for (unsigned int j = 0; j < n; j++) {
        buffer->Skip(10);
      }
      for (unsigned int i = 0; i < data->subdialogs; i++) {
        std::string s = buffer->GetString();
        data->text.push_back(s);
        done = true;
      }
      if (!done) {
        std::string s = buffer->GetString();
        data->text.push_back(s);
      }
    }
    pageOffset.clear();
  } catch (Exception &e) {
    e.Print("DialogResource::ReadDialogData");
  }
}

void
DialogResource::Load(FileBuffer *buffer)
{
  try {
    unsigned int n = buffer->GetUint16LE();
    std::map<const unsigned int, unsigned int> offset;
    for (unsigned int i = 0; i < n; i++) {
      unsigned int key = buffer->GetUint32LE();
      unsigned int value = buffer->GetUint32LE();
      offset.insert(std::pair<const unsigned int, unsigned int>(key, value));
    }
    for (std::map<const unsigned int, unsigned int>::iterator it = offset.begin(); it != offset.end(); ++it) {
      buffer->Seek(it->second);
      DialogData* data = new DialogData;
      ReadDialogData(buffer, data);
      dialogMap.insert(std::pair<const unsigned int, DialogData*>(it->first, data));
    }
    offset.clear();
  } catch (Exception &e) {
    e.Print("DialogResource::Load");
  }
}

