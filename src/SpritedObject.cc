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

#include "Defines.h"
#include "SpritedObject.h"

SpritedObject::SpritedObject(const Vector2D &p, Image *img)
        : GenericObject()
        , vertex(p)
        , sprite(img)
{}

SpritedObject::~SpritedObject()
{}

int
SpritedObject::GetAngle()
{
    return vertex.GetAngle();
}

unsigned int
SpritedObject::GetDistance()
{
    return vertex.GetDistance();
}

void
SpritedObject::CalculateRelativePosition(const Vector2D &p)
{
    vertex.CalculateRelativePosition(p);
}

void
SpritedObject::DrawFirstPerson(const int x, const int y, const int w, const int h, const int heading)
{
    Image *image = new Image((int)((float)sprite->GetWidth() * vertex.GetDistanceFactor()), (int)((float)sprite->GetHeight() * vertex.GetDistanceFactor()), sprite);
    int xx = (int)((float)(((vertex.GetAngle() - heading + ANGLE_OF_VIEW - 1) & ANGLE_MASK) * w) / (float)(2 * ANGLE_OF_VIEW + 1));
    int yy = h - (int)((float)TERRAIN_HEIGHT * (1.0 - vertex.GetDistanceFactor()));
    int ww = MIN(image->GetWidth(), w - xx);
    int hh = image->GetHeight();
    image->Draw(x + xx, y + yy - hh, 0, 0, ww, hh, 0);
    delete image;
}

void
SpritedObject::DrawTopDown()
{}
