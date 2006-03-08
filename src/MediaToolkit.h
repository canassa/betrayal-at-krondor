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

#ifndef MEDIA_TOOLKIT_H
#define MEDIA_TOOLKIT_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <list>

#include "Clock.h"
#include "EventListener.h"
#include "Video.h"

class MediaToolkit {
  protected:
    Clock *clock;
    Video *video;
    bool eventLoopRunning;
    std::list<KeyboardEventListener *> keyboardListeners;
    std::list<MouseButtonEventListener *> mouseButtonListeners;
    std::list<MouseMotionEventListener *> mouseMotionListeners;
    std::list<UpdateEventListener *> updateListeners;
  public:
    MediaToolkit();
    virtual ~MediaToolkit();
    Clock* GetClock() const;
    Video* GetVideo() const;
    void AddKeyboardListener(KeyboardEventListener *kel);
    void RemoveKeyboardListener(KeyboardEventListener *kel);
    void AddMouseButtonListener(MouseButtonEventListener *mbel);
    void RemoveMouseButtonListener(MouseButtonEventListener *mbel);
    void AddMouseMotionListener(MouseMotionEventListener *mmel);
    void RemoveMouseMotionListener(MouseMotionEventListener *mmel);
    void AddUpdateListener(UpdateEventListener *uel);
    void RemoveUpdateListener(UpdateEventListener *uel);
    void TerminateEventLoop();
    virtual void PollEventLoop() = 0;
    virtual void WaitEventLoop() = 0;
    virtual void ClearEvents() = 0;
    virtual void GetMousePosition(int *x, int *y) = 0;
};

#endif
