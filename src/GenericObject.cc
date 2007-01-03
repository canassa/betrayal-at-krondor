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

#include "GenericObject.h"
#include "Orientation.h"

GenericObject::GenericObject(const Vector2D &p, int w, int h)
: pos(p)
, relpos(0, 0)
, width(w)
, height(h)
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

void
GenericObject::CalculateRelativePosition(const Vector2D &p)
{
  relpos = pos - p;
}

unsigned int
GenericObject::GetDistance() const
{
  return relpos.GetRhoSqr();
}

int
GenericObject::GetAngle(const int heading) const
{
  return ((int)((PI2 + relpos.GetTheta()) * (float)ANGLE_SIZE / PI2) - heading) & ANGLE_MASK;
}
