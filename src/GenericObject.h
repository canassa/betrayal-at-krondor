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

class GenericObject {
  private:
    Vector2D pos;
    Vector2D relpos;
    int width;
    int height;
  public:
    GenericObject(const Vector2D &p, int w, int h);
    virtual ~GenericObject();
    void CalculateRelativePosition(const Vector2D &p);
    unsigned int GetDistance() const;
    int GetAngle(const int heading) const;
    virtual void DrawFirstPerson() = 0;
    virtual void DrawTopDown() = 0;
};

#endif