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

#include "Exception.h"
#include "SDL_Clock.h"
#include "SDL_Toolkit.h"
#include "SDL_Video.h"

SDL_Toolkit* SDL_Toolkit::instance = 0;

SDL_Toolkit::SDL_Toolkit()
: MediaToolkit()
{
  if (SDL_Init(SDL_INIT_AUDIO | SDL_INIT_TIMER | SDL_INIT_VIDEO) < 0) {
    throw SDL_Exception(SDL_GetError());
  }
  clock = new SDL_Clock();
  video = new SDL_Video();
}

SDL_Toolkit::~SDL_Toolkit()
{
  delete clock;
  delete video;
  SDL_Quit();
}

SDL_Toolkit*
SDL_Toolkit::GetInstance()
{
  if (!instance) {
    instance = new SDL_Toolkit();
  }
  return instance;
}

bool
SDL_Toolkit::HandleEvent(SDL_Event& event)
{
  bool result = false;
  if (eventHandler) {
    switch (event.type) {
      case SDL_KEYDOWN:
      case SDL_KEYUP:
        result = eventHandler->HandleKeyboardEvent(event.key.keysym.sym,
                                                   event.type == SDL_KEYDOWN);
        break;
      case SDL_MOUSEBUTTONDOWN:
      case SDL_MOUSEBUTTONUP:
        result = eventHandler->HandleMouseButtonEvent(event.button.button,
                                                      event.button.x / video->GetScaling(),
                                                      event.button.y / video->GetScaling(),
                                                      event.type == SDL_MOUSEBUTTONDOWN);
        break;
      case SDL_MOUSEMOTION:
        result = eventHandler->HandleMouseMotionEvent(event.motion.x / video->GetScaling(),
                                                      event.motion.y / video->GetScaling());
        break;
      case SDL_QUIT:
        result = true;
        break;
    }
  }
  return result;
}

void
SDL_Toolkit::PollEventLoop()
{
  if (eventHandler) {
    bool done = false;
    SDL_Event event;
    while (!done) {
      while (SDL_PollEvent(&event)) {
        done |= HandleEvent(event);
      }
      done |= eventHandler->HandleUpdateEvent();
    }
  }
}

void
SDL_Toolkit::WaitEventLoop()
{
  if (eventHandler) {
    bool done = false;
    SDL_Event event;
    while (!done) {
      if (SDL_WaitEvent(&event)) {
        done |= HandleEvent(event);
      }
    }
  }
}

void
SDL_Toolkit::ClearEvents()
{
  SDL_Event event;
  while (SDL_PollEvent(&event)) {
    // nothing
  }
}

void
SDL_Toolkit::GetMousePosition(int *x, int *y)
{
  SDL_GetMouseState(x, y);
}

