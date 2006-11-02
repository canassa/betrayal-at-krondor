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
#include "TileWorldResource.h"

static const unsigned int MAP_SIZE_X = 64;
static const unsigned int MAP_SIZE_Y = 64;

int main(int argc, char *argv[]) {
  try {
    if (argc != 2) {
      std::cerr << "Usage: " << argv[0] << " <WLD-file>" << std::endl;
      return 1;
    }
    TileWorldResource *wld = new TileWorldResource;
    FileManager::GetInstance()->Load(wld, argv[1]);
    printf("%d %d %d %d %d\n", wld->GetSize(), wld->GetMinX(), wld->GetMaxX(), wld->GetMinY(), wld->GetMaxY());
    unsigned int deltaX = wld->GetMaxX() - wld->GetMinX();
    unsigned int deltaY = wld->GetMaxY() - wld->GetMinY();
    uint8_t *map = new uint8_t[MAP_SIZE_X * MAP_SIZE_Y];
    memset(map, 0, MAP_SIZE_X * MAP_SIZE_Y);
    for (unsigned int i = 0; i < wld->GetSize(); i++) {
      TileWorldItem mi = wld->GetItem(i);
      printf("%d,%d: %3d %08x\n", mi.xloc, mi.yloc, mi.type, mi.flags);
      unsigned int x = (mi.xloc - wld->GetMinX()) * MAP_SIZE_X / deltaX;
      unsigned int y = (mi.yloc - wld->GetMinY()) * MAP_SIZE_Y / deltaY;
      map[x + y * MAP_SIZE_X] = mi.type;
    }
    for (unsigned int y = 0; y < MAP_SIZE_Y; y++) {
      for (unsigned int x = 0; x < MAP_SIZE_X; x++) {
        printf("%02x", map[x + y * MAP_SIZE_X]);
      }
      printf("\n");
    }
    delete map;
    delete wld;
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

