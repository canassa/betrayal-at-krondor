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
#include "Sound.h"

Sound::Sound(const unsigned int t)
: type(t)
, samples()
{
}

Sound::~Sound()
{
  for (unsigned int i = 0; i < samples.size(); i++) {
    delete (samples[i])->buffer;
    delete samples[i];
  }
}

unsigned int
Sound::GetSize() const
{
  return samples.size();
}

SampleData *
Sound::GetSample(const unsigned int n)
{
  return samples[n];
}

static const uint32_t RIFF_ID         = 0x46464952;
static const uint32_t WAVE_ID         = 0x45564157;
static const uint32_t FMT_ID          = 0x20746d66;
static const uint32_t DATA_ID         = 0x61746164;

FileBuffer *
Sound::CreateWave(FileBuffer *buffer)
{
  buffer->Skip(1);
  unsigned int rate = buffer->GetUint16();
  unsigned int size = buffer->GetUint32();
  buffer->Skip(2);
  FileBuffer *wave = new FileBuffer(12 + 8 + 16 + 8 + size);
  wave->PutUint32(RIFF_ID);
  wave->PutUint32(wave->GetSize() - 8);
  wave->PutUint32(WAVE_ID);
  wave->PutUint32(FMT_ID);
  wave->PutUint32(16);      // chunk size
  wave->PutUint16(1);       // compression: 1 = uncompressed PCM
  wave->PutUint16(1);       // # channels
  wave->PutUint32(rate);    // sample rate
  wave->PutUint32(rate);    // average bytes per sec: sample rate * block align
  wave->PutUint16(1);       // block align: significant bits per sample / 8 * # channels
  wave->PutUint16(8);       // significant bits per sample
  wave->PutUint32(DATA_ID);
  wave->PutUint32(size);
  wave->Copy(buffer, size);
  wave->Rewind();
  return wave;
}

static const uint32_t SMF_HEADER      = 0x6468544d;
static const uint32_t SMF_TRACK       = 0x6b72544d;
static const uint32_t SMF_HEADER_SIZE = 0x00000006;
static const uint8_t  SMF_PPQN        = 96;

FileBuffer *
Sound::CreateMidi(FileBuffer *buffer)
{
  unsigned int size = buffer->GetBytesLeft();
  FileBuffer *midi = new FileBuffer(8 + SMF_HEADER_SIZE + 8 + size);
  midi->PutUint32(SMF_HEADER);
  midi->PutUint32(SMF_HEADER_SIZE);
  midi->PutUint16(0);
  midi->PutUint8(0);
  midi->PutUint8(1);
  midi->PutUint8(0);
  midi->PutUint8(SMF_PPQN);
  midi->PutUint32(SMF_TRACK);
  midi->PutUint8((size >> 24) & 0xff);
  midi->PutUint8((size >> 16) & 0xff);
  midi->PutUint8((size >> 8) & 0xff);
  midi->PutUint8(size & 0xff);
  midi->Copy(buffer, size);
  midi->Rewind();
  return midi;
}

void
Sound::AddSample(FileBuffer *buffer)
{
  SampleData *sample = new SampleData();
  switch (buffer->GetUint8()) {
    case 0x00:
    case 0x01:
    case 0x02:
    case 0x03:
    case 0x04:
    case 0x05:
    case 0x06:
    case 0x07:
    case 0x08:
    case 0x09:
    case 0x0a:
    case 0x0b:
    case 0x0c:
    case 0x0d:
    case 0x0e:
    case 0x0f:
    case 0x29:
      sample->format = SF_UNKNOWN;
      sample->buffer = new FileBuffer(buffer->GetBytesLeft());
      sample->buffer->Fill(buffer);
      break;
    case 0xfe:
      sample->format = SF_WAVE;
      sample->buffer = CreateWave(buffer);
      break;
    default:
      throw DataCorruption("Sound::AddSample");
      break;
  }
  samples.push_back(sample);
}
