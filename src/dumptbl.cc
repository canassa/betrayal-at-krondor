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

#include <iostream>

#include "Directories.h"
#include "Exception.h"
#include "FileManager.h"
#include "TableResource.h"

int main(int argc, char *argv[]) {
  try {
    if (argc != 2) {
      std::cerr << "Usage: " << argv[0] << " <TBL-file>" << std::endl;
      return 1;
    }
    TableResource *tbl = new TableResource;
    FileManager::GetInstance()->Load(tbl, argv[1]);
    for (unsigned int i = 0; i < tbl->GetMapSize(); i++) {
      GidInfo gid = tbl->GetGidItem(i);
      DatInfo dat = tbl->GetDatItem(i);
      printf("%3d: %-8s %6d %6d %04x %02x %2d %2d %2d\n", i, tbl->GetMapItem(i).c_str(),
             gid.xsize, gid.ysize, gid.flags,
             dat.objectClass, dat.objectType, dat.terrainClass, dat.terrainType);
    }
    delete tbl;
    FileManager::CleanUp();
    Directories::CleanUp();
  } catch (Exception &e) {
    e.Print("main");
  } catch (...) {
    /* every exception should have been handled before */
    std::cerr << "Unhandled exception" << std::endl;
  }
  return 0;
}

