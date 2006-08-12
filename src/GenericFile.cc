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
#include "GenericFile.h"
#include "ResourcePath.h"

GenericFile::GenericFile() {
}

GenericFile::~GenericFile() {
}

std::string
GenericFile::GetDefaultPath() const
{
  return std::string("");
}

std::string
GenericFile::GetAlternatePath() const
{
  return std::string("");
}

std::string
GenericFile::GetLastResortPath() const
{
  return std::string("");
}

void
GenericFile::Open(const std::string &name) {
  std::string filename = GetDefaultPath() + name;
  ifs.open(filename.c_str(), std::ios::in | std::ios::binary);
  if (ifs.fail()) {
    ifs.clear();
    filename = GetAlternatePath() + name;
    ifs.open(filename.c_str(), std::ios::in | std::ios::binary);
    if (ifs.fail()) {
      ifs.clear();
      filename = GetLastResortPath() + name;
      ifs.open(filename.c_str(), std::ios::in | std::ios::binary);
      if (ifs.fail()) {
        throw OpenError(__FILE__, __LINE__, "(" + filename + ")");
      }
    }
  }
}

void
GenericFile::Close() {
  if (ifs.is_open()) {
    ifs.close();
  }
}

void
GenericFile::Seek(const std::streamoff offset) {
  if (ifs.is_open()) {
    ifs.seekg(offset, std::ios::beg);
    if (ifs.fail()) {
      throw IOError(__FILE__, __LINE__);
    }
  }
}

void
GenericFile::SeekEnd(const std::streamoff offset) {
  if (ifs.is_open()) {
    ifs.seekg(offset, std::ios::end);
    if (ifs.fail()) {
      throw IOError(__FILE__, __LINE__);
    }
  }
}

std::streamsize
GenericFile::Size() {
  if (ifs.is_open()) {
    ifs.seekg(0, std::ios::end);
    if (ifs.fail()) {
      throw IOError(__FILE__, __LINE__);
    }
    return ifs.tellg();
  }
  return 0;
}

void
GenericFile::Load(FileBuffer &buffer)
{
  try {
    buffer.Load(ifs);
  } catch (Exception &e) {
    e.Print("GenericFile::Load");
    throw;
  }
}
