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
 * Copyright (C) 2005-2007  Guido de Jong <guidoj@users.sf.net>
 */

#include "Orientation.h"
#include "Position.h"
#include "TileWorldResource.h"

Position::Position(const Vector2D &p)
        : pos(p)
        , cell(p.GetX() / TILE_SIZE, p.GetY() / TILE_SIZE)
{}

Position::Position(const Vector2D &p, const Vector2D &c)
        : pos(p)
        , cell(c)
{}

Position::~Position()
{}

Vector2D &
Position::GetCell()
{
    return cell;
}

Vector2D &
Position::GetPos()
{
    return pos;
}

void
Position::SetPos(const Vector2D &p)
{
    pos = p;
    cell = pos / TILE_SIZE;
}

void
Position::Adjust(const Vector2D &delta)
{
    pos += delta;
    cell = pos / TILE_SIZE;
}

void
Position::Adjust(const int deltaX, const int deltaY)
{
    pos += Vector2D(deltaX, deltaY);
    cell = pos / TILE_SIZE;
}
