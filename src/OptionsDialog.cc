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
#include "OptionsDialog.h"
#include "MousePointerManager.h"
#include "ResourceManager.h"
#include "WidgetFactory.h"

OptionsDialog::OptionsDialog(MediaToolkit *mtk)
: media(mtk)
, window(0)
{
  try {
    ResourceManager::GetInstance()->Load(&gameFont, "GAME.FNT");
    ResourceManager::GetInstance()->Load(&optionsPalette, "OPTIONS.PAL");
    ResourceManager::GetInstance()->Load(&optionsScreen, "OPTIONS0.SCX");
    ResourceManager::GetInstance()->Load(&reqOpt0, "REQ_OPT0.DAT");
    window = new DialogWindow(reqOpt0, optionsScreen, gameFont, this);
    int x = 0;
    int y = 0;
    media->GetMousePosition(&x, &y);
    MousePointerManager::GetInstance()->SetCurrentPointer(NORMAL_POINTER);
    MousePointerManager::GetInstance()->GetCurrentPointer()->SetPosition(x, y);
    MousePointerManager::GetInstance()->GetCurrentPointer()->SetVisible(true);
    media->AddKeyboardListener(this);
    media->AddMouseButtonListener(this);
    media->AddUpdateListener(this);
  } catch (Exception &e) {
    e.Print("OptionsDialog::OptionsDialog");
    throw;
  }
}

OptionsDialog::~OptionsDialog()
{
  media->RemoveKeyboardListener(this);
  media->RemoveMouseButtonListener(this);
  media->RemoveUpdateListener(this);
  delete window;
}

void
OptionsDialog::Run()
{
  try {
    media->GetVideo()->Clear();
    window->FadeIn(optionsPalette, media);
    media->ClearEvents();
    media->PollEventLoop();
    window->FadeOut(optionsPalette, media);
    media->GetVideo()->Clear();
  } catch (Exception &e) {
    e.Print("OptionsDialog::Run");
    throw;
  }
}

void
OptionsDialog::KeyPressed(const KeyboardEvent& kbe) {
  switch (kbe.GetKey()) {
    case KEY_ESCAPE:
      media->TerminateEventLoop();
      break;
    case KEY_TAB:
      window->SelectNextWidget(media->GetVideo());
      break;
    case KEY_RETURN:
    case KEY_SPACE:
      window->ActivateWidget();
      break;
    default:
      break;
  }
}

void
OptionsDialog::KeyReleased(const KeyboardEvent& kbe) {
  switch (kbe.GetKey()) {
    case KEY_RETURN:
    case KEY_SPACE:
      window->DeactivateWidget();
      break;
    default:
      break;
  }
}

void
OptionsDialog::MouseButtonPressed(const MouseButtonEvent& mbe) {
  switch (mbe.GetButton()) {
    case MB_LEFT:
      window->ActivateWidget(mbe.GetXPos(), mbe.GetYPos());
      break;
    default:
      break;
  }
}

void
OptionsDialog::MouseButtonReleased(const MouseButtonEvent& mbe) {
  switch (mbe.GetButton()) {
    case MB_LEFT:
      window->DeactivateWidget(mbe.GetXPos(), mbe.GetYPos());
      break;
    default:
      break;
  }
}

void
OptionsDialog::Update(const UpdateEvent& ue)
{
  ue.GetTicks();
  window->Draw(media->GetVideo());
}

void
OptionsDialog::ActionPerformed(const int action)
{
  switch (action) {
    default:
      printf("Action: %d\n", action);
      break;
  }
}
