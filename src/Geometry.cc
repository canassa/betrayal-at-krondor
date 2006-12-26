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

Vector2D&
Vector2D::operator+=(const Vector2D &p)
{
  xCoord += p.xCoord;
  yCoord += p.yCoord;
  return *this;
}

Vector2D&
Vector2D::operator-=(const Vector2D &p)
{
  xCoord -= p.xCoord;
  yCoord -= p.yCoord;
  return *this;
}

Vector2D&
Vector2D::operator*=(const int f)
{
  xCoord *= f;
  yCoord *= f;
  return *this;
}

Vector2D&
Vector2D::operator/=(const int f)
{
  xCoord /= f;
  yCoord /= f;
  return *this;
}

Vector2D
Vector2D::operator+(const Vector2D &p)
{
  return Vector2D(xCoord + p.xCoord, yCoord + p.yCoord);
}

Vector2D
Vector2D::operator-(const Vector2D &p)
{
  return Vector2D(xCoord - p.xCoord, yCoord - p.yCoord);
}

Vector2D
Vector2D::operator*(const int f)
{
  return Vector2D(xCoord * f, yCoord * f);
}

Vector2D
Vector2D::operator/(const int f)
{
  return Vector2D(xCoord / f, yCoord / f);
}

bool
Vector2D::operator==(const Vector2D &p)
{
  return (xCoord == p.xCoord) && (yCoord == p.yCoord);
}

bool
Vector2D::operator!=(const Vector2D &p)
{
  return (xCoord != p.xCoord) || (yCoord != p.yCoord);
}

bool
Vector2D::operator<(const Vector2D &p)
{
  return (xCoord < p.xCoord) ||
         ((xCoord == p.xCoord) && (yCoord < p.yCoord));
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

unsigned int
Vector2D::GetRhoSqr() const
{
  return (unsigned int)((xCoord * xCoord) + (yCoord * yCoord));
}

float
Vector2D::GetTheta() const
{
  return atan(yCoord / xCoord);
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

Vector3D&
Vector3D::operator+=(const Vector3D &p)
{
  xCoord += p.xCoord;
  yCoord += p.yCoord;
  zCoord += p.zCoord;
  return *this;
}

Vector3D&
Vector3D::operator-=(const Vector3D &p)
{
  xCoord -= p.xCoord;
  yCoord -= p.yCoord;
  zCoord -= p.zCoord;
  return *this;
}

Vector3D&
Vector3D::operator*=(const int f)
{
  xCoord *= f;
  yCoord *= f;
  zCoord *= f;
  return *this;
}

Vector3D&
Vector3D::operator/=(const int f)
{
  xCoord /= f;
  yCoord /= f;
  zCoord /= f;
  return *this;
}

Vector3D
Vector3D::operator+(const Vector3D &p)
{
  return Vector3D(xCoord + p.xCoord, yCoord + p.yCoord, zCoord + p.zCoord);
}

Vector3D
Vector3D::operator-(const Vector3D &p)
{
  return Vector3D(xCoord - p.xCoord, yCoord - p.yCoord, zCoord - p.zCoord);
}

Vector3D
Vector3D::operator*(const int f)
{
  return Vector3D(xCoord * f, yCoord * f, zCoord * f);
}

Vector3D
Vector3D::operator/(const int f)
{
  return Vector3D(xCoord / f, yCoord / f, zCoord / f);
}

bool
Vector3D::operator==(const Vector3D &p)
{
  return (xCoord == p.xCoord) && (yCoord == p.yCoord) && (zCoord == p.zCoord);
}

bool
Vector3D::operator!=(const Vector3D &p)
{
  return (xCoord != p.xCoord) || (yCoord != p.yCoord) || (zCoord != p.zCoord);
}

bool
Vector3D::operator<(const Vector3D &p)
{
  return (xCoord < p.xCoord) ||
         ((xCoord == p.xCoord) && ((yCoord < p.yCoord) ||
                                   ((yCoord == p.yCoord) && (zCoord < p.zCoord))));
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

unsigned int
Vector3D::GetRhoSqr() const
{
  return (unsigned int)((xCoord * xCoord) + (yCoord * yCoord) + (zCoord * zCoord));
}

float
Vector3D::GetTheta() const
{
  return atan(yCoord / xCoord);
}


Rectangle::Rectangle(const int x, const int y, const int w, const int h)
: xpos(x)
, ypos(y)
, width(w)
, height(h)
{
}

Rectangle::Rectangle(const Rectangle &r)
: xpos(r.xpos)
, ypos(r.ypos)
, width(r.width)
, height(r.height)
{
}

Rectangle::~Rectangle()
{
}

Rectangle&
Rectangle::operator=(const Rectangle &r)
{
  xpos = r.xpos;
  ypos = r.ypos;
  width = r.width;
  height = r.height;
  return *this;
}

bool
Rectangle::operator==(const Rectangle &r)
{
  return (xpos == r.xpos) && (ypos == r.ypos) && (width == r.width) && (height == r.height);
}

bool
Rectangle::operator!=(const Rectangle &r)
{
  return (xpos != r.xpos) || (ypos != r.ypos) || (width != r.width) || (height != r.height);
}

int
Rectangle::GetXPos() const
{
  return xpos;
}

int
Rectangle::GetYPos() const
{
  return ypos;
}

int
Rectangle::GetXCenter() const
{
  return xpos + width / 2;
}

int
Rectangle::GetYCenter() const
{
  return ypos + height / 2;
}

int
Rectangle::GetWidth() const
{
  return width;
}

int
Rectangle::GetHeight() const
{
  return height;
}

void
Rectangle::SetXPos(int x)
{
  xpos = x;
}

void
Rectangle::SetYPos(int y)
{
  ypos = y;
}

void
Rectangle::SetWidth(int w)
{
  width = w;
}

void
Rectangle::SetHeight(int h)
{
  height = h;
}

bool
Rectangle::IsInside(const Vector2D &p)
{
  return ((xpos <= p.GetX()) && (p.GetX() < xpos + width) &&
          (ypos <= p.GetY()) && (p.GetY() < ypos + height));
}
