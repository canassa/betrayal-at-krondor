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

#include <cstdio>
#include <cstdlib>
#include "Geometry.h"
#include "Orientation.h"
#include "Vertex.h"

Vertex::Vertex()
        : pos(0, 0, 0)
        , relpos(0, 0, 0)
        , angle(0)
        , distance(0)
        , distanceFactor(1.0)
{
}

Vertex::Vertex(const Vector3D &p)
        : pos(p)
        , relpos(0, 0, 0)
        , angle(0)
        , distance(0)
        , distanceFactor(1.0)
{
}

Vertex::~Vertex()
{
}

Vertex& Vertex::operator= ( const Vertex &v )
{
    pos = v.pos;
    relpos = v.relpos;
    angle = v.angle;
    distance = v.distance;
    distanceFactor = v.distanceFactor;
    return *this;
}

const Vector3D& Vertex::GetPosition() const
{
    return pos;
}

const Vector3D& Vertex::GetRelativePosition() const
{
    return relpos;
}

int Vertex::GetAngle() const
{
    return angle.Get();
}

unsigned int Vertex::GetDistance() const
{
    return distance;
}

float Vertex::GetDistanceFactor() const
{
    return distanceFactor;
}

Vector2D Vertex::ToFirstPerson(int w, int h, const Angle &heading)
{
    static const Angle ANGLE_AOV = Angle(2 * ANGLE_OF_VIEW + 1);
    int x = (int)((float)w * (float)Angle(angle - heading + ANGLE_OF_VIEW - 1).Get() / (float)ANGLE_AOV.Get());
    int y = h - (int)((float)TERRAIN_HEIGHT * (1.0 - distanceFactor) + ((float)relpos.GetZ() * distanceFactor));
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
    angle = Angle((ANGLE_SIZE / 4) - relpos.GetTheta());
    distance = relpos.GetRho();
    distanceFactor = 2.0 * ((float)MAX_VIEW_DISTANCE / ((float)MAX_VIEW_DISTANCE + (float)distance)) - 1.0;
    //distanceFactor = 1.0 - ((float)MAX_VIEW_DISTANCE / ((float)MAX_VIEW_DISTANCE + (float)distance));
}

void Vertex::CalculateRelativePosition(const Vertex &v)
{
    relpos = pos - v.GetPosition();
    relpos.SetX((int)((float)relpos.GetX() * distanceFactor + (float)v.GetRelativePosition().GetX()));
    relpos.SetY((int)((float)relpos.GetY() * distanceFactor + (float)v.GetRelativePosition().GetY()));
    angle = Angle((ANGLE_SIZE / 4) - relpos.GetTheta());
    distance = relpos.GetRho();
    distanceFactor = 2.0 * ((float)MAX_VIEW_DISTANCE / ((float)MAX_VIEW_DISTANCE + (float)distance)) - 1.0;
    //distanceFactor = 1.0 - ((float)MAX_VIEW_DISTANCE / ((float)MAX_VIEW_DISTANCE + (float)distance));
}

bool Vertex::IsInView(const Angle &heading)
{
    if ((distance > MAX_VIEW_DISTANCE) || (distance < MIN_VIEW_DISTANCE))
    {
        return false;
    }
    Angle a(angle - heading);
    return (((int)(ANGLE_SIZE - ANGLE_OF_VIEW) <= a.Get()) || (a.Get() <= (int)ANGLE_OF_VIEW)) ||
            (((WEST <= a.Get()) || (a.Get() <= EAST)) && (abs((int)((float)distance * a.GetSin())) < ANGLE_VIEW_DISTANCE));
/*    Orientation orient((angle.Get() - heading) & ANGLE_MASK);
    int orientHeading = orient.GetHeading();
    return (((int)(ANGLE_SIZE - ANGLE_OF_VIEW) <= orientHeading) || (orientHeading <= (int)ANGLE_OF_VIEW)) ||
            (((WEST <= orientHeading) || (orientHeading <= EAST)) && (abs((int)((float)distance * orient.GetSin())) < ANGLE_VIEW_DISTANCE));*/
}
