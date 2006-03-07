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

#include "Event.h"

Event::Event() 
{
}

Event::~Event()
{
}

KeyboardEvent::KeyboardEvent(const Key k)
: key(k)
{
}

KeyboardEvent::~KeyboardEvent()
{
}

Key
KeyboardEvent::GetKey() const
{
  return key;
}

MouseButtonEvent::MouseButtonEvent(const MouseButton b, const int x, const int y)
:button(b)
, xpos(x)
, ypos(y)
{
}

MouseButtonEvent::~MouseButtonEvent()
{
}

MouseButton
MouseButtonEvent::GetButton() const
{
  return button;
}

int
MouseButtonEvent::GetXPos() const
{
  return xpos;
}

int
MouseButtonEvent::GetYPos() const
{
  return ypos;
}

MouseMotionEvent::MouseMotionEvent(const int x, const int y)
: xpos(x)
, ypos(y)
{
}

MouseMotionEvent::~MouseMotionEvent()
{
}

int
MouseMotionEvent::GetXPos() const
{
  return xpos;
}

int
MouseMotionEvent::GetYPos() const
{
  return ypos;
}

UpdateEvent::UpdateEvent(const int t)
: ticks(t)
{
}

UpdateEvent::~UpdateEvent()
{
}

int
UpdateEvent::GetTicks() const
{
  return ticks;
}

ActionEvent::ActionEvent(const int a)
: action(a)
{
}

ActionEvent::~ActionEvent()
{
}

int
ActionEvent::GetAction() const
{
  return action;
}
