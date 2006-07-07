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
#include "GenericResourceFile.h"
#include "ResourcePath.h"

GenericResourceFile::GenericResourceFile() {
}

GenericResourceFile::~GenericResourceFile() {
}

void
GenericResourceFile::Open(const std::string &name) {
  std::string filename = ResourcePath::GetInstance()->GetOverridePath() + name;
  ifs.open(filename.c_str(), std::ios::in | std::ios::binary);
  if (ifs.fail()) {
    ifs.clear();
    filename = ResourcePath::GetInstance()->GetPath() + name;
    ifs.open(filename.c_str(), std::ios::in | std::ios::binary);
    if (ifs.fail()) {
      throw OpenError("GenericResourceFile::Open(" + filename + ")");
    }
  }
}

void
GenericResourceFile::Close() {
  if (ifs.is_open()) {
    ifs.close();
  }
}

void
GenericResourceFile::Seek(const std::streamoff offset) {
  if (ifs.is_open()) {
    ifs.seekg(offset, std::ios::beg);
    if (ifs.fail()) {
      throw IOError("GenericResourceFile::Seek");
    }
  }
}

void
GenericResourceFile::SeekEnd(const std::streamoff offset) {
  if (ifs.is_open()) {
    ifs.seekg(offset, std::ios::end);
    if (ifs.fail()) {
      throw IOError("GenericResourceFile::SeekEnd");
    }
  }
}

std::streamsize
GenericResourceFile::Size() {
  if (ifs.is_open()) {
    ifs.seekg(0, std::ios::end);
    if (ifs.fail()) {
      throw IOError("GenericResourceFile::Size");
    }
    return ifs.tellg();
  }
  return 0;
}

void
GenericResourceFile::Load(FileBuffer &buffer)
{
  try {
    buffer.Load(ifs);
  } catch (Exception &e) {
    e.Print("GenericResourceFile::Load");
    throw;
  }
}
