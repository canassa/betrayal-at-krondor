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

#ifndef SDL_TOOLKIT_H
#define SDL_TOOLKIT_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "MediaToolkit.h"
#include "SDL.h"

class SDL_Toolkit: public MediaToolkit {
  private:
    static SDL_Toolkit *instance;
    bool HandleEvent(SDL_Event& event);
  protected:
    SDL_Toolkit();
  public:
    ~SDL_Toolkit();
    static SDL_Toolkit* GetInstance();
    void PollEventLoop();
    void WaitEventLoop();
    void ClearEvents();
    void GetMousePosition(int *x, int *y);
};

#endif

