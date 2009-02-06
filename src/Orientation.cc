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
 * Copyright (C) 2005-2009 Guido de Jong <guidoj@users.sf.net>
 */

#include "Orientation.h"

Orientation::Orientation(const int head)
: heading(head)
{
}

Orientation::~Orientation()
{
}

int Orientation::GetHeading() const
{
    return heading.Get();
}

void Orientation::SetHeading(const int head)
{
    heading = Angle(head);
}

const Angle & Orientation::GetAngle() const
{
    return heading;
}

float Orientation::GetCos() const
{
    return heading.GetCos();
}

float Orientation::GetSin() const
{
    return heading.GetSin();
}

void Orientation::AdjustHeading(const int delta)
{
    heading += Angle(delta);
}
