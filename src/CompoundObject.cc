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
 * Copyright (C) 2007-2008 Guido de Jong <guidoj@users.sf.net>
 */

#include "CompoundObject.h"

CompoundObject::CompoundObject(const Vector2D& p)
    : GenericObject(p)
    , polygons()
{
}

CompoundObject::~CompoundObject()
{
    for (std::vector<PolygonObject *>::iterator it = polygons.begin(); it != polygons.end(); ++it)
    {
        delete (*it);
    }
    polygons.clear();
}

void CompoundObject::AddPolygon(PolygonObject *obj)
{
    polygons.push_back(obj);
}

void CompoundObject::CalculateRelativePosition(const Vector2D & p)
{
    pos.CalculateRelativePosition(p);
    for (std::vector<PolygonObject *>::iterator it = polygons.begin(); it != polygons.end(); ++it)
    {
        (*it)->CalculateRelativePosition(p);
    }
}

bool CompoundObject::IsInView(const Angle & heading, unsigned int & distance)
{
    if (pos.IsInView(heading))
    {
        distance = pos.GetDistance();
        return true;
    }
    for (std::vector<PolygonObject *>::iterator it = polygons.begin(); it != polygons.end(); ++it)
    {
        if ((*it)->IsInView(heading, distance))
        {
            return true;
        }
    }
    return false;
}

void CompoundObject::DrawFirstPerson(const int x, const int y, const int w, const int h, Camera *cam)
{
    for (std::vector<PolygonObject *>::iterator it = polygons.begin(); it != polygons.end(); ++it)
    {
        (*it)->DrawFirstPerson(x, y, w, h, cam);
    }
}

void CompoundObject::DrawTopDown()
{
}
