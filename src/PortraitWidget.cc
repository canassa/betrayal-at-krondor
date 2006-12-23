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

#include "PortraitWidget.h"

PortraitWidget::PortraitWidget(const int x, const int y, const int w, const int h, PlayerCharacter *pc)
: Widget(x, y, w, h)
, playerCharacter(pc)
, horizontalBorder(0)
, verticalBorder(0)
{
}

PortraitWidget::~PortraitWidget()
{
}

void
PortraitWidget::SetBorders(Image *hb, Image *vb)
{
  horizontalBorder = hb;
  verticalBorder = vb;
}

void
PortraitWidget::Draw()
{
  if (IsVisible()) {
    int xoff = 0;
    int yoff = 0;
    if (horizontalBorder && verticalBorder)
    {
      horizontalBorder->Draw(rect.GetXPos() + verticalBorder->GetWidth(), rect.GetYPos(), 0, 0,
                             rect.GetWidth() - 2 * verticalBorder->GetWidth(), horizontalBorder->GetHeight());
      horizontalBorder->Draw(rect.GetXPos() + verticalBorder->GetWidth(), rect.GetYPos() + rect.GetHeight() - horizontalBorder->GetHeight(), 0, 0,
                             rect.GetWidth() - 2 * verticalBorder->GetWidth(), horizontalBorder->GetHeight());
      verticalBorder->Draw(rect.GetXPos(), rect.GetYPos(), 0, 0,
                           verticalBorder->GetWidth(), rect.GetHeight());
      verticalBorder->Draw(rect.GetXPos() + rect.GetWidth() - verticalBorder->GetWidth(), rect.GetYPos(), 0, 0,
                           verticalBorder->GetWidth(), rect.GetHeight());
      xoff = verticalBorder->GetWidth();
      yoff = horizontalBorder->GetHeight();
    }
    // playerCharacter->GetPortraitImage()->Draw(rect.GetXPos() +xoff, rect.GetYPos() + yoff, 0);
  }
}
