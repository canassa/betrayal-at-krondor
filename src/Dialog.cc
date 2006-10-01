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
#include "FileManager.h"
#include "MousePointerManager.h"
#include "WidgetFactory.h"

Dialog::Dialog()
: window(0)
, palette(0)
, widgetRes()
, action(0)
, running(false)
{
  try {
    MousePointerManager::GetInstance()->SetCurrentPointer(NORMAL_POINTER);
    MousePointerManager::GetInstance()->GetCurrentPointer()->SetVisible(true);
    memset(&widgetRes, 0, sizeof(WidgetResources));
    widgetRes.eventListener = this;
  } catch (Exception &e) {
    e.Print("Dialog::Dialog");
    throw;
  }
}

Dialog::~Dialog()
{
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
  if (widgetRes.compass) {
    delete widgetRes.compass;
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
    FileManager::GetInstance()->Load(widgetRes.font, name);
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
    FileManager::GetInstance()->Load(widgetRes.label, name);
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
    FileManager::GetInstance()->Load(palette, name);
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
    FileManager::GetInstance()->Load(widgetRes.screen, name);
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
    FileManager::GetInstance()->Load(widgetRes.normal, normalName);
    if (widgetRes.pressed) {
      delete widgetRes.pressed;
    }
    widgetRes.pressed = new ImageResource();
    FileManager::GetInstance()->Load(widgetRes.pressed, pressedName);
  } catch (Exception &e) {
    e.Print("Dialog::SetIcons");
    throw;
  }
}

void
Dialog::SetCamera(Camera *cam)
{
  if (cam) {
    widgetRes.camera = cam;
  } else {
    throw NullPointer(__FILE__, __LINE__);
  }
}

void
Dialog::SetCompass(const std::string &name)
{
  try {
    if (widgetRes.compass) {
      delete widgetRes.compass;
    }
    widgetRes.compass = new ImageResource();
    FileManager::GetInstance()->Load(widgetRes.compass, name);
  } catch (Exception &e) {
    e.Print("Dialog::SetCompass");
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
    FileManager::GetInstance()->Load(widgetRes.heads, name);
  } catch (Exception &e) {
    e.Print("Dialog::SetHeads");
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
    FileManager::GetInstance()->Load(widgetRes.request, name);
  } catch (Exception &e) {
    e.Print("Dialog::SetRequest");
    throw;
  }
}

void
Dialog::SetMembers(Party *party, const int group)
{
  if (party) {
    widgetRes.playerCharacterGroup = group;
    for (unsigned int i = 0; i < MAX_ACTIVE_MEMBERS; i++) {
      PlayerCharacter *pc = party->GetActiveMember(i);
      widgetRes.members[i] = pc;
    }
  } else {
    throw NullPointer(__FILE__, __LINE__);
  }
}

void
Dialog::SetGameView(Game *game, const int group, const GameViewType type)
{
  if (game) {
    widgetRes.game = game;
    widgetRes.gameViewGroup = group;
    widgetRes.gameViewType = type;
  } else {
    throw NullPointer(__FILE__, __LINE__);
  }
}

void
Dialog::Enter()
{
  try {
    window = new DialogWindow(widgetRes);
    MediaToolkit* media = MediaToolkit::GetInstance();
    media->AddKeyboardListener(this);
    media->AddMouseButtonListener(this);
    media->GetVideo()->Clear();
    MousePointerManager::GetInstance()->GetCurrentPointer()->Attach(this);
    window->FadeIn(palette->GetPalette());
  } catch (Exception &e) {
    e.Print("Dialog::Enter");
    throw;
  }
}

void
Dialog::Leave()
{
  try {
    window->FadeOut(palette->GetPalette());
    MousePointerManager::GetInstance()->GetCurrentPointer()->Detach(this);
    MediaToolkit* media = MediaToolkit::GetInstance();
    media->GetVideo()->Clear();
    media->RemoveMouseButtonListener(this);
    media->RemoveKeyboardListener(this);
    delete window;
    window = 0;
  } catch (Exception &e) {
    e.Print("Dialog::Leave");
    throw;
  }
}

unsigned int
Dialog::Execute()
{
  try {
    running = true;
    while (running) {
      MediaToolkit::GetInstance()->WaitEvents();
    }
    return action;
  } catch (Exception &e) {
    e.Print("Dialog::Execute");
    throw;
  }
}

void
Dialog::Update()
{
  window->Draw();
}

void
Dialog::ActionPerformed(const ActionEvent& ae)
{
  action = ae.GetAction();
  running = false;
}

void
Dialog::MouseButtonPressed(const MouseButtonEvent& mbe)
{
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
  window->Draw();
}

void
Dialog::MouseButtonReleased(const MouseButtonEvent& mbe)
{
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
  window->Draw();
}


GameDialog::GameDialog()
: Dialog()
{
}

GameDialog::~GameDialog()
{
}

void
GameDialog::KeyPressed(const KeyboardEvent& kbe)
{
  switch (kbe.GetKey()) {
    case KEY_ESCAPE:
      action = ACT_ESCAPE;
      running = false;
      break;
    case KEY_UP:
      action = ACT_UP;
      running = false;
      break;
    case KEY_DOWN:
      action = ACT_DOWN;
      running = false;
      break;
    case KEY_LEFT:
      action = ACT_LEFT;
      running = false;
      break;
    case KEY_RIGHT:
      action = ACT_RIGHT;
      running = false;
      break;
    default:
      break;
  }
  window->Draw();
}

void
GameDialog::KeyReleased(const KeyboardEvent& kbe)
{
  switch (kbe.GetKey()) {
    default:
      break;
  }
}


OptionsDialog::OptionsDialog()
: Dialog()
{
}

OptionsDialog::~OptionsDialog()
{
}

void
OptionsDialog::KeyPressed(const KeyboardEvent& kbe)
{
  switch (kbe.GetKey()) {
    case KEY_ESCAPE:
      action = ACT_ESCAPE;
      running = false;
      break;
    case KEY_DOWN:
    case KEY_TAB:
      if (running) {
        window->SelectNextWidget();
      }
      break;
    case KEY_UP:
      if (running) {
        window->SelectPreviousWidget();
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
  window->Draw();
}

void
OptionsDialog::KeyReleased(const KeyboardEvent& kbe)
{
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
  window->Draw();
}
