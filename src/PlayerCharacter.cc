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

#include "PlayerCharacter.h"

PlayerCharacter::PlayerCharacter(const std::string& s)
: name(s)
, buttonImage(0)
, portraitImage(0)
, order(-1)
, selected(false)
{
  charClass = CLASS_WARRIOR;
  condition = COND_NORMAL;
  memset(&currentRatings, 0, sizeof(RatingSet));
  memset(&normalRatings, 0, sizeof(RatingSet));
  memset(&currentSkills, 0, sizeof(SkillSet));
  memset(&normalSkills, 0, sizeof(SkillSet));
}

PlayerCharacter::~PlayerCharacter()
{
}

std::string&
PlayerCharacter::GetName()
{
  return name;
}

void
PlayerCharacter::SetName(const std::string& s)
{
  name = s;
}

Image *
PlayerCharacter::GetButtonImage() const
{
  return buttonImage;
}

void
PlayerCharacter::SetButtonImage(Image *img)
{
  buttonImage = img;
}

Image *
PlayerCharacter::GetPortraitImage() const
{
  return portraitImage;
}

void
PlayerCharacter::SetPortraitImage(Image *img)
{
  portraitImage = img;
}

CharacterClass
PlayerCharacter::GetCharacterClass() const
{
  return charClass;
}

void
PlayerCharacter::SetCharacterClass(const CharacterClass cc)
{
  charClass = cc;
}

ConditionType
PlayerCharacter::GetCondition() const
{
  return condition;
}

void
PlayerCharacter::SetCondition(const ConditionType ct)
{
  condition = ct;
}

int
PlayerCharacter::GetOrder() const
{
  return order;
}

void
PlayerCharacter::SetOrder(const int n)
{
  order = n;
}

bool
PlayerCharacter::IsSelected() const
{
  return selected;
}

void
PlayerCharacter::Select(const bool toggle)
{
  selected = toggle;
}

RatingSet&
PlayerCharacter::GetCurrentRatings()
{
  return currentRatings;
}

RatingSet&
PlayerCharacter::GetNormalRatings()
{
  return normalRatings;
}

SkillSet&
PlayerCharacter::GetCurrentSkills()
{
  return currentSkills;
}

SkillSet&
PlayerCharacter::GetNormalSkills()
{
  return normalSkills;
}
