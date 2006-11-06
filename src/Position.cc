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

#include "Position.h"

static const int CELL_SIZE = 64000;

Position::Position(const int x, const int y)
: xCell(x / CELL_SIZE)
, yCell(y / CELL_SIZE)
, xPos(x)
, yPos(y)
{
}

Position::Position(const int xc, const int yc, const int xp, const int yp)
: xCell(xc)
, yCell(yc)
, xPos(xp)
, yPos(yp)
{
}

Position::~Position()
{
}

int
Position::GetXCell() const
{
  return xCell;
}

int
Position::GetYCell() const
{
  return yCell;
}

int
Position::GetXPos() const
{
  return xPos;
}

int
Position::GetYPos() const
{
  return yPos;
}

void
Position::SetPos(const int x, const int y)
{
  xPos = x;
  xCell = xPos / CELL_SIZE;
  yPos = y;
  yCell = yPos / CELL_SIZE;
}

void
Position::Adjust(const int deltaX, const int deltaY)
{
  xPos += deltaX;
  xCell = xPos / CELL_SIZE;
  yPos += deltaY;
  yCell = yPos / CELL_SIZE;
}
