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
#include "GameFile.h"
#include "ResourceFile.h"

FileManager* FileManager::instance = 0;

FileManager::FileManager()
{
  resIndex.Init("krondor.rmf");
  resArchive.Open(resIndex.GetResourceFilename());
}

FileManager::~FileManager()
{
  resArchive.Close();
}

FileManager*
FileManager::GetInstance()
{
  if (!instance) {
    instance = new FileManager();
  }
  return instance;
}

void
FileManager::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

FileBuffer*
FileManager::LoadGame(const std::string &name)
{
  try {
    GameFile gamfile;
    gamfile.Open(name);
    FileBuffer *buffer = new FileBuffer(gamfile.Size());
    gamfile.Seek(0);
    gamfile.Load(*buffer);
    gamfile.Close();
    return buffer;
  } catch (Exception &e) {
    throw FileNotFound(__FILE__, __LINE__, name);
  }
  return 0;
}

FileBuffer*
FileManager::LoadResource(const std::string &name)
{
  try {
    ResourceFile resfile;
    resfile.Open(name);
    FileBuffer *buffer = new FileBuffer(resfile.Size());
    resfile.Seek(0);
    resfile.Load(*buffer);
    resfile.Close();
    return buffer;
  } catch (Exception &e1) {
    ResourceIndexData resIdxData = {0, 0};
    if (resIndex.Find(name, resIdxData) && (resIdxData.size != 0)) {
      try {
        FileBuffer *buffer = new FileBuffer(resIdxData.size);
        resArchive.LoadResource(*buffer, resIdxData.offset);
        return buffer;
      } catch (Exception &e2) {
        e2.Print("FileManager::LoadResource");
        throw;
      }
    } else {
      throw FileNotFound(__FILE__, __LINE__, name);
    }
  }
  return 0;
}

void
FileManager::Load(GameData *gam, const std::string &name)
{
  try {
    FileBuffer *buffer;
    buffer = LoadGame(name);
    gam->Load(buffer);
    delete buffer;
  } catch (Exception &e) {
    e.Print("FileManager::Load");
    throw;
  }
}

void
FileManager::Load(ResourceData *res, const std::string &name)
{
  try {
    FileBuffer *buffer;
    buffer = LoadResource(name);
    res->Load(buffer);
    delete buffer;
  } catch (Exception &e) {
    e.Print("FileManager::Load");
    throw;
  }
}

