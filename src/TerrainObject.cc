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

#include "TerrainObject.h"

TerrainObject::TerrainObject()
        : GenericObject()
        , vertices()
{}

TerrainObject::~TerrainObject()
{}

void TerrainObject::AddVertex(const Vertex& v)
{
    vertices.push_back(v);
}

void TerrainObject::CalculateRelativePosition(const Vector2D& p)
{
    for (std::vector<Vertex>::iterator it = vertices.begin(); it != vertices.end(); ++it)
    {
        it->CalculateRelativePosition(p);
    }
}

int TerrainObject::GetAngle()
{
    int sum = 0;
    for (std::vector<Vertex>::iterator it = vertices.begin(); it != vertices.end(); ++it)
    {
        sum += it->GetAngle();
    }
    return sum / vertices.size();
}

unsigned int TerrainObject::GetDistance()
{
    unsigned int sum = 0;
    for (std::vector<Vertex>::iterator it = vertices.begin(); it != vertices.end(); ++it)
    {
        sum += it->GetDistance();
    }
    return sum / vertices.size();
}

void TerrainObject::DrawFirstPerson(const int x, const int y, const int w, const int h, const int heading)
{
    if (x && y && w && h && heading);
}

void TerrainObject::DrawTopDown()
{
}
