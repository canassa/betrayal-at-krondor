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
 * Copyright (C) 2006 Guido de Jong <guidoj@users.sf.net>
 */

#ifndef GENERIC_OBJECT_H
#define GENERIC_OBJECT_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Geometry.h"

static const int ANGLE_OF_VIEW = 12;
static const unsigned int VIEW_DISTANCE = 32000;

static const int TERRAIN_HEIGHT = 38;

class GenericObject {
  protected:
    Vector2D pos;
    Vector2D relpos;
    int angle;
    unsigned int distance;
    int width;
    int height;
  public:
    GenericObject(const Vector2D &p, const int w, const int h);
    virtual ~GenericObject();
    Vector2D& GetPosition();
    Vector2D& GetRelativePosition();
    int GetAngle() const;
    unsigned int GetDistance() const;
    void CalculateRelativePosition(const Vector2D &p);
    virtual void DrawFirstPerson(const int x, const int y, const int w, const int h, const int heading) = 0;
    virtual void DrawTopDown() = 0;
};

#endif
