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
, xloc(0)
, yloc(0)
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
    yloc = buffer->GetUint32LE();
    xloc = buffer->GetUint32LE();
    buffer->Skip(4);
    zone = buffer->GetUint8();
    int xcell = buffer->GetUint8();
    int ycell = buffer->GetUint8();
    int xpos = buffer->GetUint32LE();
    int ypos = buffer->GetUint32LE();
    game->GetCamera()->SetPosition(xpos, ypos);
    if ((game->GetCamera()->GetPosition().GetXCell() != xcell) ||
        (game->GetCamera()->GetPosition().GetYCell() != ycell)) {
      throw DataCorruption(__FILE__, __LINE__, "cell != position");
    }
    buffer->Skip(5);
    game->GetCamera()->SetHeading(buffer->GetUint16LE());
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
    throw;
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
    buffer->PutUint32LE(yloc);
    buffer->PutUint32LE(xloc);
    buffer->Skip(4);
    buffer->PutUint8(zone);
    buffer->PutUint8(game->GetCamera()->GetPosition().GetXCell());
    buffer->PutUint8(game->GetCamera()->GetPosition().GetYCell());
    buffer->PutUint32LE(game->GetCamera()->GetXPos());
    buffer->PutUint32LE(game->GetCamera()->GetYPos());
    buffer->Skip(5);
    buffer->PutUint16LE(game->GetCamera()->GetHeading());
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
    e.Print("GameResource::Save");
    throw;
  }
}
