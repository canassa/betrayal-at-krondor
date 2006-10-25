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

#include <iomanip>
#include <sstream>

#include "SkillLevelWidget.h"

SkillLevelWidget::SkillLevelWidget(const int x, const int y, const int w, const int h, const Side s, Image *sw, Image *bl, FontResource &f)
: Widget(x, y, w, h)
, side(s)
, sword(sw)
, blood(bl)
, skill(0)
, level(0)
{
  if (side == LEFT_SIDE) {
    skill = new TextWidget(xpos + 34, ypos, 72, 12, f);
    skill->SetAlignment(HA_LEFT, VA_TOP);
    skill->SetColor(TEXT_COLOR_NORMAL);
    skill->SetShadow(SHADOW_COLOR, 1, 1);
    level = new TextWidget(xpos + 110, ypos, 20, 12, f);
    level->SetAlignment(HA_RIGHT, VA_TOP);
    level->SetColor(TEXT_COLOR_NORMAL);
    level->SetShadow(SHADOW_COLOR, 1, 1);
  } else {
    skill = new TextWidget(xpos + 6, ypos, 72, 12, f);
    skill->SetAlignment(HA_LEFT, VA_TOP);
    skill->SetColor(TEXT_COLOR_NORMAL);
    skill->SetShadow(SHADOW_COLOR, 1, 1);
    level = new TextWidget(xpos + 82, ypos, 20, 12, f);
    level->SetAlignment(HA_RIGHT, VA_TOP);
    level->SetColor(TEXT_COLOR_NORMAL);
    level->SetShadow(SHADOW_COLOR, 1, 1);
  }
}

SkillLevelWidget::~SkillLevelWidget()
{
  if (skill) {
    delete skill;
  }
  if (level) {
    delete level;
  }
}

void
SkillLevelWidget::SetLevel(const std::string& s, const int x)
{
  skill->SetText(s);
  if (x > 0) {
    std::stringstream stream;
    stream << std::setw(2) << std::setfill(' ') << x << '%';
    level->SetText(stream.str());
  } else {
    level->SetText("N/A");
  }
}

void
SkillLevelWidget::Draw()
{
  skill->Draw();
  level->Draw();
  sword->Draw(xpos, ypos + 2, 0);
}
