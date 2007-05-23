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

#include "MediaToolkit.h"
#include "TextButtonWidget.h"

TextButtonWidget::TextButtonWidget(const Rectangle &r, const int a)
: ButtonWidget(r, a)
, label(0)
{
}

TextButtonWidget::~TextButtonWidget()
{
  if (label) {
    delete label;
  }
}

void
TextButtonWidget::SetLabel(const std::string& s, Font *f)
{
  label = new TextWidget(Rectangle(rect.GetXPos() + 2, rect.GetYPos() + 2, rect.GetWidth() - 4, rect.GetHeight() - 4), f);
  label->SetText(s);
}

void
TextButtonWidget::Draw()
{
  if (IsVisible()) {
    if (IsPressed()) {
      Video *video = MediaToolkit::GetInstance()->GetVideo();
      video->FillRect(rect.GetXPos() + 1, rect.GetYPos() + 1, rect.GetWidth() - 2, rect.GetHeight() - 2, BUTTON_COLOR_PRESSED);
      video->DrawVLine(rect.GetXPos(), rect.GetYPos(), rect.GetHeight(), LIGHT_COLOR);
      video->DrawHLine(rect.GetXPos() + 1, rect.GetYPos(), rect.GetWidth() - 1, SHADOW_COLOR);
      video->DrawVLine(rect.GetXPos() + rect.GetWidth() - 1, rect.GetYPos() + 1, rect.GetHeight() - 2, SHADOW_COLOR);
      video->DrawHLine(rect.GetXPos() + 1, rect.GetYPos() + rect.GetHeight() - 1, rect.GetWidth() - 1, LIGHT_COLOR);
    } else {
      Video *video = MediaToolkit::GetInstance()->GetVideo();
      video->FillRect(rect.GetXPos() + 1, rect.GetYPos() + 1, rect.GetWidth() - 2, rect.GetHeight() - 2, BUTTON_COLOR_NORMAL);
      video->DrawVLine(rect.GetXPos(), rect.GetYPos(), rect.GetHeight(), SHADOW_COLOR);
      video->DrawHLine(rect.GetXPos() + 1, rect.GetYPos(), rect.GetWidth() - 1, LIGHT_COLOR);
      video->DrawVLine(rect.GetXPos() + rect.GetWidth() - 1, rect.GetYPos() + 1, rect.GetHeight() - 2, LIGHT_COLOR);
      video->DrawHLine(rect.GetXPos() + 1, rect.GetYPos() + rect.GetHeight() - 1, rect.GetWidth() - 1, SHADOW_COLOR);
    }
    if (label) {
      if (IsEnabled()) {
        if (IsPressed()) {
          label->SetColor(TEXT_COLOR_PRESSED);
          label->SetShadow(SHADOW_COLOR, 0, 1);
        } else {
          label->SetColor(TEXT_COLOR_NORMAL);
          label->SetShadow(SHADOW_COLOR, 0, 1);
        }
      } else {
        label->SetColor(TEXT_COLOR_DISABLED);
        label->SetShadow(NO_SHADOW, 0, 0);
      }
      label->Draw();
    }
  }
}

void
TextButtonWidget::LeftClick(const bool toggle, const int, const int)
{
  if (IsVisible()) {
    SetPressed(toggle);
    if (toggle) {
      GenerateActionEvent(GetAction());
    }
  }
}

void
TextButtonWidget::RightClick(const bool toggle, const int, const int)
{
  if (IsVisible()) {
    if (toggle) {
    }
  }
}
