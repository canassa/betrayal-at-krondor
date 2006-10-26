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

#include "SkillsWidget.h"

SkillsWidget::SkillsWidget(const int x, const int y, const int w, const int h, PlayerCharacter *pc, Image *sw, Image *bl, FontResource &f)
: Widget(x, y, w, h)
, playerCharacter(pc)
, font(f)
, leftSword(0)
, leftBlood(0)
, rightSword(0)
, rightBlood(0)
, defense(0)
, crossbowAccuracy(0)
, meleeAccuracy(0)
, castingAccuracy(0)
, assessment(0)
, armorcraft(0)
, weaponcraft(0)
, barding(0)
, haggling(0)
, lockpick(0)
, scouting(0)
, stealth(0)
{
  leftSword = new Image(sw);
  leftBlood = new Image(bl);
  rightSword = new Image(sw);
  rightBlood = new Image(bl);
  rightSword->HorizontalFlip();
  rightBlood->HorizontalFlip();
  defense = new SkillLevelWidget(xpos, ypos, 132, 25, LEFT_SIDE, leftSword, leftBlood, f);
  crossbowAccuracy = new SkillLevelWidget(xpos, ypos + 16, 132, 25, LEFT_SIDE, leftSword, leftBlood, f);
  meleeAccuracy = new SkillLevelWidget(xpos, ypos + 32, 132, 25, LEFT_SIDE, leftSword, leftBlood, f);
  castingAccuracy = new SkillLevelWidget(xpos, ypos + 48, 132, 25, LEFT_SIDE, leftSword, leftBlood, f);
  assessment = new SkillLevelWidget(xpos, ypos + 64, 132, 25, LEFT_SIDE, leftSword, leftBlood, f);
  armorcraft = new SkillLevelWidget(xpos, ypos + 80, 132, 25, LEFT_SIDE, leftSword, leftBlood, f);
  weaponcraft = new SkillLevelWidget(xpos + 145, ypos, 132, 25, RIGHT_SIDE, rightSword, rightBlood, f);
  barding = new SkillLevelWidget(xpos + 145, ypos + 16, 132, 25, RIGHT_SIDE, rightSword, rightBlood, f);
  haggling = new SkillLevelWidget(xpos + 145, ypos + 32, 132, 25, RIGHT_SIDE, rightSword, rightBlood, f);
  lockpick = new SkillLevelWidget(xpos + 145, ypos + 48, 132, 25, RIGHT_SIDE, rightSword, rightBlood, f);
  scouting = new SkillLevelWidget(xpos + 145, ypos + 64, 132, 25, RIGHT_SIDE, rightSword, rightBlood, f);
  stealth = new SkillLevelWidget(xpos + 145, ypos + 80, 132, 25, RIGHT_SIDE, rightSword, rightBlood, f);
  defense->SetLevel("Defense", pc->GetCurrentSkills().defense);
  crossbowAccuracy->SetLevel("Accy: Crossbow", pc->GetCurrentSkills().crossbowAccuracy);
  meleeAccuracy->SetLevel("Accy: Melee", pc->GetCurrentSkills().meleeAccuracy);
  castingAccuracy->SetLevel("Accy: Casting", pc->GetCurrentSkills().castingAccuracy);
  assessment->SetLevel("Assessment", pc->GetCurrentSkills().assessment);
  armorcraft->SetLevel("Armorcraft", pc->GetCurrentSkills().armorcraft);
  weaponcraft->SetLevel("Weaponcraft", pc->GetCurrentSkills().weaponcraft);
  barding->SetLevel("Barding", pc->GetCurrentSkills().barding);
  haggling->SetLevel("Haggling", pc->GetCurrentSkills().haggling);
  lockpick->SetLevel("Lockpick", pc->GetCurrentSkills().lockpick);
  scouting->SetLevel("Scouting", pc->GetCurrentSkills().scouting);
  stealth->SetLevel("Stealth", pc->GetCurrentSkills().stealth);
}

SkillsWidget::~SkillsWidget()
{
  delete leftSword;
  delete leftBlood;
  delete rightSword;
  delete rightBlood;
}

void
SkillsWidget::Draw()
{
  defense->Draw();
  crossbowAccuracy->Draw();
  meleeAccuracy->Draw();
  castingAccuracy->Draw();
  assessment->Draw();
  armorcraft->Draw();
  weaponcraft->Draw();
  barding->Draw();
  haggling->Draw();
  lockpick->Draw();
  scouting->Draw();
  stealth->Draw();
}
