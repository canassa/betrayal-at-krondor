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
 * Copyright (C) 2005-2006  Guido de Jong <guidoj@users.sf.net>
 */

#ifndef GEOMETRY_H
#define GEOMETRY_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

class Point2D {
  private:
    int xCoord;
    int yCoord;
  public:
    Point2D(const int x, const int y);
    Point2D(Point2D &p);
    virtual ~Point2D();
    Point2D& operator=(Point2D &p);
    bool operator==(Point2D &p);
    int GetX() const;
    int GetY() const;
    void SetX(int x);
    void SetY(int y);
};

class Point3D {
  private:
    int xCoord;
    int yCoord;
    int zCoord;
  public:
    Point3D(const int x, const int y, const int z);
    Point3D(Point3D &p);
    virtual ~Point3D();
    Point3D& operator=(Point3D &p);
    bool operator==(Point3D &p);
    int GetX() const;
    int GetY() const;
    int GetZ() const;
    void SetX(int x);
    void SetY(int y);
    void SetZ(int z);
};

class Rectangle2D {
  private:
    int xpos;
    int ypos;
    int width;
    int height;
  public:
    Rectangle2D(const int x, const int y, const int w, const int h);
    Rectangle2D(Rectangle2D &r);
    virtual ~Rectangle2D();
    Rectangle2D& operator=(Rectangle2D &r);
    bool operator==(Rectangle2D &r);
    int GetXPos() const;
    int GetYPos() const;
    int GetXCenter() const;
    int GetYCenter() const;
    int GetWidth() const;
    int GetHeight() const;
    void SetXPos(int x);
    void SetYPos(int x);
    void SetWidth(int w);
    void SetHeight(int h);
    bool IsInside(Point2D &p);
};

#endif
