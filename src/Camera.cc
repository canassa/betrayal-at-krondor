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
: xpos(x)
, ypos(y)
, orientation(heading)
{
}

Camera::~Camera()
{
}

void
Camera::GetPosition(int &x, int &y) const
{
  x = xpos;
  y = ypos;
}

void
Camera::SetPosition(const int x, const int y)
{
  xpos = x;
  ypos = y;
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
}

void
Camera::Turn(const int delta)
{
  orientation.AdjustHeading(delta);
}
