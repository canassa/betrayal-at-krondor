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

#include <errno.h>
#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
#include <sys/stat.h>
#include <sys/types.h>

#include "Exception.h"
#include "GamePath.h"
#include "ResourcePath.h"

GamePath* GamePath::instance = 0;

#if defined(WIN32) || defined(__APPLE_CC__)
static const std::string DEFAULT_GAME_PATH = "";
#else
static const std::string DEFAULT_GAME_PATH = std::string(getenv("HOME")) + "/." + std::string(PACKAGE) + "/";
#endif

GamePath::GamePath()
{
  path = DEFAULT_GAME_PATH;
  original = ResourcePath::GetInstance()->GetPath() + "games/";
  resource = ResourcePath::GetInstance()->GetPath();

#if !defined(WIN32) && !defined(__APPLE_CC__)
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

GamePath::~GamePath()
{
}

GamePath*
GamePath::GetInstance()
{
  if (!instance) {
    instance = new GamePath();
  }
  return instance;
}

void
GamePath::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

std::string
GamePath::GetPath() const
{
  return path;
}

std::string
GamePath::GetOriginalPath() const
{
  return original;
}

std::string
GamePath::GetResourcePath() const
{
  return resource;
}

void
GamePath::SetPath(const std::string &s)
{
  path = s;
}

void
GamePath::SetOriginalPath(const std::string &s)
{
  original = s;
}

void
GamePath::SetResourcePath(const std::string &s)
{
  resource = s;
}
