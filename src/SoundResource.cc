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
#include "SoundResource.h"
#include "ResourceTag.h"

static const unsigned int MAX_NUM_SFX     = 1000;

static const uint32_t     RIFF_ID         = 0x46464952;
static const uint32_t     WAVE_ID         = 0x45564157;
static const uint32_t     FMT_ID          = 0x20746d66;
static const uint32_t     DATA_ID         = 0x61746164;

static const uint32_t     SMF_HEADER      = 0x6468544d;
static const uint32_t     SMF_TRACK       = 0x6b72544d;
static const unsigned int SMF_HEADER_SIZE = 6;
static const unsigned int SMF_PPQN        = 96;

SoundResource::SoundResource()
: TaggedResource()
{
}

SoundResource::~SoundResource()
{
  for (std::map<unsigned int, SoundData>::iterator it = soundMap.begin(); it != soundMap.end(); ++it) {
    delete (*it).second.buffer;
  }
  soundMap.clear();
}

SoundData&
SoundResource::GetSoundData(unsigned int id)
{
  return soundMap[id];
}

FileBuffer *
SoundResource::CreateWave(FileBuffer *buffer, const unsigned int size)
{
  FileBuffer *wave = new FileBuffer(12 + 8 + 16 + 8 + size);
  wave->PutUint32(RIFF_ID);
  wave->PutUint32(wave->GetSize() - 8);
  wave->PutUint32(WAVE_ID);
  wave->PutUint32(FMT_ID);
  wave->PutUint32(16);
  wave->PutUint16(1);
  wave->PutUint16(1);
  wave->PutUint32(0x8400);
  wave->PutUint32(0x8400);
  wave->PutUint16(1);
  wave->PutUint16(8);
  wave->PutUint32(DATA_ID);
  wave->PutUint32(size);
  wave->Copy(buffer, size);
  wave->Rewind();
  return wave;
}

FileBuffer *
SoundResource::CreateMidi(FileBuffer *buffer, const unsigned int size)
{
  const uint8_t *tmp;
  FileBuffer *midi = new FileBuffer(8 + SMF_HEADER_SIZE + 8 + size);
  midi->PutUint32(SMF_HEADER);
  tmp = (const uint8_t *)&SMF_HEADER_SIZE;
  midi->PutUint8(tmp[3]);
  midi->PutUint8(tmp[2]);
  midi->PutUint8(tmp[1]);
  midi->PutUint8(tmp[0]);
  midi->PutUint16(0);
  midi->PutUint8(0);
  midi->PutUint8(1);
  midi->PutUint8(0);
  midi->PutUint8(SMF_PPQN);
  midi->PutUint32(SMF_TRACK);
  tmp = (const uint8_t *)&size;
  midi->PutUint8(tmp[3]);
  midi->PutUint8(tmp[2]);
  midi->PutUint8(tmp[1]);
  midi->PutUint8(tmp[0]);
  midi->Copy(buffer, size);
  midi->Rewind();
  return midi;
}

void
SoundResource::Load(FileBuffer *buffer)
{
  try {
    Split(buffer);
    FileBuffer *infbuf;
    FileBuffer *tagbuf;
    if (!Find(TAG_INF, infbuf) ||
        !Find(TAG_TAG, tagbuf)) {
      Clear();
      throw DataCorruption("SoundResource::Load");
    }
    infbuf->Skip(2);
    unsigned int n = infbuf->GetUint16();
    infbuf->Skip(1);
    ResourceTag tags;
    tags.Load(tagbuf);
    for (unsigned int i = 0; i < n; i++) {
      unsigned int id = infbuf->GetUint16();
      std::streamoff offset = infbuf->GetUint32();
      std::string name;
      if (tags.Find(id, name)) {
        buffer->Rewind();
        buffer->Skip(offset + 8);
        FileBuffer *sndbuf = 0;
        if (id != buffer->GetUint16()) {
          Clear();
          throw DataCorruption("SoundResource::Load");
        }
        buffer->Skip(3);
        unsigned int size = buffer->GetUint32();
        sndbuf = new FileBuffer(size);
        sndbuf->Fill(buffer);
        SoundData data;
        data.name = name;
        data.buffer = sndbuf;
        soundMap.insert(std::pair<unsigned int, SoundData>(id, data));
      } else {
        throw DataCorruption("SoundResource::Load");
      }
    }
    Clear();
  } catch (Exception &e) {
    e.Print("SoundResource::Load");
    Clear();
  }
}

