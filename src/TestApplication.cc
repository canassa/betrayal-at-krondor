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
}

TestApplication::~TestApplication()
{
  delete mediaToolkit;
  delete ResourceManager::GetInstance();
  delete ResourcePath::GetInstance();
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
      mediaToolkit->GetClock()->Delay(1000);
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
    mediaToolkit->GetClock()->Delay(2000);
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
    TextArea ta(280, 180, fnt);
    ta.SetText("The quick brown fox jumped over the lazy dog.");
    ta.SetColor(15);
    ta.Draw(mediaToolkit->GetVideo(), 10, 10);
    mediaToolkit->GetVideo()->Refresh();
    mediaToolkit->GetClock()->Delay(2000);
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

