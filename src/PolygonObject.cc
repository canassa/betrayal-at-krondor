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
 * Copyright (C) 2007-2009 Guido de Jong <guidoj@users.sf.net>
 */

#include "PolygonObject.h"

PolygonObject::PolygonObject(const Vector2D& p)
    : GenericObject(p)
    , vertices()
    , xCoords(0)
    , yCoords(0)
{
}

PolygonObject::~PolygonObject()
{
    if (xCoords != 0)
    {
        delete xCoords;
    }
    if (yCoords != 0)
    {
        delete yCoords;
    }
    vertices.clear();
}

void PolygonObject::AddVertex(const Vertex& v)
{
    vertices.push_back(v);
    if (xCoords != 0)
    {
        delete xCoords;
    }
    if (yCoords != 0)
    {
        delete yCoords;
    }
    xCoords = new int[vertices.size()];
    yCoords = new int[vertices.size()];
}

Vertex& PolygonObject::GetVertex(const unsigned int i)
{
    return vertices[i];
}

unsigned int PolygonObject::GetNumVertices()
{
    return vertices.size();
}

void PolygonObject::CalculateRelativePosition(const Vector2D & p)
{
    pos.CalculateRelativePosition(p);
    for (std::vector<Vertex>::iterator it = vertices.begin(); it != vertices.end(); ++it)
    {
        it->CalculateRelativePosition(pos);
    }
}

bool PolygonObject::IsInView(const Angle & heading, unsigned int & distance)
{
    if (pos.IsInView(heading))
    {
        distance = pos.GetDistance();
        return true;
    }
    for (std::vector<Vertex>::iterator it = vertices.begin(); it != vertices.end(); ++it)
    {
        if (it->IsInView(heading))
        {
            distance = it->GetDistance();
            return true;
        }
    }
    return false;
}
