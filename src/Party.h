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

#ifndef PARTY_H
#define PARTY_H

#include <vector>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "PlayerCharacter.h"

class Party {
  private:
    std::vector<PlayerCharacter *> members;
    int zone;
    int xTilePos;
    int yTilePos;
    int xCellPos;
    int yCellPos;
  public:
    Party();
    ~Party();
    PlayerCharacter* GetMember(const unsigned int n);
    PlayerCharacter* GetActiveMember(const int order);
    void AddMember(PlayerCharacter *pc);
    void ActivateMember(const unsigned int n, const int order);
    void SelectMember(const int order);
};

#endif
