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

#ifndef EVENT_LISTENER_H
#define EVENT_LISTENER_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Event.h"

class KeyboardEventListener {
  public:
    KeyboardEventListener() {};
    virtual ~KeyboardEventListener() {};
    virtual void KeyPressed(const KeyboardEvent &kbe) = 0;
    virtual void KeyReleased(const KeyboardEvent &kbe) = 0;
};

class MouseButtonEventListener {
  public:
    MouseButtonEventListener() {};
    virtual ~MouseButtonEventListener() {};
    virtual void MouseButtonPressed(const MouseButtonEvent &mbe) = 0;
    virtual void MouseButtonReleased(const MouseButtonEvent &mbe) = 0;
};

class MouseMotionEventListener {
  public:
    MouseMotionEventListener() {};
    virtual ~MouseMotionEventListener() {};
    virtual void MouseMoved(const MouseMotionEvent &mme) = 0;
};

class TimerEventListener {
  public:
    TimerEventListener() {};
    virtual ~TimerEventListener() {};
    virtual void Update(const TimerEvent &te) = 0;
};

class UpdateEventListener {
  public:
    UpdateEventListener() {};
    virtual ~UpdateEventListener() {};
    virtual void Update(const UpdateEvent &ue) = 0;
};

class ActionEventListener {
  public:
    ActionEventListener() {};
    virtual ~ActionEventListener() {};
    virtual void ActionPerformed(const ActionEvent &ae) = 0;
};

#endif
