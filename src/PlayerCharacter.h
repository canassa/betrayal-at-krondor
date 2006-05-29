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

#ifndef PLAYER_CHARACTER_H
#define PLAYER_CHARACTER_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Image.h"

typedef enum _Condition {
  NORMAL, POISENED
} ConditionType;

typedef struct _RatingSet {
  int curHealth;
  int maxHealth;
  int curStamina;
  int maxStamina;
  int speed;
  int strength;
} RatingSet;

typedef struct _SkillSet {
  int defense;
  int crossbowAccuracy;
  int meleeAccuracy;
  int castingAccuracy;
  int assessment;
  int armorcraft;
  int weaponcraft;
  int barding;
  int haggling;
  int lockpick;
  int scouting;
  int stealth;
} SkillSet;

class PlayerCharacter {
  private:
    std::string name;
    Image *headImage;
    Image *skillsImage;
    int order;
    bool selected;
    RatingSet ratings;
    ConditionType condition;
    SkillSet skills;
  public:
    PlayerCharacter(const std::string& s);
    ~PlayerCharacter();
    std::string& GetName();
    Image* GetHeadImage() const;
    Image* GetSkillsImage() const;
    int GetOrder() const;
    bool IsSelected() const;
    ConditionType GetCondition() const;
    RatingSet& GetRatings();
    SkillSet& GetSkills();
    void SetHeadImage(Image *img);
    void SetSkillsImage(Image *img);
    void SetOrder(const int n);
    void Select(const bool toggle);
};

#endif

