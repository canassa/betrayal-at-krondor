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

#include "Exception.h"
#include "DialogWindow.h"
#include "FileManager.h"
#include "MousePointerManager.h"

DialogWindow::DialogWindow(WidgetResources& widgetRes)
: panel(0)
{
  try{
    WidgetFactory wf;
    panel = wf.CreatePanel(widgetRes);
  } catch (Exception &e) {
    e.Print("DialogWindow::DialogWindow");
    throw;
  }
}

DialogWindow::~DialogWindow()
{
  if (panel) {
    delete panel;
  }
}

void
DialogWindow::Draw(Video *video)
{
  panel->Draw(video);
  MousePointerManager::GetInstance()->GetCurrentPointer()->Draw(video);
  video->Refresh();
}

void
DialogWindow::FadeIn(PaletteResource* pal, MediaToolkit *media)
{
  panel->Draw(media->GetVideo());
  MousePointerManager::GetInstance()->GetCurrentPointer()->Draw(media->GetVideo());
  pal->FadeIn(media, 0, VIDEO_COLORS, 64, 5);
}

void
DialogWindow::FadeOut(PaletteResource* pal, MediaToolkit *media)
{
  panel->Draw(media->GetVideo());
  MousePointerManager::GetInstance()->GetCurrentPointer()->Draw(media->GetVideo());
  pal->FadeOut(media, 0, VIDEO_COLORS, 64, 5);
}

void
DialogWindow::LeftClickWidget(const bool toggle)
{
  panel->LeftClickWidget(toggle);
}

void
DialogWindow::RightClickWidget(const bool toggle)
{
  panel->RightClickWidget(toggle);
}

void
DialogWindow::LeftClickWidget(const bool toggle, const int x, const int y)
{
  panel->LeftClickWidget(toggle, x, y);
}

void
DialogWindow::RightClickWidget(const bool toggle, const int x, const int y)
{
  panel->RightClickWidget(toggle, x, y);
}

void
DialogWindow::SelectNextWidget(Video *video)
{
  panel->NextWidget(video);
}
