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
#include "Sample.h"

Sample::Sample()
: type(0)
, channels(1)
, rate(0)
, bitsPerSample(8)
, sampleBuffer(0)
{
}

Sample::~Sample()
{
  if (sampleBuffer) {
    delete sampleBuffer;
  }
}

unsigned int
Sample::GetChannels() const
{
  return channels;
}

unsigned int
Sample::GetRate() const
{
  return rate;
}

unsigned int
Sample::GetBitsPerSample() const
{
  return bitsPerSample;
}

FileBuffer *
Sample::GetBuffer()
{
  return sampleBuffer;
}

void
Sample::Load(FileBuffer *buffer)
{
  if (sampleBuffer) {
    delete sampleBuffer;
  }
  unsigned int size = 0;
  type = buffer->GetUint8();
  switch (type) {
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
      size = buffer->GetBytesLeft();
      break;
    case 0xfe:
      buffer->Skip(1);
      rate = buffer->GetUint16();
      size = buffer->GetUint32();
      buffer->Skip(2);
      break;
    default:
      throw DataCorruption("Sample::Load");
      break;
  }
  sampleBuffer = new FileBuffer(size);
  sampleBuffer->Fill(buffer);
}
