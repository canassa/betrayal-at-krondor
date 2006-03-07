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
#include "MousePointerManager.h"
#include "ResourceManager.h"
#include "WidgetFactory.h"

DialogWindow::DialogWindow(MediaToolkit *mtk)
: media(mtk)
, panel(0)
{
}

DialogWindow::~DialogWindow()
{
  delete panel;
}

void
DialogWindow::Create(RequestResource& req, ScreenResource& scr, FontResource& fnt, WidgetCallBack *wcb)
{
  try{
    WidgetFactory wf;
    if (panel) {
      delete panel;
    }
    panel = wf.CreatePanel(req, scr, fnt, wcb);
    panel->Draw(media->GetVideo());
    MousePointerManager::GetInstance()->GetCurrentPointer()->Draw(media->GetVideo());
  } catch (Exception &e) {
    e.Print("DialogWindow::Create");
    throw;
  }
}

void
DialogWindow::Run(PaletteResource& pal)
{
  try {
    pal.FadeIn(media->GetVideo(), 0, VIDEO_COLORS, 64, 10, media->GetClock());
    media->ClearEvents();
    media->SetEventHandler(this);
    media->PollEventLoop();
    media->SetEventHandler(0);
    pal.FadeOut(media->GetVideo(), 0, VIDEO_COLORS, 64, 10, media->GetClock());
  } catch (Exception &e) {
    e.Print("DialogWindow::Run");
    throw;
  }
}

void
DialogWindow::HandleKeyboardEvent(int key, bool down)
{
  if (down) {
    switch (key) {
      case KEY_ESCAPE:
        media->TerminateEventLoop();
        break;
      case KEY_TAB:
        panel->NextWidget(media->GetVideo());
        break;
      case KEY_RETURN:
      case KEY_SPACE:
        panel->Activate(down);
        break;
      default:
        break;
    }
  } else {
    switch (key) {
      case KEY_RETURN:
      case KEY_SPACE:
        panel->Activate(down);
        break;
      default:
        break;
    }
  }
}

void
DialogWindow::HandleMouseButtonEvent(int button, int x, int y, bool down)
{
  panel->Draw(media->GetVideo());
  MousePointerManager::GetInstance()->GetCurrentPointer()->Draw(media->GetVideo());
  media->GetVideo()->Refresh();
  if (down) {
    switch (button) {
      case MB_LEFT:
        panel->Activate(x, y, down);
        break;
      default:
        break;
    }
  } else {
    switch (button) {
      case MB_LEFT:
        panel->Activate(x, y, down);
        break;
      default:
        break;
    }
  }
}

void
DialogWindow::HandleUpdateEvent()
{
  panel->Draw(media->GetVideo());
  MousePointerManager::GetInstance()->GetCurrentPointer()->Draw(media->GetVideo());
  media->GetVideo()->Refresh();
}
