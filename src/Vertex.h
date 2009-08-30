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

#ifndef VERTEX_H
#define VERTEX_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Geometry.h"

static const unsigned int MAX_VIEW_DISTANCE = 32000;
static const unsigned int MIN_VIEW_DISTANCE = 32;

static const int ANGLE_OF_VIEW = 12;
static const int ANGLE_VIEW_DISTANCE = MAX_VIEW_DISTANCE / 2;

static const int TERRAIN_HEIGHT = 38;

class Vertex
{
    protected:
        Vector3D pos;
        Vector3D relpos;
        Angle angle;
        unsigned int distance;
        float distanceFactor;
    public:
        Vertex();
        Vertex ( const Vector3D &p );
        virtual ~Vertex();
        Vertex& operator= ( const Vertex &v );
        const Vector3D& GetPosition() const;
        const Vector3D& GetRelativePosition() const;
        int GetAngle() const;
        unsigned int GetDistance() const;
        float GetDistanceFactor() const;
        Vector2D ToFirstPerson ( int w, int h, const Angle & heading );
        Vector2D ToTopDown ( int w, int h );
        void CalculateRelativePosition ( const Vector2D &p );
        bool IsInView ( const Angle & heading );
};

#endif
