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

#include "CharacterButtonWidget.h"

Image* CharacterButtonWidget::selectedImage = 0;

CharacterButtonWidget::CharacterButtonWidget(const int x, const int y, const int w, const int h, const int a)
: ButtonWidget(x, y, w, h, a)
, character(0)
{
}

CharacterButtonWidget::~CharacterButtonWidget()
{
}

void
CharacterButtonWidget::SetCharacter(PlayerCharacter *pc)
{
  character = pc;
}

void
CharacterButtonWidget::SetImage(Image *selected)
{
  selectedImage = selected;
}

void
CharacterButtonWidget::Draw()
{
  if (IsVisible()) {
    if (character) {
      character->GetButtonImage()->Draw(xpos, ypos, 0);
      if (character->IsSelected()) {
        selectedImage->Draw(xpos, ypos, 0);
      }
    }
  }
}

void
CharacterButtonWidget::LeftClick(const bool toggle)
{
  if (IsVisible()) {
    if (toggle) {
      GenerateActionEvent(GetAction());
    }
  }
}

void
CharacterButtonWidget::RightClick(const bool toggle)
{
  if (IsVisible()) {
    if (toggle) {
      GenerateActionEvent(GetAction() + RIGHT_CLICK_OFFSET);
    }
  }
}
