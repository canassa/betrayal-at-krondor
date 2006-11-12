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

#include "MediaToolkit.h"
#include "BadgeWidget.h"

BadgeWidget::BadgeWidget(const int x, const int y, const int w, const int h)
: Widget(x, y, w, h)
, label(0)
{
}

BadgeWidget::~BadgeWidget()
{
  if (label) {
    delete label;
  }
}

void
BadgeWidget::SetLabel(const std::string& s, FontResource& f)
{
  label = new TextWidget(xpos + 2, ypos + 2, width - 4, height - 4, f);
  label->SetText(s);
  label->SetColor(TEXT_COLOR_NORMAL);
  label->SetShadow(SHADOW_COLOR, 0, 1);
}

void
BadgeWidget::Draw()
{
  if (IsVisible()) {
    Video *video = MediaToolkit::GetInstance()->GetVideo();
    video->FillRect(xpos + 1, ypos + 1, width - 2, height - 2, BUTTON_COLOR_NORMAL);
    video->DrawVLine(xpos, ypos, height, SHADOW_COLOR);
    video->DrawHLine(xpos + 1, ypos, width - 1, LIGHT_COLOR);
    video->DrawVLine(xpos + width - 1, ypos + 1, height - 2, LIGHT_COLOR);
    video->DrawHLine(xpos + 1, ypos + height - 1, width - 1, SHADOW_COLOR);
    if (label) {
      label->Draw();
    }
  }
}
