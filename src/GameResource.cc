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

#include "Exception.h"
#include "GameResource.h"

static const unsigned int INVENTORY_SLOTS = 24;

GameResource::GameResource()
: game(0)
, xloc(0)
, yloc(0)
{
}

GameResource::~GameResource()
{
  if (game) {
    delete game;
  }
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

void
GameResource::Load(FileBuffer *buffer)
{
  try {
    if (game){
      delete game;
    }
    game = new Game();
    game->SetName(buffer->GetString());
    buffer->Seek(0x00005a);
    buffer->Skip(16);
    yloc = buffer->GetUint32LE();
    xloc = buffer->GetUint32LE();
    buffer->Skip(4);
    zone = buffer->GetUint8();
    int xcell = buffer->GetUint8();
    int ycell = buffer->GetUint8();
    int xpos = buffer->GetUint32LE();
    int ypos = buffer->GetUint32LE();
    game->GetCamera()->SetPosition(Vector2D(xpos, ypos));
    if (game->GetCamera()->GetPosition().GetCell() != Vector2D(xcell, ycell)) {
      throw DataCorruption(__FILE__, __LINE__, "cell != position");
    }
    buffer->Skip(5);
    game->GetCamera()->SetHeading(buffer->GetUint16LE());
    buffer->Skip(23);
    for (unsigned int m = 0; m < game->GetParty()->GetNumMembers(); m++) {
      game->GetParty()->GetMember(m)->SetName(buffer->GetString(10));
    }
    for (unsigned int m = 0; m < game->GetParty()->GetNumMembers(); m++) {
      buffer->Skip(8);
      for (unsigned int i = 0; i < NUM_STATS; i++) {
        for (unsigned int j = 0; j < NUM_STAT_VALUES; j++) {
          game->GetParty()->GetMember(m)->GetStatistics().Set(i, j, buffer->GetUint8());
        }
      }
      buffer->Skip(7);
    }
    unsigned int n = buffer->GetUint8();
    for (unsigned int i = 0; i < n; i++) {
      game->GetParty()->ActivateMember(buffer->GetUint8(), i);
    }
    if (game->GetParty()->GetNumActiveMembers() != n) {
      throw DataCorruption(__FILE__, __LINE__, "active members");
    }
    buffer->Seek(0x03a7f8);
    for (unsigned int m = 0; m < game->GetParty()->GetNumMembers(); m++) {
      buffer->Skip(buffer->GetUint16LE());
      unsigned int numItems = buffer->GetUint8();
      unsigned int numSlots = buffer->GetUint16LE();
      if (numSlots != INVENTORY_SLOTS) {
        throw DataCorruption(__FILE__, __LINE__, "inventory slots");
      }
      Inventory *inv = game->GetParty()->GetMember(m)->GetInventory();
      for (unsigned int i = 0; i < numSlots; i++) {
        if (i < numItems){
          unsigned int id = buffer->GetUint8();
          unsigned int value = buffer->GetUint8();
          unsigned int flags = buffer->GetUint16LE();
          InventoryItem *item;
          switch (game->GetObjectInfo(id).type) {
            case OT_SWORD:
            case OT_CROSSBOW:
            case OT_ARMOR:
              item = new RepairableInventoryItem(id, value);
              break;
            case OT_STAFF:
              item = new SingleInventoryItem(id);
              break;
            case OT_WEAPON_OIL:
            case OT_ARMOR_OIL:
            case OT_SPECIAL_OIL:
            case OT_NOTE:
            case OT_BOOK:
            case OT_POTION:
            case OT_RESTORATIVES:
              item = new UsableInventoryItem(id, value);
              break;
            case OT_AMMUNITION:
            case OT_KEY:
            case OT_TOOL:
            case OT_BOWSTRING:
            case OT_SCROLL:
            case OT_CONTAINER:
            case OT_LIGHTER:
            case OT_INGREDIENT:
            case OT_RATION:
            case OT_FOOD:
              item = new MultipleInventoryItem(id, value);
              break;
            case OT_UNKNOWN5:
            case OT_UNKNOWN6:
            case OT_UNKNOWN14:
            case OT_UNKNOWN15:
              throw DataCorruption(__FILE__, __LINE__, "unknown object type: ", game->GetObjectInfo(id).type);
              break;
            default:
              throw DataCorruption(__FILE__, __LINE__, "invalid object type: ", game->GetObjectInfo(id).type);
              break;
          }
          item->Equip(flags & EQUIPED_MASK);
          inv->Add(item);
        } else {
          buffer->Skip(4);
        }
      }
      buffer->Skip(1);
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
    buffer->Seek(0x00005a);
    buffer->Skip(16);
    buffer->PutUint32LE(yloc);
    buffer->PutUint32LE(xloc);
    buffer->Skip(4);
    buffer->PutUint8(zone);
    buffer->PutUint8(game->GetCamera()->GetPosition().GetCell().GetX());
    buffer->PutUint8(game->GetCamera()->GetPosition().GetCell().GetY());
    buffer->PutUint32LE(game->GetCamera()->GetPos().GetX());
    buffer->PutUint32LE(game->GetCamera()->GetPos().GetY());
    buffer->Skip(5);
    buffer->PutUint16LE(game->GetCamera()->GetHeading());
    buffer->Skip(23);
    for (unsigned int m = 0; m < game->GetParty()->GetNumMembers(); m++) {
      buffer->PutString(game->GetParty()->GetMember(m)->GetName(), 10);
    }
    for (unsigned int m = 0; m < game->GetParty()->GetNumMembers(); m++) {
      buffer->Skip(8);
      for (unsigned int i = 0; i < NUM_STATS; i++) {
        for (unsigned int j = 0; j < NUM_STAT_VALUES; j++) {
          buffer->PutUint8(game->GetParty()->GetMember(m)->GetStatistics().Get(i, j));
        }
      }
      buffer->PutUint8(m + 1);
      buffer->Skip(6);
    }
    buffer->PutUint8(game->GetParty()->GetNumActiveMembers());
    for (unsigned int i = 0; i < game->GetParty()->GetNumActiveMembers(); i++) {
      buffer->PutUint8(game->GetParty()->GetActiveMemberIndex(i));
    }
    buffer->Seek(0x03a7f8);
    for (unsigned int m = 0; m < game->GetParty()->GetNumMembers(); m++) {
      buffer->Skip(12);
      Inventory *inv = game->GetParty()->GetMember(m)->GetInventory();
      buffer->PutUint8(inv->GetItems().size());
      buffer->PutUint8(INVENTORY_SLOTS);
      std::list<const InventoryItem *>::iterator it = inv->GetItems().begin();
      for (unsigned int i = 0; i < INVENTORY_SLOTS; i++) {
        if (it != inv->GetItems().end()) {
          buffer->PutUint8((*it)->GetId());
          buffer->PutUint8((*it)->GetValue());
          buffer->PutUint16LE((*it)->GetFlags());
          ++it;
        } else {
          buffer->PutUint32LE(0);
        }
      }
    }
  } catch (Exception &e) {
    e.Print("GameResource::Save");
    throw;
  }
}
