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

#include <iostream>

#include "Directories.h"
#include "Exception.h"
#include "FileManager.h"
#include "ObjectResource.h"

int main()
{
    try
    {
        for (unsigned int i = 0; i < ObjectResource::GetInstance()->GetSize(); i++)
        {
            ObjectInfo info = ObjectResource::GetInstance()->GetObjectInfo(i);
            printf("%-30s: %04x %3d %5d %3d %3d %3d %3d %1d %1d %2d %04x %6d %04x %3d\n", info.name.c_str(), info.flags, info.level, info.value,
                   info.strengthSwing, info.accuracySwing, info.strengthThrust, info.accuracyThrust, info.imageSize, info.race, info.type,
                   info.effectMask, info.effect, info.modifierMask, info.modifier);
        }
        ObjectResource::CleanUp();
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

