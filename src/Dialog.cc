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
, palette(0)
, widgetRes()
, action(0)
, running(false)
{
  try {
    MousePointerManager::GetInstance()->SetCurrentPointer(NORMAL_POINTER);
    MousePointerManager::GetInstance()->GetCurrentPointer()->SetVisible(true);
    media->AddKeyboardListener(this);
    media->AddMouseButtonListener(this);
    media->AddUpdateListener(this);
    memset(&widgetRes, 0, sizeof(WidgetResources));
    widgetRes.eventListener = this;
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
  if (widgetRes.font) {
    delete widgetRes.font;
  }
  if (widgetRes.label) {
    delete widgetRes.label;
  }
  if (widgetRes.screen) {
    delete widgetRes.screen;
  }
  if (widgetRes.normal) {
    delete widgetRes.normal;
  }
  if (widgetRes.pressed) {
    delete widgetRes.pressed;
  }
  if (widgetRes.heads) {
    delete widgetRes.heads;
  }
  if (widgetRes.request) {
    delete widgetRes.request;
  }
  if (palette) {
    delete palette;
  }
  if (window) {
    delete window;
  }
}

void
Dialog::SetFont(const std::string &name)
{
  try {
    if (widgetRes.font) {
      delete widgetRes.font;
    }
    widgetRes.font = new FontResource();
    ResourceManager::GetInstance()->Load(widgetRes.font, name);
  } catch (Exception &e) {
    e.Print("Dialog::SetFont");
    throw;
  }
}

void
Dialog::SetLabel(const std::string &name)
{
  try {
    if (widgetRes.label) {
      delete widgetRes.label;
    }
    widgetRes.label = new LabelResource();
    ResourceManager::GetInstance()->Load(widgetRes.label, name);
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
    if (widgetRes.screen) {
      delete widgetRes.screen;
    }
    widgetRes.screen = new ScreenResource();
    ResourceManager::GetInstance()->Load(widgetRes.screen, name);
  } catch (Exception &e) {
    e.Print("Dialog::SetScreen");
    throw;
  }
}

void
Dialog::SetIcons(const std::string &normalName, const std::string &pressedName)
{
  try {
    if (widgetRes.normal) {
      delete widgetRes.normal;
    }
    widgetRes.normal = new ImageResource();
    ResourceManager::GetInstance()->Load(widgetRes.normal, normalName);
    if (widgetRes.pressed) {
      delete widgetRes.pressed;
    }
    widgetRes.pressed = new ImageResource();
    ResourceManager::GetInstance()->Load(widgetRes.pressed, pressedName);
  } catch (Exception &e) {
    e.Print("Dialog::SetIcons");
    throw;
  }
}

void
Dialog::SetHeads(const std::string &name)
{
  try {
    if (widgetRes.heads) {
      delete widgetRes.heads;
    }
    widgetRes.heads = new ImageResource();
    ResourceManager::GetInstance()->Load(widgetRes.heads, name);
  } catch (Exception &e) {
    e.Print("Dialog::SetIcons");
    throw;
  }
}

void
Dialog::SetRequest(const std::string &name)
{
  try {
    if (widgetRes.request) {
      delete widgetRes.request;
    }
    widgetRes.request = new RequestResource();
    ResourceManager::GetInstance()->Load(widgetRes.request, name);
  } catch (Exception &e) {
    e.Print("Dialog::SetRequest");
    throw;
  }
}

void
Dialog::SetMembers(Party *party)
{
  if (party) {
    for (unsigned int i = 0; i < MAX_ACTIVE_MEMBERS; i++) {
      PlayerCharacter *pc = party->GetActiveMember(i);
      widgetRes.members[i] = pc;
    }
  } else {
    throw NullPointer("Dialog::AddMembers");
  }
}

unsigned int
Dialog::Execute()
{
  try {
    window = new DialogWindow(widgetRes);
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
        window->LeftClickWidget(true);
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
        window->LeftClickWidget(false);
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
        window->LeftClickWidget(true, mbe.GetXPos(), mbe.GetYPos());
      }
      break;
    case MB_RIGHT:
      if (running) {
        window->RightClickWidget(true, mbe.GetXPos(), mbe.GetYPos());
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
        window->LeftClickWidget(false, mbe.GetXPos(), mbe.GetYPos());
      }
      break;
    case MB_RIGHT:
      if (running) {
        window->RightClickWidget(false, mbe.GetXPos(), mbe.GetYPos());
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
