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

#ifndef POSITION_H
#define POSITION_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

static const int MOVE_SIZE     = 400;
static const int MOVE_FORWARD  = +1 * MOVE_SIZE;
static const int MOVE_BACKWARD = -1 * MOVE_SIZE;

class Position {
  private:
    int xCell;
    int yCell;
    int xPos;
    int yPos;
  public:
    Position(const int x, const int y);
    Position(const int xc, const int yc, const int xp, const int yp);
    ~Position();
    int GetXCell() const;
    int GetYCell() const;
    int GetXPos() const;
    int GetYPos() const;
    void SetPos(const int x, const int y);
    void Adjust(const int deltaX, const int deltaY);
};

#endif
