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

#include "Geometry.h"

Vector2D::Vector2D(const int x, const int y)
: xCoord(x)
, yCoord(y)
{
}

Vector2D::Vector2D(const Vector2D &p)
: xCoord(p.xCoord)
, yCoord(p.yCoord)
{
}

Vector2D::~Vector2D()
{
}

Vector2D&
Vector2D::operator=(const Vector2D &p)
{
  xCoord = p.xCoord;
  yCoord = p.yCoord;
  return *this;
}

bool
Vector2D::operator==(const Vector2D &p)
{
  return (xCoord == p.xCoord) && (yCoord == p.yCoord);
}

int
Vector2D::GetX() const
{
  return xCoord;
}

int
Vector2D::GetY() const
{
  return yCoord;
}

void
Vector2D::SetX(int x)
{
  xCoord = x;
}

void
Vector2D::SetY(int y)
{
  yCoord = y;
}

Vector3D::Vector3D(const int x, const int y, const int z)
: xCoord(x)
, yCoord(y)
, zCoord(z)
{
}

Vector3D::Vector3D(const Vector3D &p)
: xCoord(p.xCoord)
, yCoord(p.yCoord)
, zCoord(p.zCoord)
{
}

Vector3D::~Vector3D()
{
}

Vector3D&
Vector3D::operator=(const Vector3D &p)
{
  xCoord = p.xCoord;
  yCoord = p.yCoord;
  zCoord = p.zCoord;
  return *this;
}

bool
Vector3D::operator==(const Vector3D &p)
{
  return (xCoord == p.xCoord) && (yCoord == p.yCoord) && (zCoord == p.zCoord);
}

int
Vector3D::GetX() const
{
  return xCoord;
}

int
Vector3D::GetY() const
{
  return yCoord;
}

int
Vector3D::GetZ() const
{
  return zCoord;
}

void
Vector3D::SetX(int x)
{
  xCoord = x;
}

void
Vector3D::SetY(int y)
{
  yCoord = y;
}

void
Vector3D::SetZ(int z)
{
  zCoord = z;
}

Rectangle2D::Rectangle2D(const int x, const int y, const int w, const int h)
: xpos(x)
, ypos(y)
, width(w)
, height(h)
{
}

Rectangle2D::Rectangle2D(const Rectangle2D &r)
: xpos(r.xpos)
, ypos(r.ypos)
, width(r.width)
, height(r.height)
{
}

Rectangle2D::~Rectangle2D()
{
}

Rectangle2D&
Rectangle2D::operator=(const Rectangle2D &r)
{
  xpos = r.xpos;
  ypos = r.ypos;
  width = r.width;
  height = r.height;
  return *this;
}

bool
Rectangle2D::operator==(const Rectangle2D &r)
{
  return (xpos == r.xpos) && (ypos == r.ypos) && (width == r.width) && (height == r.height);
}

int
Rectangle2D::GetXPos() const
{
  return xpos;
}

int
Rectangle2D::GetYPos() const
{
  return ypos;
}

int
Rectangle2D::GetXCenter() const
{
  return xpos + width / 2;
}

int
Rectangle2D::GetYCenter() const
{
  return ypos + height / 2;
}

int
Rectangle2D::GetWidth() const
{
  return width;
}

int
Rectangle2D::GetHeight() const
{
  return height;
}

void
Rectangle2D::SetXPos(int x)
{
  xpos = x;
}

void
Rectangle2D::SetYPos(int y)
{
  ypos = y;
}

void
Rectangle2D::SetWidth(int w)
{
  width = w;
}

void
Rectangle2D::SetHeight(int h)
{
  height = h;
}

bool
Rectangle2D::IsInside(const Vector2D &p)
{
  return ((xpos <= p.GetX()) && (p.GetX() < xpos + width) &&
          (ypos <= p.GetY()) && (p.GetY() < ypos + height));
}
