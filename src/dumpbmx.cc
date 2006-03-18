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
#include "ImageResource.h"
#include "ResourceManager.h"
#include "ResourcePath.h"

int main(int argc, char *argv[]) {
  try {
    if (argc != 2) {
      std::cerr << "Usage: " << argv[0] << " <BMX-file>" << std::endl;
      return 1;
    }
    ImageResource *bmx = new ImageResource;
    ResourceManager::GetInstance()->Load(bmx, argv[1]);
    for (unsigned int i = 0; i < bmx->GetNumImages(); i++) {
      Image *image = bmx->GetImage(i);
      printf("%2d  %dx%d\n", i, image->GetWidth(), image->GetHeight());
      for (int y = 0; y < image->GetHeight(); y++) {
        for (int x = 0; x < image->GetWidth(); x++) {
          printf("%02x ", image->GetPixel(x, y));
        }
        printf("\n");
      }
    }
    delete bmx;
    ResourceManager::CleanUp();
    ResourcePath::CleanUp();
  } catch (Exception &e) {
    e.Print("main");
  } catch (...) {
    /* every exception should have been handled before */
    std::cerr << "Unhandled exception" << std::endl;
  }
  return 0;
}

