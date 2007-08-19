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

#include "Orientation.h"

float Orientation::cosTbl[ANGLE_SIZE];
float Orientation::sinTbl[ANGLE_SIZE];

Orientation::Orientation(const int head)
        : heading(head)
{
    for (unsigned int i = 0; i < ANGLE_SIZE; i++)
    {
        cosTbl[i] = cos((float)i * PI2 / (float)ANGLE_SIZE);
        sinTbl[i] = sin((float)i * PI2 / (float)ANGLE_SIZE);
    }
}

Orientation::~Orientation()
{}

int
Orientation::GetHeading() const
{
    return heading;
}

void
Orientation::SetHeading(const int head)
{
    heading = head & ANGLE_MASK;
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
    heading &= ANGLE_MASK;
}
