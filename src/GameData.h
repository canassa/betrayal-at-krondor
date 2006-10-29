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

#include <string>
#include <vector>

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
    unsigned int heading;
    std::vector<std::string> memberName;
    std::vector<unsigned int> memberData;
  public:
    GameData();
    virtual ~GameData();
    std::string& GetName();
    void SetName(const std::string& s);
    unsigned int GetXPos() const;
    void SetXPos(const unsigned int x);
    unsigned int GetYPos() const;
    void SetYPos(const unsigned int y);
    unsigned int GetZone() const;
    void SetZone(const unsigned int z);
    unsigned int GetXCell() const;
    void SetXCell(const unsigned int x);
    unsigned int GetYCell() const;
    void SetYCell(const unsigned int y);
    unsigned int GetXLoc() const;
    void SetXLoc(const unsigned int x);
    unsigned int GetYLoc() const;
    void SetYLoc(const unsigned int y);
    unsigned int GetHeading() const;
    void SetHeading(const unsigned int h);
    std::string& GetMemberName(const unsigned int m);
    void SetMemberName(const unsigned int m, const std::string& s);
    unsigned int GetMemberData(const unsigned int m, const unsigned int i, const unsigned int j);
    void SetMemberData(const unsigned int m, const unsigned int i, const unsigned int j, const unsigned int v);
    void Load(FileBuffer *buffer);
    void Save(FileBuffer *buffer);
};

#endif
