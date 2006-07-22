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
#include "FileManager.h"
#include "ResourcePath.h"
#include "SoundResource.h"

int main(int argc, char *argv[]) {
  try {
    if (argc != 2) {
      printf("Usage: %s <sound-id>\n", argv[0]);
      return 1;
    }
    SoundResource *snd = new SoundResource;
    FileManager::GetInstance()->Load(snd, "Frp.sx");
    SoundData data = snd->GetSoundData(atoi(argv[1]));
    printf("%8s %d\n", data.name.c_str(), data.buffer->GetSize());
    //data.buffer->Dump();
    std::ofstream ofs;
    ofs.open("snd.out", std::ios::binary);
    data.buffer->Save(ofs);
    ofs.close();
    delete snd;
    FileManager::CleanUp();
    ResourcePath::CleanUp();
  } catch (Exception &e) {
    e.Print("main");
  } catch (...) {
    /* every exception should have been handled before */
    std::cerr << "Unhandled exception" << std::endl;
  }
  return 0;
}

