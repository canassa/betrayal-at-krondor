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
    delete samples[i];
  }
}

unsigned int
Sound::GetSize() const
{
  return samples.size();
}

Sample *
Sound::GetSample(const unsigned int n)
{
  return samples[n];
}

void
Sound::AddSample(FileBuffer *buffer)
{
  Sample *sample = new Sample();
  sample->Load(buffer);
  samples.push_back(sample);
}
