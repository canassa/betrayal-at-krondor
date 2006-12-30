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

unsigned int
GenericObject::GetDistance(const Vector2D &p)
{
  return (pos - p).GetRhoSqr();
}

int
GenericObject::GetAngle(const int heading) const
{
  return ((int)(pos.GetTheta() * (float)(1 << MAX_HEADING_BITS) / PI2) - heading) & ~(1 << MAX_HEADING_BITS);
}
