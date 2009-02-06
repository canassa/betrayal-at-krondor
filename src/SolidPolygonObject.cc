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

#include "MediaToolkit.h"
#include "SolidPolygonObject.h"

SolidPolygonObject::SolidPolygonObject(const Vector2D& p, const unsigned int c)
        : PolygonObject(p)
        , color(c)
{
}

SolidPolygonObject::~SolidPolygonObject()
{
}

void SolidPolygonObject::DrawFirstPerson(const int x, const int y, const int w, const int h, Camera *cam)
{
    for (unsigned int i = 0; i < vertices.size(); i++)
    {
        Vector2D v = vertices[i].ToFirstPerson(w, h, cam->GetAngle());
        xCoords[i] = x + v.GetX();
        yCoords[i] = y + v.GetY();
    }
    MediaToolkit::GetInstance()->GetVideo()->FillPolygon(xCoords, yCoords, vertices.size(), color);
}

void SolidPolygonObject::DrawTopDown()
{
}
