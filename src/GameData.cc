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

#include "Exception.h"
#include "GameData.h"

GameData::GameData()
: name("")
, xpos(0)
, ypos(0)
, xcell(0)
, ycell(0)
, xloc(0)
, yloc(0)
, orientation(0)
, memberName()
, memberData()
{
}

GameData::~GameData()
{
}

std::string&
GameData::GetName()
{
  return name;
}

unsigned int
GameData::GetXPos() const
{
  return xpos;
}

unsigned int
GameData::GetYPos() const
{
  return ypos;
}

unsigned int
GameData::GetZone() const
{
  return zone;
}

unsigned int
GameData::GetXCell() const
{
  return xcell;
}

unsigned int
GameData::GetYCell() const
{
  return ycell;
}

unsigned int
GameData::GetXLoc() const
{
  return xloc;
}

unsigned int
GameData::GetYLoc() const
{
  return yloc;
}

unsigned int
GameData::GetOrientation() const
{
  return orientation;
}

std::string&
GameData::GetMemberName(const unsigned int m)
{
  return memberName[m];
}

unsigned int
GameData::GetMemberData(const unsigned int m, const unsigned int i, const unsigned int j)
{
  return memberData[(m * 16 + i) * 5 + j];
}

void
GameData::Load(FileBuffer *buffer)
{
  try {
    name = buffer->GetString();
    buffer->Seek(90);
    buffer->Skip(16);
    ypos = buffer->GetUint32LE();
    xpos = buffer->GetUint32LE();
    buffer->Skip(4);
    zone = buffer->GetUint8();
    xcell = buffer->GetUint8();
    ycell = buffer->GetUint8();
    xloc = buffer->GetUint32LE();
    yloc = buffer->GetUint32LE();
    buffer->Skip(5);
    orientation = buffer->GetUint16LE();
    buffer->Skip(23);
    for (unsigned int m = 0; m < 6; m++) {
      memberName.push_back(buffer->GetString(10));
    }
    for (unsigned int m = 0; m < 6; m++) {
      buffer->Skip(8);
      for (unsigned int i = 0; i < 16; i++) {
        for (unsigned int j = 0; j < 5; j++) {
          memberData.push_back(buffer->GetUint8());
        }
      }
      buffer->Skip(7);
    }
  } catch (Exception &e) {
    e.Print("GameData::Load");
  }
}
