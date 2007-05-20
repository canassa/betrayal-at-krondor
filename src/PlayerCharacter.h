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

#ifndef PLAYER_CHARACTER_H
#define PLAYER_CHARACTER_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Image.h"
#include "Inventory.h"
#include "Statistics.h"

typedef enum _CharacterClass {
  CLASS_WARRIOR,
  CLASS_SPELLCASTER
} CharacterClass;

typedef enum _ConditionType {
  COND_NORMAL,
  COND_SICK,
  COND_PLAGUED,
  COND_POISONED,
  COND_DRUNK,
  COND_HEALING,
  COND_STARVING,
  COND_NEAR_DEATH
} ConditionType;

class PlayerCharacter {
  private:
    std::string name;
    Statistics statistics;
    Image *buttonImage;
    Image *portraitImage;
    int order;
    bool selected;
    CharacterClass charClass;
    ConditionType condition;
    Inventory *inventory;
  public:
    PlayerCharacter(const std::string& s);
    ~PlayerCharacter();
    std::string& GetName();
    void SetName(const std::string& s);
    Statistics& GetStatistics();
    Image* GetButtonImage() const;
    void SetButtonImage(Image *img);
    Image* GetPortraitImage() const;
    void SetPortraitImage(Image *img);
    int GetOrder() const;
    void SetOrder(const int n);
    bool IsSelected() const;
    void Select(const bool toggle);
    CharacterClass GetCharacterClass() const;
    void SetCharacterClass(const CharacterClass cc);
    ConditionType GetCondition() const;
    void SetCondition(const ConditionType ct);
    Inventory* GetInventory() const;
};

#endif

