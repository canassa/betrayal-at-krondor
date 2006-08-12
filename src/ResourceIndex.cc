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
#include "ResourceArchive.h"
#include "ResourceIndex.h"

ResourceIndex::ResourceIndex()
: resourceFilename("")
, numResources(0)
{
}

ResourceIndex::~ResourceIndex()
{
  resIdxMap.clear();
}

void
ResourceIndex::Init(const std::string &filename)
{
  try {
    ResourceFile rmf;
    rmf.Open(filename);
    FileBuffer rmfBuffer(rmf.Size());
    rmf.Seek(0);
    rmf.Load(rmfBuffer);
    rmf.Close();
    if ((rmfBuffer.GetUint32() != 1) || (rmfBuffer.GetUint16() != 4)) {
      throw DataCorruption(__FILE__, __LINE__);
    }
    resourceFilename = rmfBuffer.GetString(RES_FILENAME_LEN);
    numResources = rmfBuffer.GetUint16();

    ResourceFile res;
    res.Open(resourceFilename);
    FileBuffer resBuffer(RES_FILENAME_LEN + 4);
    for (unsigned int i = 0; i < numResources; i++) {
      /* skip the hashkey */
      rmfBuffer.Skip(4);
      std::streamoff offset = rmfBuffer.GetUint32();
      res.Seek(offset);
      res.Load(resBuffer);
      std::string resIdxName = resBuffer.GetString(RES_FILENAME_LEN);
      ResourceIndexData resIdxData;
      resIdxData.offset = offset + RES_FILENAME_LEN + 4;
      resIdxData.size = resBuffer.GetUint32();
      resIdxMap.insert(std::pair<const std::string, ResourceIndexData>(resIdxName, resIdxData));
    }
    res.Close();
  } catch (Exception &e) {
    e.Print("ResourceIndex::Init");
    throw;
  }
}

std::string
ResourceIndex::GetResourceFilename() const
{
  return resourceFilename;
}

bool
ResourceIndex::Find(const std::string &name, ResourceIndexData &data)
{
  std::map<const std::string, ResourceIndexData>::iterator it = resIdxMap.find(name);
  if (it != resIdxMap.end()) {
    data = it->second;
    return true;
  }
  return false;
}
