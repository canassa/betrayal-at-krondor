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
 * Copyright (C) 2006 Guido de Jong <guidoj@users.sf.net>
 */

#include "Camera.h"

Camera::Camera(const int x, const int y, const int heading)
: position(x, y)
, orientation(heading)
{
}

Camera::~Camera()
{
}

Position&
Camera::GetPosition()
{
  return position;
}

int
Camera::GetXPos() const
{
  return position.GetXPos();
}

int
Camera::GetYPos() const
{
  return position.GetYPos();
}

void
Camera::SetPosition(const int x, const int y)
{
  position.SetPos(x, y);
  Notify();
}

Orientation&
Camera::GetOrientation()
{
  return orientation;
}

int
Camera::GetHeading() const
{
  return orientation.GetHeading();
}

void
Camera::SetHeading(const int heading)
{
  orientation.SetHeading(heading);
  Notify();
}

void
Camera::Move(const int delta)
{
  position.Adjust((int)((float)delta * orientation.GetSin()),
                  (int)((float)delta * orientation.GetCos()));
  Notify();
}

void
Camera::Turn(const int delta)
{
  orientation.AdjustHeading(delta);
  Notify();
}
