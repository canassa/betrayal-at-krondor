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

#include "Exception.h"
#include "AnimationResource.h"
#include "ResourceManager.h"
#include "ResourcePath.h"

int main(int argc, char *argv[]) {
  try {
    if (argc != 2) {
      std::cerr << "Usage: " << argv[0] << " <ADS-file>" << std::endl;
      return 1;
    }
    AnimationResource *anim = new AnimationResource;
    ResourceManager::GetInstance()->Load(anim, argv[1]);
    AnimationData data = anim->GetAnimationData(1);
    printf("%s %s %s\n", anim->GetVersion().c_str(), data.name.c_str(), data.resource.c_str());
    FileBuffer *scr = anim->GetScript();
    while (!scr->AtEnd()) {
      unsigned int code = scr->GetUint16();
      printf("%04x ", code);
      switch (code) {
        case 0x0001:
          break;
        case 0x1030:
          printf(" %d %d", scr->GetUint16(), scr->GetUint16());
          break;
        case 0x1330:
          printf(" %d %d", scr->GetUint16(), scr->GetUint16());
          break;
        case 0x1350:
          printf(" %d %d", scr->GetUint16(), scr->GetUint16());
          break;
        case 0x1420:
          break;
        case 0x1510:
          break;
        case 0x1520:
          break;
        case 0x2005:
          printf(" %d %d %d %d", scr->GetUint16(), scr->GetUint16(), scr->GetUint16(), scr->GetUint16());
          break;
        case 0x2010:
          printf(" %d %d %d", scr->GetUint16(), scr->GetUint16(), scr->GetUint16());
          break;
        case 0xffff:
          break;
        default:
          printf(" unknown");
          break;
      }
      printf("\n");
    }
    delete anim;
    delete ResourceManager::GetInstance();
    delete ResourcePath::GetInstance();
  } catch (Exception &e) {
    e.Print("main");
  } catch (...) {
    /* every exception should have been handled before */
    std::cerr << "Unhandled exception" << std::endl;
  }
  return 0;
}

