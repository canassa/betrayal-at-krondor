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

#include <fstream>

#include "Exception.h"
#include "ResourcePath.h"

ResourcePath* ResourcePath::instance = 0;

static const std::string DEFAULT_RESOURCE_PATH[] =
{
  "/opt/krondor/",
  "/opt/share/krondor/",
  "/usr/share/krondor/",
  "/usr/local/share/krondor/",
  "/krondor/",
  "./krondor/",
  "../krondor/",
  ""
};

static const std::string SEARCH_TESTFILE = "krondor.001";
static const std::string DEFAULT_OVERRIDE = "override/";

ResourcePath::ResourcePath()
: path("")
, override("")
{
  int  i = 0;
  bool found = false;
  std::ifstream ifs;
  std::string filename;

  while (!found && (DEFAULT_RESOURCE_PATH[i] != "")) {
    try {
      path = DEFAULT_RESOURCE_PATH[i];
      override = path + DEFAULT_OVERRIDE;
      filename = path + SEARCH_TESTFILE;
      ifs.open(filename.c_str(), std::ios::in | std::ios::binary);
      if (ifs.is_open()) {
        found = true;
        ifs.close();
      }
    } catch (...) {
      /* continu */
    }
    i++;
  }
  if (!found) {
    path = "";
    override = "";
    throw FileNotFound("ResourcePath::ResourcePath(" + SEARCH_TESTFILE + ")");
  }
}

ResourcePath::~ResourcePath()
{
}

ResourcePath*
ResourcePath::GetInstance()
{
  if (!instance) {
    instance = new ResourcePath();
  }
  return instance;
}

void
ResourcePath::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

std::string
ResourcePath::GetPath() const
{
  return path;
}

std::string
ResourcePath::GetOverridePath() const
{
  return override;
}

void ResourcePath::SetPath(const std::string &s)
{
  path = s;
  override = path + DEFAULT_OVERRIDE;
}

void ResourcePath::SetOverridePath(const std::string &s)
{
  override = s;
}

