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

#include "Exception.h"
#include "Null_Audio.h"
#include "SDL_Audio.h"
#include "SDL_Clock.h"
#include "SDL_Toolkit.h"
#include "SDL_Video.h"

static const int16_t      JOYSTICK_AXIS_FACTOR = 16384;
static const unsigned int JOYSTICK_SPEED       = 4;

SDL_Toolkit::SDL_Toolkit()
    : MediaToolkit()
    , xPos(0)
    , yPos(0)
    , xMove(0)
    , yMove(0)
    , joystick(0)
{
    if (SDL_Init(SDL_INIT_AUDIO | SDL_INIT_TIMER | SDL_INIT_VIDEO | SDL_INIT_JOYSTICK) < 0)
    {
        throw SDL_Exception(__FILE__, __LINE__, SDL_GetError());
    }
#if defined(HAVE_LIBSDL_MIXER) && defined(HAVE_LIBSDL_SOUND)
    audio = new SDL_Audio();
#else
    audio = new Null_Audio();
#endif
    clock = new SDL_Clock();
    video = new SDL_Video();

    if (SDL_NumJoysticks() > 0)
    {
        joystick = SDL_JoystickOpen(0);
        if (!joystick)
        {
            throw SDL_Exception(__FILE__, __LINE__, SDL_GetError());
        }
    }

}

SDL_Toolkit::~SDL_Toolkit()
{
    SDL_WM_GrabInput(SDL_GRAB_OFF);
    if (joystick)
    {
        SDL_JoystickClose(joystick);
    }
    delete audio;
    delete clock;
    delete video;
    SDL_Quit();
}

void
SDL_Toolkit::HandleEvent(SDL_Event *event)
{
    switch (event->type)
    {
        case SDL_KEYDOWN:
            {
                KeyboardEvent kbe((Key)event->key.keysym.sym);
                for (std::list<KeyboardEventListener *>::iterator it = keyboardListeners.begin(); it != keyboardListeners.end(); ++it)
                {
                    (*it)->KeyPressed(kbe);
                }
            }
            break;
        case SDL_KEYUP:
            {
                KeyboardEvent kbe((Key)event->key.keysym.sym);
                for (std::list<KeyboardEventListener *>::iterator it = keyboardListeners.begin(); it != keyboardListeners.end(); ++it)
                {
                    (*it)->KeyReleased(kbe);
                }
            }
            break;
        case SDL_MOUSEBUTTONDOWN:
            {
                PointerButton pb;
                switch (event->button.button)
                {
                    case SDL_BUTTON_LEFT:
                        pb = PB_PRIMARY;
                        break;
                    case SDL_BUTTON_MIDDLE:
                        pb = PB_TERTIARY;
                        break;
                    case SDL_BUTTON_RIGHT:
                        pb = PB_SECONDARY;
                        break;
                    default:
                        return;
                }
                xPos = event->button.x / video->GetScaling();
                yPos = event->button.y / video->GetScaling();
                PointerButtonEvent pbe(pb, xPos, yPos);
                for (std::list<PointerButtonEventListener *>::iterator it = pointerButtonListeners.begin(); it != pointerButtonListeners.end(); ++it)
                {
                    (*it)->PointerButtonPressed(pbe);
                }
            }
            break;
        case SDL_MOUSEBUTTONUP:
            {
                PointerButton pb;
                switch (event->button.button)
                {
                    case SDL_BUTTON_LEFT:
                        pb = PB_PRIMARY;
                        break;
                    case SDL_BUTTON_MIDDLE:
                        pb = PB_TERTIARY;
                        break;
                    case SDL_BUTTON_RIGHT:
                        pb = PB_SECONDARY;
                        break;
                    default:
                        return;
                }
                xPos = event->button.x / video->GetScaling();
                yPos = event->button.y / video->GetScaling();
                PointerButtonEvent pbe(pb, xPos, yPos);
                for (std::list<PointerButtonEventListener *>::iterator it = pointerButtonListeners.begin(); it != pointerButtonListeners.end(); ++it)
                {
                    (*it)->PointerButtonReleased(pbe);
                }
            }
            break;
        case SDL_MOUSEMOTION:
            {
                xPos = event->button.x / video->GetScaling();
                yPos = event->button.y / video->GetScaling();
                PointerMotionEvent pme(xPos, yPos);
                for (std::list<PointerMotionEventListener *>::iterator it = pointerMotionListeners.begin(); it != pointerMotionListeners.end(); ++it)
                {
                    (*it)->PointerMoved(pme);
                }
            }
            break;
        case SDL_JOYAXISMOTION:
            if (event->jaxis.which == 0)
            {
                if (event->jaxis.axis == 0)
                {
                    xMove = event->jaxis.value / JOYSTICK_AXIS_FACTOR;
                }
                else if (event->jaxis.axis == 1)
                {
                    yMove = event->jaxis.value / JOYSTICK_AXIS_FACTOR;
                }
            }
            break;
        case SDL_JOYBUTTONDOWN:
            if (event->jbutton.which == 0)
            {
            }
            break;
        case SDL_JOYBUTTONUP:
            if (event->jbutton.which == 0)
            {
            }
            break;
        case SDL_USEREVENT:
            {
                // timer event
                clock->CancelTimer((unsigned long)event->user.data1);
                TimerEvent te((unsigned long)event->user.data1);
                for (std::list<TimerEventListener *>::iterator it = timerListeners.begin(); it != timerListeners.end(); ++it)
                {
                    (*it)->TimerExpired(te);
                }
            }
            break;
        default:
            break;
    }
}

