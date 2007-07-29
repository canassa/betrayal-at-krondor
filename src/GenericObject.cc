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
 * Copyright (C) 2007 Guido de Jong <guidoj@users.sf.net>
 */

#include "GenericObject.h"

GenericObject::GenericObject(const Vector2D &p)
: pos(p)
, relpos(0, 0)
, angle(0)
, distance(0)
{
}

GenericObject::~GenericObject()
{
}

Vector2D&
GenericObject::GetPosition()
{
  return pos;
}

Vector2D&
GenericObject::GetRelativePosition()
{
  return relpos;
}

int
GenericObject::GetAngle() const
{
  return angle;
}

unsigned int
GenericObject::GetDistance() const
{
  return distance;
}

void
GenericObject::CalculateRelativePosition(const Vector2D &p)
{
  relpos = pos - p;
  angle = (ANGLE_SIZE / 4 - relpos.GetTheta()) & ANGLE_MASK;
  distance = relpos.GetRho();
}
