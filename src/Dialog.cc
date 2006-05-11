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
#include "Dialog.h"
#include "MousePointerManager.h"
#include "ResourceManager.h"
#include "WidgetFactory.h"

Dialog::Dialog(MediaToolkit *mtk)
: media(mtk)
, window(0)
, font(0)
, label(0)
, palette(0)
, screen(0)
, request(0)
, action(0)
, running(false)
{
  try {
    MousePointerManager::GetInstance()->SetCurrentPointer(NORMAL_POINTER);
    MousePointerManager::GetInstance()->GetCurrentPointer()->SetVisible(true);
    media->AddKeyboardListener(this);
    media->AddMouseButtonListener(this);
    media->AddUpdateListener(this);
  } catch (Exception &e) {
    e.Print("Dialog::Dialog");
    throw;
  }
}

Dialog::~Dialog()
{
  media->RemoveUpdateListener(this);
  media->RemoveMouseButtonListener(this);
  media->RemoveKeyboardListener(this);
  if (font) {
    delete font;
  }
  if (label) {
    delete label;
  }
  if (palette) {
    delete palette;
  }
  if (screen) {
    delete screen;
  }
  if (request) {
    delete request;
  }
  if (window) {
    delete window;
  }
}

void
Dialog::SetFont(const std::string &name)
{
  try {
    if (font) {
      delete font;
    }
    font = new FontResource();
    ResourceManager::GetInstance()->Load(font, name);
  } catch (Exception &e) {
    e.Print("Dialog::SetFont");
    throw;
  }
}

void
Dialog::SetLabel(const std::string &name)
{
  try {
    if (label) {
      delete label;
    }
    label = new LabelResource();
    ResourceManager::GetInstance()->Load(label, name);
  } catch (Exception &e) {
    e.Print("Dialog::SetLabel");
    throw;
  }
}

void
Dialog::SetPalette(const std::string &name)
{
  try {
    if (palette) {
      delete palette;
    }
    palette = new PaletteResource();
    ResourceManager::GetInstance()->Load(palette, name);
  } catch (Exception &e) {
    e.Print("Dialog::Setpalette");
    throw;
  }
}

void
Dialog::SetScreen(const std::string &name)
{
  try {
    if (screen) {
      delete screen;
    }
    screen = new ScreenResource();
    ResourceManager::GetInstance()->Load(screen, name);
  } catch (Exception &e) {
    e.Print("Dialog::SetScreen");
    throw;
  }
}

void
Dialog::SetRequest(const std::string &name)
{
  try {
    if (request) {
      delete request;
    }
    request = new RequestResource();
    ResourceManager::GetInstance()->Load(request, name);
  } catch (Exception &e) {
    e.Print("Dialog::SetRequest");
    throw;
  }
}

unsigned int
Dialog::Execute()
{
  try {
    window = new DialogWindow(request, screen, label, font, this);
    media->GetVideo()->Clear();
    window->FadeIn(palette, media);
    running = true;
    media->PollEventLoop();
    running = false;
    window->FadeOut(palette, media);
    media->GetVideo()->Clear();
    delete window;
    window = 0;
    return action;
  } catch (Exception &e) {
    e.Print("Dialog::Execute");
    throw;
  }
}

void
Dialog::KeyPressed(const KeyboardEvent& kbe) {
  switch (kbe.GetKey()) {
    case KEY_ESCAPE:
      action = ACT_ESCAPE;
      media->TerminateEventLoop();
      break;
    case KEY_TAB:
      if (running) {
        window->SelectNextWidget(media->GetVideo());
      }
      break;
    case KEY_RETURN:
    case KEY_SPACE:
      if (running) {
        window->ActivateWidget();
      }
      break;
    default:
      break;
  }
}

void
Dialog::KeyReleased(const KeyboardEvent& kbe) {
  switch (kbe.GetKey()) {
    case KEY_RETURN:
    case KEY_SPACE:
      if (running) {
        window->DeactivateWidget();
      }
      break;
    default:
      break;
  }
}

void
Dialog::MouseButtonPressed(const MouseButtonEvent& mbe) {
  switch (mbe.GetButton()) {
    case MB_LEFT:
      if (running) {
        window->ActivateWidget(mbe.GetXPos(), mbe.GetYPos());
      }
      break;
    default:
      break;
  }
}

void
Dialog::MouseButtonReleased(const MouseButtonEvent& mbe) {
  switch (mbe.GetButton()) {
    case MB_LEFT:
      if (running) {
        window->DeactivateWidget(mbe.GetXPos(), mbe.GetYPos());
      }
      break;
    default:
      break;
  }
}

void
Dialog::Update(const UpdateEvent& ue)
{
  ue.GetTicks();
  if (running) {
    window->Draw(media->GetVideo());
  }
}

void
Dialog::ActionPerformed(const ActionEvent& ae)
{
  action = ae.GetAction();
  media->TerminateEventLoop();
}
