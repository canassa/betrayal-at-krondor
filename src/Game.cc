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
#include "Game.h"
#include "PlayerCharacter.h"
#include "ResourceManager.h"

Game::Game()
: party(0)
{
  try {
    ResourceManager::GetInstance()->Load(&partyRes, "PARTY.DAT");
    ResourceManager::GetInstance()->Load(&heads, "HEADS.BMX");
    party = new Party();
    for (unsigned int i = 0; i < partyRes.GetSize(); i++) {
      PartyData *pd = partyRes.GetData(i);
      PlayerCharacter *pc = new PlayerCharacter(pd->name);
      pc->SetHeadImage(heads.GetImage(i));
      party->AddMember(pc);
    }
    party->ActivateMember(0, 0);
    party->ActivateMember(1, 2);
    party->ActivateMember(2, 1);
  } catch (Exception &e) {
    e.Print("Game::Game");
    throw;
  }
}

Game::~Game()
{
  if (party) {
    delete party;
  }
}

Party *
Game::GetParty()
{
  return party;
}
