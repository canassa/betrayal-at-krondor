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

void
SDL_Toolkit::HandleEvent(SDL_Event& event)
{
  KeyboardEvent *kbe;
  if (eventHandler) {
    switch (event.type) {
      case SDL_KEYDOWN:
        eventHandler->HandleKeyboardEvent(event.key.keysym.sym, true);
        kbe = new KeyboardEvent((Key)event.key.keysym.sym);
        for (unsigned int i = 0; i < keyboardListeners.size(); i++) {
          keyboardListeners[i]->KeyPressed(*kbe);
        }
        delete kbe;
        break;
      case SDL_KEYUP:
        eventHandler->HandleKeyboardEvent(event.key.keysym.sym, false);
        kbe = new KeyboardEvent((Key)event.key.keysym.sym);
        for (unsigned int i = 0; i < keyboardListeners.size(); i++) {
          keyboardListeners[i]->KeyReleased(*kbe);
        }
        delete kbe;
        break;
      case SDL_MOUSEBUTTONDOWN:
        eventHandler->HandleMouseButtonEvent(event.button.button - 1,
                                             event.button.x / video->GetScaling(),
                                             event.button.y / video->GetScaling(),
                                             true);
        break;
      case SDL_MOUSEBUTTONUP:
        eventHandler->HandleMouseButtonEvent(event.button.button - 1,
                                             event.button.x / video->GetScaling(),
                                             event.button.y / video->GetScaling(),
                                             false);
        break;
      case SDL_MOUSEMOTION:
        eventHandler->HandleMouseMotionEvent(event.motion.x / video->GetScaling(),
                                             event.motion.y / video->GetScaling());
        break;
      default:
        break;
    }
  }
}

void
SDL_Toolkit::PollEventLoop()
{
  if (eventHandler) {
    eventLoopRunning = true;
    SDL_Event event;
    while (eventLoopRunning) {
      while (SDL_PollEvent(&event)) {
        HandleEvent(event);
      }
      eventHandler->HandleUpdateEvent();
    }
  }
}

void
SDL_Toolkit::WaitEventLoop()
{
  if (eventHandler) {
    eventLoopRunning = true;
    SDL_Event event;
    while (eventLoopRunning) {
      if (SDL_WaitEvent(&event)) {
        HandleEvent(event);
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
