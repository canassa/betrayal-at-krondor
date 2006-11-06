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
#include "GameResource.h"

GameResource::GameResource()
: game(0)
, xpos(0)
, ypos(0)
, xcell(0)
, ycell(0)
, xloc(0)
, yloc(0)
, heading(0)
, memberName()
, memberData()
, activeMember()
{
}

GameResource::~GameResource()
{
}

Game *
GameResource::GetGame()
{
  return game;
}

void
GameResource::SetGame(Game *g)
{
  game = g;
}

unsigned int
GameResource::GetXPos() const
{
  return xpos;
}

void
GameResource::SetXPos(const unsigned int x)
{
  xpos = x;
}

unsigned int
GameResource::GetYPos() const
{
  return ypos;
}

void
GameResource::SetYPos(const unsigned int y)
{
  ypos = y;
}

unsigned int
GameResource::GetZone() const
{
  return zone;
}

void
GameResource::SetZone(const unsigned int z)
{
  zone = z;
}

unsigned int
GameResource::GetXCell() const
{
  return xcell;
}

void
GameResource::SetXCell(const unsigned int x)
{
  xcell = x;
}

unsigned int
GameResource::GetYCell() const
{
  return ycell;
}

void
GameResource::SetYCell(const unsigned int y)
{
  ycell = y;
}

unsigned int
GameResource::GetXLoc() const
{
  return xloc;
}

void
GameResource::SetXLoc(const unsigned int x)
{
  xloc = x;
}

unsigned int
GameResource::GetYLoc() const
{
  return yloc;
}

void
GameResource::SetYLoc(const unsigned int y)
{
  yloc = y;
}

unsigned int
GameResource::GetHeading() const
{
  return heading;
}

void
GameResource::SetHeading(const unsigned int h)
{
  heading = h;
}

std::string&
GameResource::GetMemberName(const unsigned int m)
{
  return memberName[m];
}

void
GameResource::SetMemberName(const unsigned int m, const std::string& s)
{
  memberName[m] = s;
}

unsigned int
GameResource::GetMemberData(const unsigned int m, const unsigned int i, const unsigned int j)
{
  return memberData[(m * 16 + i) * 5 + j];
}

void
GameResource::SetMemberData(const unsigned int m, const unsigned int i, const unsigned int j, const unsigned int v)
{
  memberData[(m * 16 + i) * 5 + j] = v;
}

unsigned int
GameResource::GetActiveMember(const unsigned int i)
{
  return activeMember[i];
}

void
GameResource::SetActiveMember(const unsigned int i, const unsigned int v)
{
  activeMember[i] = v;
}

void
GameResource::Load(FileBuffer *buffer)
{
  try {
    if (game){
      delete game;
    }
    game = new Game();
    game->SetName(buffer->GetString());
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
    heading = buffer->GetUint16LE();
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
    unsigned int n = buffer->GetUint8();
    for (unsigned int i = 0; i < n; i++) {
      activeMember.push_back(buffer->GetUint8());
    }
  } catch (Exception &e) {
    e.Print("GameResource::Load");
  }
}

void
GameResource::Save(FileBuffer *buffer)
{
  if (!game) {
    throw NullPointer(__FILE__, __LINE__, "game");
  }
  try {
    buffer->Rewind();
    buffer->PutString(game->GetName());
    buffer->Seek(90);
    buffer->Skip(16);
    buffer->PutUint32LE(ypos);
    buffer->PutUint32LE(xpos);
    buffer->Skip(4);
    buffer->PutUint8(zone);
    buffer->PutUint8(xcell);
    buffer->PutUint8(ycell);
    buffer->PutUint32LE(xloc);
    buffer->PutUint32LE(yloc);
    buffer->Skip(5);
    buffer->PutUint16LE(heading);
    buffer->Skip(23);
    for (unsigned int m = 0; m < 6; m++) {
      buffer->PutString(memberName[m], 10);
    }
    for (unsigned int m = 0; m < 6; m++) {
      buffer->Skip(8);
      for (unsigned int i = 0; i < 16; i++) {
        for (unsigned int j = 0; j < 5; j++) {
          buffer->PutUint8(memberData[(m * 16 + i) * 5 + j]);
        }
      }
      buffer->PutUint8(m + 1);
      buffer->Skip(6);
    }
    buffer->PutUint8(activeMember.size());
    for (unsigned int i = 0; i < activeMember.size(); i++) {
      buffer->PutUint8(activeMember[i]);
    }
  } catch (Exception &e) {
    e.Print("GameResource::Load");
  }
}
