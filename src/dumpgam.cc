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
#include "GameResource.h"

int main(int argc, char *argv[]) {
  try {
    if (argc != 2) {
      std::cerr << "Usage: " << argv[0] << " <GAM-file>" << std::endl;
      return 1;
    }
    GameResource *gam = new GameResource;
    FileManager::GetInstance()->Load(gam, argv[1]);
    Game *game = gam->GetGame();
    printf("%s  (%d, %d)\n", game->GetName().c_str(), gam->GetXPos(), gam->GetYPos());
    printf("z: %d  c: (%d, %d)  l: (%d, %d)  o: %d\n",
           gam->GetZone(), gam->GetXCell(), gam->GetYCell(), gam->GetXLoc(), gam->GetYLoc(), gam->GetHeading());
    for (unsigned int m = 0; m < 6; m++) {
      printf("%10s:", gam->GetMemberName(m).c_str());
      for (unsigned int i = 0; i < 16; i++) {
        printf("\n\t");
        for (unsigned int j = 0; j < 5; j++) {
          printf(" %3d", gam->GetMemberData(m, i, j));
        }
      }
      printf("\n");
    }
    printf("active: %s %s %s\n",
           gam->GetMemberName(gam->GetActiveMember(0)).c_str(),
           gam->GetMemberName(gam->GetActiveMember(1)).c_str(),
           gam->GetMemberName(gam->GetActiveMember(2)).c_str());
    delete gam;
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

