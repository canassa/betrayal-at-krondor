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

PopUpWidget::PopUpWidget(const int x, const int y, const int w, const int h)
: ContainerWidget(x, y, w, h)
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
    video->FillRect(xpos + 1, ypos + 1, width - 2, height - 2, POPUP_COLOR);
    video->DrawVLine(xpos, ypos, height, SHADOW_COLOR);
    video->DrawHLine(xpos + 1, ypos, width - 1, LIGHT_COLOR);
    video->DrawVLine(xpos + width - 1, ypos + 1, height - 2, LIGHT_COLOR);
    video->DrawHLine(xpos + 1, ypos + height - 1, width - 1, SHADOW_COLOR);
    video->DrawVLine(xpos - 1, ypos + 1, height, SHADOW_COLOR);
    video->DrawHLine(xpos, ypos + height, width - 1, SHADOW_COLOR);
    DrawChildWidgets();
  }
}
