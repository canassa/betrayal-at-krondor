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
, userAction(UA_UNKNOWN)
, dialogType(DT_OPT0)
, window(0)
, running(false)
{
  try {
    ResourceManager::GetInstance()->Load(&bookFont, "BOOK.FNT");
    ResourceManager::GetInstance()->Load(&gameFont, "GAME.FNT");
    ResourceManager::GetInstance()->Load(&optionsPalette, "OPTIONS.PAL");
    ResourceManager::GetInstance()->Load(&options0Screen, "OPTIONS0.SCX");
    ResourceManager::GetInstance()->Load(&options1Screen, "OPTIONS1.SCX");
    ResourceManager::GetInstance()->Load(&options2Screen, "OPTIONS2.SCX");
    ResourceManager::GetInstance()->Load(&reqOpt0, "REQ_OPT0.DAT");
    ResourceManager::GetInstance()->Load(&reqOpt1, "REQ_OPT1.DAT");
    ResourceManager::GetInstance()->Load(&reqPref, "REQ_PREF.DAT");
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
  if (window) {
    delete window;
  }
}

UserActionType
OptionsDialog::GetUserAction()
{
  try {
    while (userAction == UA_UNKNOWN) {
      switch (dialogType) {
        case DT_OPT0:
          window = new DialogWindow(reqOpt0, options0Screen, gameFont, this);
          break;
        case DT_PREFERENCES:
          window = new DialogWindow(reqPref, options2Screen, gameFont, this);
          break;
        default:
          window = 0;
      }
      if (window) {
        media->GetVideo()->Clear();
        window->FadeIn(optionsPalette, media);
        running = true;
        media->ClearEvents();
        media->PollEventLoop();
        running = false;
        window->FadeOut(optionsPalette, media);
        media->GetVideo()->Clear();
        delete window;
        window = 0;
      }
    }
  } catch (Exception &e) {
    e.Print("OptionsDialog::GetUserAction");
    throw;
  }
  return userAction;
}

void
OptionsDialog::KeyPressed(const KeyboardEvent& kbe) {
  switch (kbe.GetKey()) {
    case KEY_ESCAPE:
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
OptionsDialog::KeyReleased(const KeyboardEvent& kbe) {
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
OptionsDialog::MouseButtonPressed(const MouseButtonEvent& mbe) {
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
OptionsDialog::MouseButtonReleased(const MouseButtonEvent& mbe) {
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
OptionsDialog::Update(const UpdateEvent& ue)
{
  ue.GetTicks();
  if (running) {
    window->Draw(media->GetVideo());
  }
}

void
OptionsDialog::ActionPerformed(const ActionEvent& ae)
{
  switch (dialogType) {
    case DT_OPT0:
      switch (ae.GetAction()) {
        case OPT0_CONTENTS:
          dialogType = DT_CONTENTS;
          break;
        case OPT0_NEW_GAME:
          userAction = UA_NEW_GAME;
          break;
        case OPT0_PREFERENCES:
          dialogType = DT_PREFERENCES;
          break;
        case OPT0_QUIT:
          userAction = UA_QUIT;
          break;
        case OPT0_RESTORE:
          dialogType = DT_RESTORE;
          break;
        default:
          break;
      }
      break;
    case DT_PREFERENCES:
      switch (ae.GetAction()) {
        default:
          dialogType = DT_OPT0;
          break;
      }
      break;
    default:
      printf("DialogType: %d, action: %d\n", dialogType, ae.GetAction());
      break;
  }
  media->TerminateEventLoop();
}
