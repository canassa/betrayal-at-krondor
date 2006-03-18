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

#ifndef RESOURCE_PATH_H
#define RESOURCE_PATH_H

#include <string>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

class ResourcePath
{
  private:
    std::string path;
    std::string override;
    static ResourcePath *instance;
  protected:
    ResourcePath();
  public:
    ~ResourcePath();
    static ResourcePath* GetInstance();
    static void CleanUp();
    std::string GetPath() const;
    std::string GetOverridePath() const;
    void SetPath(const std::string &s);
    void SetOverridePath(const std::string &s);
};

#endif
