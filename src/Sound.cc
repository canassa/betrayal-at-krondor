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

/* WAVE/RIFF tags & constants */
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

/* Standard MIDI File tags & constants */
static const uint32_t SMF_HEADER      = 0x6468544d;
static const uint32_t SMF_TRACK       = 0x6b72544d;
static const uint32_t SMF_HEADER_SIZE = 6;
static const uint8_t  SMF_PPQN        = 96;

/* MIDI event codes */
static const uint8_t MIDI_NOTE_OFF = 0x80;
static const uint8_t MIDI_NOTE_ON  = 0x90;
static const uint8_t MIDI_KEY      = 0xa0;
static const uint8_t MIDI_CONTROL  = 0xb0;
static const uint8_t MIDI_PATCH    = 0xc0;
static const uint8_t MIDI_CHANNEL  = 0xd0;
static const uint8_t MIDI_PITCH    = 0xe0;
static const uint8_t MIDI_SYSEX    = 0xf0;
static const uint8_t MIDI_META     = 0xff;

/* MIDI Meta events */
static const uint8_t META_SEQNUM     = 0x00;
static const uint8_t META_TEXT       = 0x01;
static const uint8_t META_COPYRIGHT  = 0x02;
static const uint8_t META_TRACK      = 0x03;
static const uint8_t META_INSTRUMENT = 0x04;
static const uint8_t META_LYRIC      = 0x05;
static const uint8_t META_MARKER     = 0x06;
static const uint8_t META_CUE        = 0x07;
static const uint8_t META_CHANNEL    = 0x20;
static const uint8_t META_PORT       = 0x21;
static const uint8_t META_EOT        = 0x2f;
static const uint8_t META_TEMPO      = 0x51;
static const uint8_t META_SMPTE      = 0x54;
static const uint8_t META_TIME       = 0x58;
static const uint8_t META_KEY        = 0x59;
static const uint8_t META_SEQDATA    = 0x7f;

FileBuffer *
Sound::CreateMidi(FileBuffer *buffer, const unsigned int channel)
{
  buffer->Skip(2);
  unsigned int code = buffer->GetUint8();
  if (code & 0x0f != channel) {
    throw DataCorruption("Sound::CreateMidi");
  }
  switch (code & 0xf0) {
    default:
      break;
  }
  unsigned int size = buffer->GetBytesLeft();
  FileBuffer *midi = new FileBuffer(8 + SMF_HEADER_SIZE + 8 + size);
  midi->PutUint32(SMF_HEADER);
  midi->PutUint32Reverse(SMF_HEADER_SIZE);
  midi->PutUint16(0);
  midi->PutUint8(0);
  midi->PutUint8(1);
  midi->PutUint8(0);
  midi->PutUint8(SMF_PPQN);
  midi->PutUint32(SMF_TRACK);
  midi->PutUint32Reverse(size);
  midi->Copy(buffer, size);
  midi->Rewind();
  return midi;
}

void
Sound::AddSample(FileBuffer *buffer)
{
  SampleData *sample = new SampleData();
  unsigned int code = buffer->GetUint8();
  if (code == 0xfe) {
    sample->format = SF_WAVE;
    sample->buffer = CreateWave(buffer);
  } else {
    sample->format = SF_MIDI;
    sample->buffer = CreateMidi(buffer, code & 0x0f);
  }
  samples.push_back(sample);
}
