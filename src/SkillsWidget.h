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
 * Copyright (C) 2005-2009 Guido de Jong <guidoj@users.sf.net>
 */

#ifndef SKILLS_WIDGET_H
#define SKILLS_WIDGET_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "PlayerCharacter.h"
#include "SkillLevelWidget.h"

class SkillsWidget
            : public Widget
{
private:
    PlayerCharacter *playerCharacter;
    Font *font;
    Image *leftSword;
    Image *leftBlood;
    Image *rightSword;
    Image *rightBlood;
    SkillLevelWidget *defense;
    SkillLevelWidget *crossbowAccuracy;
    SkillLevelWidget *meleeAccuracy;
    SkillLevelWidget *castingAccuracy;
    SkillLevelWidget *assessment;
    SkillLevelWidget *armorcraft;
    SkillLevelWidget *weaponcraft;
    SkillLevelWidget *barding;
    SkillLevelWidget *haggling;
    SkillLevelWidget *lockpick;
    SkillLevelWidget *scouting;
    SkillLevelWidget *stealth;
public:
    SkillsWidget ( const Rectangle &r, PlayerCharacter *pc, Image *sw, Image *bl, Font *f );
    virtual ~SkillsWidget();
    void Draw();
    void Drag ( const int x, const int y );
    void Drop ( const int x, const int y );
};

#endif
