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

#ifndef GAME_DATA_H
#define GAME_DATA_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "FileBuffer.h"

class GameData {
  private:
    std::string name;
    unsigned int xpos;
    unsigned int ypos;
    unsigned int zone;
    unsigned int xcell;
    unsigned int ycell;
    unsigned int xloc;
    unsigned int yloc;
    unsigned int orientation;
    std::string member[6];
  public:
    GameData();
    virtual ~GameData();
    std::string& GetName();
    unsigned int GetXPos() const;
    unsigned int GetYPos() const;
    unsigned int GetZone() const;
    unsigned int GetXCell() const;
    unsigned int GetYCell() const;
    unsigned int GetXLoc() const;
    unsigned int GetYLoc() const;
    unsigned int GetOrientation() const;
    std::string& GetMember(const unsigned int n);
    void Load(FileBuffer *buffer);
};

#endif
