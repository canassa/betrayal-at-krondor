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

/*! \file xbak.cc
    \brief Main xBaK source file.

    This file contains the the main function of xBaK.
 */

#include <iostream>

#if defined( __MACOS__) || defined(__MACOSX__)
#include "SDL.h"
#endif

#include "Directories.h"
#include "Exception.h"
#include "GameApplication.h"

int main(int argc, char **argv)
{
    if (argc > 1)
    {
        Directories::GetInstance()->SetResourcePath(std::string(argv[1]));
    }
    try
    {
        GameApplication::GetInstance()->Run();
        GameApplication::CleanUp();
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
    Directories::CleanUp();
    return 0;
}

