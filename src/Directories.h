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

#ifndef DIRECTORIES_H
#define DIRECTORIES_H

#include <string>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

class Directories
{
  private:
    std::string resourcePath;
    std::string sharedPath;
    std::string userPath;
    std::string gamesPath;
    std::string capturePath;
    static Directories *instance;
    void CreatePath(const std::string& path);
    std::string SearchResources() const;
  protected:
    Directories();
  public:
    ~Directories();
    static Directories* GetInstance();
    static void CleanUp();
    std::string GetResourcePath() const;
    std::string GetSharedPath() const;
    std::string GetUserPath() const;
    std::string GetGamesPath() const;
    std::string GetCapturePath() const;
    void SetResourcePath(const std::string &path);
};

#endif
