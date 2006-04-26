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
#include "GameDialog.h"
#include "MousePointerManager.h"
#include "ResourceManager.h"

GameDialog::GameDialog(MediaToolkit *mtk)
: media(mtk)
, window(0)
, running(false)
{
  try {
    ResourceManager::GetInstance()->Load(&gameFont, "GAME.FNT");
    ResourceManager::GetInstance()->Load(&optionsPalette, "OPTIONS.PAL");
    ResourceManager::GetInstance()->Load(&frameScreen, "FRAME.SCX");
    ResourceManager::GetInstance()->Load(&reqMain, "REQ_MAIN.DAT");
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
    e.Print("GameDialog::GameDialog");
  }
}

GameDialog::~GameDialog()
{
  media->RemoveKeyboardListener(this);
  media->RemoveMouseButtonListener(this);
  media->RemoveUpdateListener(this);
  if (window) {
    delete window;
  }
}

void
GameDialog::Play()
{
  try {
    PaletteResource *palette = 0;
    media->ClearEvents();
    palette = &optionsPalette;
    window = new DialogWindow(reqMain, frameScreen, lblNull, gameFont, this);
    if (window) {
      media->GetVideo()->Clear();
      window->FadeIn(*palette, media);
      running = true;
      media->PollEventLoop();
      running = false;
      window->FadeOut(*palette, media);
      media->GetVideo()->Clear();
      delete window;
      window = 0;
    }
  } catch (Exception &e) {
    e.Print("GameDialog::Play");
  }
}

void
GameDialog::KeyPressed(const KeyboardEvent& kbe)
{
  switch (kbe.GetKey()){
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
GameDialog::KeyReleased(const KeyboardEvent& kbe)
{
  switch (kbe.GetKey()){
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
GameDialog::MouseButtonPressed(const MouseButtonEvent& mbe)
{
  switch (mbe.GetButton()){
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
GameDialog::MouseButtonReleased(const MouseButtonEvent& mbe)
{
  switch (mbe.GetButton()){
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
GameDialog::Update(const UpdateEvent& ue)
{
  ue.GetTicks();
  if (running) {
    window->Draw(media->GetVideo());
  }
}

void
GameDialog::ActionPerformed(const ActionEvent& ae)
{
  switch (ae.GetAction()) {
    default:
      break;
  }
  media->TerminateEventLoop();
}
