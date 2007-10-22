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

/*! \file dumpsnd.cc
    \brief Main dumpsnd source file.

    This file contains the the main function of the midi data dumper.
 */

#include <iostream>
#include <sstream>

#include "Directories.h"
#include "Exception.h"
#include "FileManager.h"
#include "Sound.h"
#include "SoundResource.h"

int main(int argc, char *argv[])
{
    try
    {
        if (argc != 2)
        {
            printf("Usage: %s <sound-id>\n", argv[0]);
            return 1;
        }
        SoundResource *snd = SoundResource::GetInstance();
        SoundData data = snd->GetSoundData(atoi(argv[1]));
        printf("%8s %d %d\n", data.name.c_str(), data.type, (unsigned int)data.sounds.size());
        for (unsigned int i = 0; i < data.sounds.size(); i++)
        {
            Sound *sound = data.sounds[i];
            printf("%d: %d %d %d\n", i, sound->GetType(),sound->GetChannel(), sound->GetFormat());
            FileBuffer *buf = sound->GetSamples();
            buf->Dump();
        }
        delete snd;
        SoundResource::CleanUp();
        FileManager::CleanUp();
        Directories::CleanUp();
    }
    catch (Exception &e)
    {
        e.Print("main");
    }
    catch (...)
    {
        /* every exception should have been handled before */
        std::cerr << "Unhandled exception" << std::endl;
    }
    return 0;
}

