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
#include "MousePointerManager.h"
#include "MoviePlayer.h"
#include "ResourceManager.h"
#include "ResourcePath.h"
#include "SDL_Toolkit.h"
#include "TestApplication.h"
#include "TextArea.h"

TestApplication* TestApplication::instance = 0;

TestApplication::TestApplication()
: mediaToolkit(SDL_Toolkit::GetInstance())
, pal()
, fnt()
, img()
, scr()
, ttm()
{
  mediaToolkit->GetVideo()->SetScaling(2);
  mediaToolkit->GetVideo()->CreateScreen(VIDEO_WIDTH, VIDEO_HEIGHT);
  MousePointerManager::GetInstance()->AddPointer("POINTER.BMX");
  MousePointerManager::GetInstance()->Register(mediaToolkit);
  mediaToolkit->AddKeyboardListener(this);
  mediaToolkit->AddTimerListener(this);
}

TestApplication::~TestApplication()
{
  mediaToolkit->RemoveKeyboardListener(this);
  mediaToolkit->RemoveTimerListener(this);
  MousePointerManager::CleanUp();
  delete mediaToolkit;
  ResourceManager::CleanUp();
  ResourcePath::CleanUp();
}

TestApplication*
TestApplication::GetInstance()
{
  if (!instance) {
    instance = new TestApplication();
  }
  return instance;
}

void
TestApplication::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
TestApplication::ActivatePalette()
{
  try {
    pal.Fill();
    pal.Activate(mediaToolkit->GetVideo(), 0, 256);
  } catch (Exception &e) {
    e.Print("TestApplication::ActivatePalette");
  }
}

void
TestApplication::ActivatePalette(const std::string& name)
{
  try {
    ResourceManager::GetInstance()->Load(&pal, name);
    pal.Activate(mediaToolkit->GetVideo(), 0, 256);
  } catch (Exception &e) {
    e.Print("TestApplication::ActivatePalette");
  }
}

void
TestApplication::ShowImage(const std::string& name)
{
  try {
    ResourceManager::GetInstance()->Load(&img, name);
    for (unsigned int i = 0; i < img.GetNumImages(); i++) {
      mediaToolkit->GetVideo()->Clear();
      img.GetImage(i)->Draw(mediaToolkit->GetVideo(), 0, 0);
      mediaToolkit->GetVideo()->Refresh();
      mediaToolkit->GetClock()->StartTimer(TMR_TEST_APP, 2500);
      mediaToolkit->WaitEventLoop();
    }
  } catch (Exception &e) {
    e.Print("TestApplication::ShowImage");
  }
}

void
TestApplication::ShowScreen(const std::string& name)
{
  try {
    ResourceManager::GetInstance()->Load(&scr, name);
    mediaToolkit->GetVideo()->Clear();
    scr.GetImage()->Draw(mediaToolkit->GetVideo(), 0, 0);
    mediaToolkit->GetVideo()->Refresh();
    mediaToolkit->ClearEvents();
    mediaToolkit->GetClock()->StartTimer(TMR_TEST_APP, 5000);
    mediaToolkit->WaitEventLoop();
  } catch (Exception &e) {
    e.Print("TestApplication::ShowScreen");
  }
}

void
TestApplication::DrawFont(const std::string& name)
{
  try {
    ResourceManager::GetInstance()->Load(&fnt, name);
    mediaToolkit->GetVideo()->Clear();
    TextArea ta1(280, 180, fnt);
    ta1.SetText("The quick brown fox jumped over the lazy dog.");
    ta1.SetColor(15);
    ta1.Draw(mediaToolkit->GetVideo(), 10, 10, false);
    TextArea ta2(280, 180, fnt);
    ta2.SetText("The quick brown fox jumped over the lazy dog.");
    ta2.SetColor(15);
    ta2.Draw(mediaToolkit->GetVideo(), 10, 50, true);
    mediaToolkit->GetVideo()->Refresh();
    mediaToolkit->GetClock()->StartTimer(TMR_TEST_APP, 5000);
    mediaToolkit->WaitEventLoop();
  } catch (Exception &e) {
    e.Print("TestApplication::DrawFont");
  }
}

void
TestApplication::PlayMovie(const std::string& name)
{
  try {
    ResourceManager::GetInstance()->Load(&ttm, name);
    MoviePlayer moviePlayer(mediaToolkit);
    moviePlayer.Play(&ttm.GetMovieTags(), false);
  } catch (Exception &e) {
    e.Print("TestApplication::PlayMovie");
  }
}

void
TestApplication::KeyPressed(const KeyboardEvent &kbe)
{
  switch (kbe.GetKey()) {
    case KEY_ESCAPE:
    case KEY_RETURN:
    case KEY_SPACE:
      mediaToolkit->TerminateEventLoop();
      break;
    default:
      break;
  }
}

void
TestApplication::KeyReleased(const KeyboardEvent &kbe)
{
  switch (kbe.GetKey()) {
    default:
      break;
  }
}

void
TestApplication::TimerExpired(const TimerEvent &te)
{
  if (te.GetID() == TMR_TEST_APP) {
    mediaToolkit->TerminateEventLoop();
  }
}
