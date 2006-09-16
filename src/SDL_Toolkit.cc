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
#include "SDL_Audio.h"
#include "SDL_Clock.h"
#include "SDL_Toolkit.h"
#include "SDL_Video.h"

SDL_Toolkit::SDL_Toolkit()
: MediaToolkit()
{
  if (SDL_Init(SDL_INIT_AUDIO | SDL_INIT_TIMER | SDL_INIT_VIDEO) < 0) {
    throw SDL_Exception(__FILE__, __LINE__, SDL_GetError());
  }
  audio = new SDL_Audio();
  clock = new SDL_Clock();
  video = new SDL_Video();
}

SDL_Toolkit::~SDL_Toolkit()
{
  delete audio;
  delete clock;
  delete video;
  SDL_Quit();
}

void
SDL_Toolkit::HandleEvent(SDL_Event& event)
{
  switch (event.type) {
    case SDL_KEYDOWN:
      {
        KeyboardEvent kbe((Key)event.key.keysym.sym);
        for (std::list<KeyboardEventListener *>::iterator it = keyboardListeners.begin(); it != keyboardListeners.end(); ++it) {
          (*it)->KeyPressed(kbe);
        }
      }
      break;
    case SDL_KEYUP:
      {
        KeyboardEvent kbe((Key)event.key.keysym.sym);
        for (std::list<KeyboardEventListener *>::iterator it = keyboardListeners.begin(); it != keyboardListeners.end(); ++it) {
          (*it)->KeyReleased(kbe);
        }
      }
      break;
    case SDL_MOUSEBUTTONDOWN:
      {
        MouseButtonEvent mbe((MouseButton)(event.button.button - 1),
                             event.button.x / video->GetScaling(),
                             event.button.y / video->GetScaling());
        for (std::list<MouseButtonEventListener *>::iterator it = mouseButtonListeners.begin(); it != mouseButtonListeners.end(); ++it) {
          (*it)->MouseButtonPressed(mbe);
        }
      }
      break;
    case SDL_MOUSEBUTTONUP:
      {
        MouseButtonEvent mbe((MouseButton)(event.button.button - 1),
                             event.button.x / video->GetScaling(),
                             event.button.y / video->GetScaling());
        for (std::list<MouseButtonEventListener *>::iterator it = mouseButtonListeners.begin(); it != mouseButtonListeners.end(); ++it) {
          (*it)->MouseButtonReleased(mbe);
        }
      }
      break;
    case SDL_MOUSEMOTION:
      {
        MouseMotionEvent mme(event.button.x / video->GetScaling(),
                             event.button.y / video->GetScaling());
        for (std::list<MouseMotionEventListener *>::iterator it = mouseMotionListeners.begin(); it != mouseMotionListeners.end(); ++it) {
          (*it)->MouseMoved(mme);
        }
      }
      break;
    case SDL_USEREVENT:
      // timer event
      {
        clock->CancelTimer((unsigned long)event.user.data1);
        TimerEvent te((unsigned long)event.user.data1);
        for (std::list<TimerEventListener *>::iterator it = timerListeners.begin(); it != timerListeners.end(); ++it) {
          (*it)->TimerExpired(te);
        }
      }
      break;
    default:
      break;
  }
}

void
SDL_Toolkit::PollEvents()
{
  SDL_Event event;
  while (SDL_PollEvent(&event)) {
    HandleEvent(event);
  }
}

void
SDL_Toolkit::PollEventLoop()
{
  int currentTicks;
  int previousTicks = SDL_GetTicks();

  eventLoopRunning = true;
  while (eventLoopRunning) {
    PollEvents();
    currentTicks = SDL_GetTicks();
    UpdateEvent ue(currentTicks - previousTicks);
    for (std::list<UpdateEventListener *>::iterator it = updateListeners.begin(); it != updateListeners.end(); ++it) {
      (*it)->Update(ue);
    }
    previousTicks = currentTicks;
  }
}

void
SDL_Toolkit::WaitEvents()
{
  SDL_Event event;
  if (SDL_WaitEvent(&event)) {
    HandleEvent(event);
  }
}

void
SDL_Toolkit::WaitEventLoop()
{
  eventLoopRunning = true;
  while (eventLoopRunning) {
    WaitEvents();
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

