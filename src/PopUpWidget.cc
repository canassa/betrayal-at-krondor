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
#include "PopUpWidget.h"

PopUpWidget::PopUpWidget(const Rectangle &r)
: ContainerWidget(r)
{
}

PopUpWidget::~PopUpWidget()
{
}

void
PopUpWidget::Draw()
{
  if (IsVisible()) {
    Video *video = MediaToolkit::GetInstance()->GetVideo();
    video->FillRect(rect.GetXPos() + 1, rect.GetYPos() + 1, rect.GetWidth() - 2, rect.GetHeight() - 2, POPUP_COLOR);
    video->DrawVLine(rect.GetXPos(), rect.GetYPos(), rect.GetHeight(), SHADOW_COLOR);
    video->DrawHLine(rect.GetXPos() + 1, rect.GetYPos(), rect.GetWidth() - 1, LIGHT_COLOR);
    video->DrawVLine(rect.GetXPos() + rect.GetWidth() - 1, rect.GetYPos() + 1, rect.GetHeight() - 2, LIGHT_COLOR);
    video->DrawHLine(rect.GetXPos() + 1, rect.GetYPos() + rect.GetHeight() - 1, rect.GetWidth() - 1, SHADOW_COLOR);
    video->DrawVLine(rect.GetXPos() - 1, rect.GetYPos() + 1, rect.GetHeight(), SHADOW_COLOR);
    video->DrawHLine(rect.GetXPos(), rect.GetYPos() + rect.GetHeight(), rect.GetWidth() - 1, SHADOW_COLOR);
    DrawChildWidgets();
  }
}
