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

#include <fstream>

#include <errno.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <sys/stat.h>
#include <sys/types.h>

#include "Exception.h"
#include "Directories.h"

Directories* Directories::instance = 0;

Directories::Directories()
: resourcePath("")
, sharedPath("")
, userPath("")
, gamesPath("")
, capturePath("")
{
  resourcePath = SearchResources();
#if defined(DATADIR)
  sharedPath = std::string(DATADIR) + std::string(PACKAGE) + "/";
#else
  sharedPath = "";
#endif
#if defined(WIN32) || defined(__APPLE_CC__)
  userPath = "";
  gamesPath = "";
  capturePath = "";
#else
  userPath = std::string(getenv("HOME")) + "/." + std::string(PACKAGE) + "/";
  gamesPath = userPath + "/games/";
  capturePath = userPath + "/capture/";
#endif
  CreatePath(userPath);
  CreatePath(gamesPath);
  CreatePath(capturePath);
}

Directories::~Directories()
{
}

Directories*
Directories::GetInstance()
{
  if (!instance) {
    instance = new Directories();
  }
  return instance;
}

void
Directories::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
Directories::CreatePath(const std::string &path)
{
#if defined(WIN32)
  // TODO
#elif defined(__APPLE_CC__)
  // TODO
#else
  struct stat statbuf;
  if (stat(path.c_str(), &statbuf) == -1) {
    if (errno == ENOENT) {
      if (mkdir(path.c_str(), S_IRWXU| S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH) == -1) {
        throw IOError(__FILE__, __LINE__);
      }
    } else {
      throw FileNotFound(__FILE__, __LINE__, path);
    }
  }
#endif
}

static const std::string SEARCH_RESOURCE_FILE = "krondor.001";
static const std::string SEARCH_RESOURCE_PATH[] =
{
  "/opt/krondor/",
  "/opt/share/krondor/",
  "/krondor/",
  "./krondor/",
  "../krondor/",
  ""
};

std::string
Directories::SearchResources() const
{
  unsigned int i = 0;
  while (SEARCH_RESOURCE_PATH[i] != "") {
    try {
      std::string path = SEARCH_RESOURCE_PATH[i];
      std::string filename = path + SEARCH_RESOURCE_FILE;
      std::ifstream ifs;
      ifs.open(filename.c_str(), std::ios::in | std::ios::binary);
      if (ifs.is_open()) {
        ifs.close();
        return path;
      }
    } catch (...) {
      /* continu */
    }
    i++;
  }
  throw FileNotFound(__FILE__, __LINE__, SEARCH_RESOURCE_FILE);
  return "";
}

void
Directories::SetResourcePath(const std::string &path)
{
  resourcePath = path;
}

std::string
Directories::GetResourcePath() const
{
  return resourcePath;
}

std::string
Directories::GetSharedPath() const
{
  return sharedPath;
}

std::string
Directories::GetUserPath() const
{
  return userPath;
}

std::string
Directories::GetGamesPath() const
{
  return gamesPath;
}

std::string
Directories::GetCapturePath() const
{
  return capturePath;
}
