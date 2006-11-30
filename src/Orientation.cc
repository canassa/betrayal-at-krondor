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

#include <cstdio>
#include <cmath>
#ifndef M_PIl
#define M_PIl 3.1415926535897932384626433832795029L
#endif

#include "Orientation.h"

float Orientation::cosTbl[1 << MAX_HEADING_BITS];
float Orientation::sinTbl[1 << MAX_HEADING_BITS];

Orientation::Orientation(const int head)
: heading(head)
{
  for (unsigned int i = 0; i < (1 << MAX_HEADING_BITS); i++) {
    cosTbl[i] = cos((float)i * M_PIl / (float)(1 << MAX_HEADING_BITS));
    sinTbl[i] = sin((float)i * M_PIl / (float)(1 << MAX_HEADING_BITS));
  }
}

Orientation::~Orientation()
{
}

int
Orientation::GetHeading() const
{
  return heading;
}

void
Orientation::SetHeading(const int head)
{
  heading = head & ~(1 << MAX_HEADING_BITS);
}

float
Orientation::GetCos() const
{
  return cosTbl[heading];
}

float
Orientation::GetSin() const
{
  return sinTbl[heading];
}

void
Orientation::AdjustHeading(const int delta)
{
  heading += delta;
  heading &= ~(-1 << MAX_HEADING_BITS);
}
