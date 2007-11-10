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

#ifndef SDL_TOOLKIT_H
#define SDL_TOOLKIT_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "MediaToolkit.h"
#include "SDL.h"

class SDL_Toolkit
            : public MediaToolkit
{
private:
    void HandleEvent ( SDL_Event *event );
public:
    SDL_Toolkit();
    ~SDL_Toolkit();
    void PollEvents();
    void PollEventLoop();
    void WaitEvents();
    void WaitEventLoop();
    void ClearEvents();
    void GetPointerPosition ( int *x, int *y );
    void SetPointerPosition ( int x, int y );
};

#endif

