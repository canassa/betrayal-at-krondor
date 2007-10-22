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

/*! \file dumpddx.cc
    \brief Main dumpddx source file.

    This file contains the the main function of the .DDX data dumper.
 */

#include <iostream>

#include "DialogResource.h"
#include "Directories.h"
#include "Exception.h"
#include "FileManager.h"

void dumpDialogData(unsigned int n, DialogData *data, unsigned int depth)
{
    for (unsigned int d = 0; d < depth; d++)
    {
        printf("\t");
    }
    printf("%d\t%d\n", n, data->childDialogs);
    for (unsigned int i = 0; i < data->text.size(); i++)
    {
        for (unsigned int d = 0; d < depth; d++)
        {
            printf("\t");
        }
        printf("\t%d: %s\n", i, data->text[i].c_str());
    }
    for (unsigned int i = 0; i < data->childData.size(); i++)
    {
        dumpDialogData(i, data->childData[i], depth+1);
    }
}

int main(int argc, char *argv[])
{
    try
    {
        if (argc != 2)
        {
            std::cerr << "Usage: " << argv[0] << " <DDX-file>" << std::endl;
            return 1;
        }
        DialogResource *ddx = new DialogResource;
        FileManager::GetInstance()->Load(ddx, argv[1]);
        printf("Size: %d\n", ddx->GetSize());
        DialogData* data = 0;
        for (unsigned int i = 0; i < 512; i++)
        {
            if (ddx->Find(i, data))
            {
                dumpDialogData(i, data, 0);
            }
        }
        delete ddx;
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

