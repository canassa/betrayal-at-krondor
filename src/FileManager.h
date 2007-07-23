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
 * Copyright (C) 2005-2007  Guido de Jong <guidoj@users.sf.net>
 */

#ifndef FILE_MANAGER_H
#define FILE_MANAGER_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "ConfigData.h"
#include "GameData.h"
#include "ResourceArchive.h"
#include "ResourceData.h"
#include "ResourceIndex.h"

class FileManager {
  private:
    ResourceIndex resIndex;
    ResourceArchive resArchive;
    FileBuffer* LoadConfig(const std::string &name);
    void SaveConfig(const std::string &name, FileBuffer* buffer);
    FileBuffer* LoadGame(const std::string &name);
    void SaveGame(const std::string &name, FileBuffer* buffer);
    FileBuffer* LoadResource(const std::string &name);
    void SaveResource(const std::string &name, FileBuffer* buffer);
    void SaveResource(const std::string &name, FileBuffer* buffer, const unsigned int n);
    static FileManager *instance;
  protected:
    FileManager();
  public:
    ~FileManager();
    static FileManager* GetInstance();
    static void CleanUp();
    bool ConfigExists(const std::string &name);
    void Load(ConfigData *cfg, const std::string &name);
    void Save(ConfigData *cfg, const std::string &name);
    bool GameExists(const std::string &name);
    void Load(GameData *gam, const std::string &name);
    void Save(GameData *gam, const std::string &name);
    bool ResourceExists(const std::string &name);
    void Load(ResourceData *res, const std::string &name);
    void Save(ResourceData *res, const std::string &name);
    void ExtractResource(const std::string &name);
    void ExtractAllResources();
    void ArchiveAllResources();
};

#endif

