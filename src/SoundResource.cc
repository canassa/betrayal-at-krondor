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
#include "FileManager.h"
#include "SoundResource.h"
#include "ResourceTag.h"

static const unsigned int MAX_NUM_SFX = 1000;

SoundData::SoundData()
: name()
, type(0)
, sounds()
{
}

SoundData::~SoundData()
{
  sounds.clear();
}

SoundResource* SoundResource::instance = 0;

SoundResource::SoundResource()
: TaggedResource()
, soundMap()
{
}

SoundResource::~SoundResource()
{
  Clear();
}

SoundResource*
SoundResource::GetInstance()
{
  if (!instance) {
    instance = new SoundResource();
    FileManager::GetInstance()->Load(instance, "frp.sx");
  }
  return instance;
}

void
SoundResource::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

SoundData&
SoundResource::GetSoundData(unsigned int id)
{
  return soundMap[id];
}

void
SoundResource::Clear()
{
  for (std::map<unsigned int, SoundData>::iterator it = soundMap.begin(); it != soundMap.end(); ++it) {
    SoundData data = (*it).second;
    for (std::vector<Sound *>::iterator it2 = data.sounds.begin(); it2 != data.sounds.end(); ++it2) {
      delete (*it2);
    }
  }
  soundMap.clear();
}

void
SoundResource::Load(FileBuffer *buffer)
{
  try {
    Clear();
    Split(buffer);
    FileBuffer *infbuf;
    FileBuffer *tagbuf;
    if (!Find(TAG_INF, infbuf) ||
        !Find(TAG_TAG, tagbuf)) {
      ClearTags();
      throw DataCorruption(__FILE__, __LINE__);
    }
    infbuf->Skip(2);
    unsigned int n = infbuf->GetUint16LE();
    infbuf->Skip(1);
    ResourceTag tags;
    tags.Load(tagbuf);
    for (unsigned int i = 0; i < n; i++) {
      unsigned int id = infbuf->GetUint16LE();
      std::streamoff offset = infbuf->GetUint32LE();
      std::string name;
      if (tags.Find(id, name)) {
        buffer->Seek(offset + 8);
        if (id != buffer->GetUint16LE()) {
          ClearTags();
          throw DataCorruption(__FILE__, __LINE__);
        }
        SoundData data;
        data.name = name;
        data.type = buffer->GetUint8();
        buffer->Skip(2);
        FileBuffer *sndbuf = new FileBuffer(buffer->GetUint32LE() - 2);
        buffer->Skip(2);
        sndbuf->Fill(buffer);
        buffer->Skip(-sndbuf->GetSize());
        int code = buffer->GetUint8();
        while (code != 0xff) {
          Sound *sound = new Sound(code);
          std::vector<unsigned int> offsetVec;
          std::vector<unsigned int> sizeVec;
          code = buffer->GetUint8();
          while (code != 0xff) {
            buffer->Skip(1);
            offsetVec.push_back(buffer->GetUint16LE());
            sizeVec.push_back(buffer->GetUint16LE());
            code = buffer->GetUint8();
          }
          for (unsigned int j = 0; j < offsetVec.size(); j++) {
            sndbuf->Seek(offsetVec[j]);
            FileBuffer *samplebuf = new FileBuffer(sizeVec[j]);
            samplebuf->Fill(sndbuf);
            sound->AddVoice(samplebuf);
            delete samplebuf;
          }
          sound->GenerateBuffer();
          data.sounds.push_back(sound);
          code = buffer->GetUint8();
        }
        soundMap.insert(std::pair<unsigned int, SoundData>(id, data));
        delete sndbuf;
      } else {
        throw DataCorruption(__FILE__, __LINE__);
      }
    }
    ClearTags();
  } catch (Exception &e) {
    e.Print("SoundResource::Load");
    ClearTags();
    throw;
  }
}

void
SoundResource::Save(FileBuffer *buffer)
{
  try {
    // TODO
    buffer = buffer;
  } catch (Exception &e) {
    e.Print("SoundResource::Save");
    throw;
  }
}
