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

#include "Vertex.h"

Vertex::Vertex()
        : pos(0, 0, 0)
        , relpos(0, 0, 0)
        , angle(0)
        , distance(0)
        , distanceFactor(1.0)
{}

Vertex::Vertex(const Vector3D &p)
        : pos(p)
        , relpos(0, 0, 0)
        , angle(0)
        , distance(0)
        , distanceFactor(1.0)
{}

Vertex::~Vertex()
{}

Vertex& Vertex::operator= ( const Vertex &v )
{
    pos = v.pos;
    relpos = v.relpos;
    angle = v.angle;
    distance = v.distance;
    distanceFactor = v.distanceFactor;
    return *this;
}

Vector3D& Vertex::GetPosition()
{
    return pos;
}

Vector3D& Vertex::GetRelativePosition()
{
    return relpos;
}

int Vertex::GetAngle() const
{
    return angle;
}

unsigned int Vertex::GetDistance() const
{
    return distance;
}

float Vertex::GetDistanceFactor() const
{
    return distanceFactor;
}

Vector2D Vertex::ToFirstPerson(int w, int h, int heading)
{
    int x = (int)((float)(((angle - heading + ANGLE_OF_VIEW - 1) & ANGLE_MASK) * w) / (float)(2 * ANGLE_OF_VIEW + 1));
    int y = h - (int)((float)TERRAIN_HEIGHT * (1.0 - distanceFactor));
    return Vector2D(x, y);
}

Vector2D Vertex::ToTopDown(int , int )
{
    // TODO
    return Vector2D(0, 0);
}

void Vertex::CalculateRelativePosition(const Vector2D &p)
{
    relpos = pos - p;
    angle = (ANGLE_SIZE / 4 - relpos.GetTheta()) & ANGLE_MASK;
    distance = relpos.GetRho();
    distanceFactor = 2.0 * (((float)VIEW_DISTANCE / ((float)VIEW_DISTANCE + (float)distance)) - 0.5);
}