void
SDL_Toolkit::UpdatePointer()
{
    if (xMove)
    {
        xPos = xPos + xMove * JOYSTICK_SPEED;
        if (xPos < 0)
        {
            xPos = 0;
        }
        else if (xPos > VIDEO_WIDTH)
        {
            xPos = VIDEO_WIDTH;
        }
    }
    if (yMove)
    {
        yPos = yPos + yMove * JOYSTICK_SPEED;
        if (yPos < 0)
        {
            yPos = 0;
        }
        else if (yPos > VIDEO_HEIGHT)
        {
            yPos = VIDEO_HEIGHT;
        }
    }
    if (xMove || yMove)
    {
        PointerMotionEvent pme(xPos, yPos);
        for (std::list<PointerMotionEventListener *>::iterator it = pointerMotionListeners.begin(); it != pointerMotionListeners.end(); ++it)
        {
            (*it)->PointerMoved(pme);
        }
    }
}

void
SDL_Toolkit::PollEvents()
{
    SDL_Event event;
    while (SDL_PollEvent(&event))
    {
        HandleEvent(&event);
    }
    UpdatePointer();
}

void
SDL_Toolkit::PollEventLoop()
{
    int currentTicks;
    int previousTicks = SDL_GetTicks();

    eventLoopRunning = true;
    while (eventLoopRunning)
    {
        PollEvents();
        currentTicks = SDL_GetTicks();
        LoopEvent le(currentTicks - previousTicks);
        for (std::list<LoopEventListener *>::iterator it = loopListeners.begin(); it != loopListeners.end(); ++it)
        {
            (*it)->LoopComplete(le);
        }
        previousTicks = currentTicks;
    }
}

void
SDL_Toolkit::WaitEvents()
{
    SDL_Event event;
    if (SDL_WaitEvent(&event))
    {
        HandleEvent(&event);
    }
    UpdatePointer();
}

void
SDL_Toolkit::WaitEventLoop()
{
    int currentTicks;
    int previousTicks = SDL_GetTicks();

    eventLoopRunning = true;
    while (eventLoopRunning)
    {
        WaitEvents();
        currentTicks = SDL_GetTicks();
        LoopEvent le(currentTicks - previousTicks);
        for (std::list<LoopEventListener *>::iterator it = loopListeners.begin(); it != loopListeners.end(); ++it)
        {
            (*it)->LoopComplete(le);
        }
        previousTicks = currentTicks;
    }
}

void
SDL_Toolkit::ClearEvents()
{
    SDL_Event event;
    while (SDL_PollEvent(&event))
    {
        // nothing
    }
}

void
SDL_Toolkit::GetPointerPosition(int *x, int *y)
{
    SDL_GetMouseState(x, y);
}

void
SDL_Toolkit::SetPointerPosition(int x, int y)
{
    int scaling = video->GetScaling();
    SDL_WarpMouse(x * scaling, y * scaling);
}
