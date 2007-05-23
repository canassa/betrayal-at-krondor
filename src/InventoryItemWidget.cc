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

#include "Exception.h"
#include "InventoryItemWidget.h"
#include "MousePointerManager.h"

InventoryItemWidget::InventoryItemWidget(const Rectangle &r, const int a)
: ActiveWidget(r, a)
, iconImage(0)
, pressed(false)
, selected(false)
, xOrg(r.GetXPos())
, yOrg(r.GetYPos())
, xOffset(0)
, yOffset(0)
{
}

InventoryItemWidget::~InventoryItemWidget()
{
}

void
InventoryItemWidget::SetImage(Image *icon)
{
  if (!icon) {
    throw NullPointer(__FILE__, __LINE__);
  }
  iconImage = icon;
}

void
InventoryItemWidget::Draw()
{
  if (IsVisible()) {
    if (selected) {
    }
    if (pressed) {
      MousePointer *mp = MousePointerManager::GetInstance()->GetCurrentPointer();
      rect.SetXPos(mp->GetXPos() + xOffset);
      rect.SetYPos(mp->GetYPos() + yOffset);
    }
    if (iconImage) {
      iconImage->Draw(rect.GetXPos(), rect.GetYPos(), 0);
    }
  }
}

void
InventoryItemWidget::Focus()
{
}

void
InventoryItemWidget::LeftClick(const bool toggle, const int x, const int y)
{
  if (IsVisible()) {
    pressed = toggle;
    if (pressed) {
      xOffset = rect.GetXPos() - x;
      yOffset = rect.GetYPos() - y;
    } else {
      rect.SetXPos(xOrg);
      rect.SetYPos(yOrg);
      xOffset = 0;
      yOffset = 0;
    }
    if (toggle) {
      GenerateActionEvent(GetAction());
    }
  }
}

void
InventoryItemWidget::RightClick(const bool toggle, const int, const int)
{
  if (IsVisible()) {
    selected = toggle;
    if (toggle) {
      GenerateActionEvent(GetAction() + RIGHT_CLICK_OFFSET);
    }
  }
}
