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
#include "ResourceManager.h"
#include "ResourcePath.h"
#include "RequestResource.h"

int main(int argc, char *argv[]) {
  try {
    if (argc != 2) {
      std::cerr << "Usage: " << argv[0] << " <REQ-file>" << std::endl;
      return 1;
    }
    RequestResource *req = new RequestResource;
    ResourceManager::GetInstance()->Load(req, argv[1]);
    printf("%3d %3d %3d %3d %3d %3d %3d\n", req->GetType(), req->GetXPos(), req->GetYPos(), req->GetWidth(), req->GetHeight(), req->GetXOff(), req->GetYOff());
    for (unsigned int i = 0; i < req->GetSize(); i++) {
      RequestData data = req->GetRequestData(i);
      printf("%3d: %3d %3d %3d %3d %3d %3d %3d %s\n", i,
             data.widget, data.action, data.xpos, data.ypos, data.width, data.height, data.teleport, data.label.c_str());
    }
    delete req;
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

