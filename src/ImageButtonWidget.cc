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

#include "ImageButtonWidget.h"

ImageButtonWidget::ImageButtonWidget(const Rectangle2D &r, const int a)
: ButtonWidget(r, a)
, normalImage(0)
, pressedImage(0)
{
}

ImageButtonWidget::~ImageButtonWidget()
{
}

void
ImageButtonWidget::SetImage(Image *normal, Image *press)
{
  normalImage = normal;
  pressedImage = press;
}

void
ImageButtonWidget::Draw()
{
  if (IsVisible()) {
    if (IsEnabled()) {
      if (IsPressed()) {
        if (pressedImage) {
          pressedImage->Draw(rect.GetXPos(), rect.GetYPos() + 1, 0);
        }
      } else {
        if (normalImage) {
          normalImage->Draw(rect.GetXPos(), rect.GetYPos() + 1, 0);
        }
      }
    }
  }
}

void
ImageButtonWidget::LeftClick(const bool toggle)
{
  if (IsVisible()) {
    SetPressed(toggle);
    if (toggle) {
      GenerateActionEvent(GetAction());
    }
  }
}

void
ImageButtonWidget::RightClick(const bool toggle)
{
  if (IsVisible()) {
    if (toggle) {
    }
  }
}
