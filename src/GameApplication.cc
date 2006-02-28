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

#include "AnimationResource.h"
#include "Exception.h"
#include "FontResource.h"
#include "GameApplication.h"
#include "MousePointerManager.h"
#include "MoviePlayer.h"
#include "MovieResource.h"
#include "OptionsDialog.h"
#include "PaletteResource.h"
#include "ResourceManager.h"
#include "ResourcePath.h"
#include "ScreenResource.h"
#include "SDL_Toolkit.h"
#include "TextArea.h"

GameApplication* GameApplication::instance = 0;

GameApplication::GameApplication()
: mediaToolkit(SDL_Toolkit::GetInstance())
{
  mediaToolkit->GetVideo()->SetScaling(2);
  mediaToolkit->GetVideo()->CreateScreen(VIDEO_WIDTH, VIDEO_HEIGHT);
  mediaToolkit->GetVideo()->Clear();

  PaletteResource pal;
  pal.Fill();
  pal.Activate(mediaToolkit->GetVideo(), 0, VIDEO_COLORS);
  FontResource fnt;
  ResourceManager::GetInstance()->Load(&fnt, "GAME.FNT");
  TextArea ta(240, 16, fnt);
  ta.SetText("xBaK: Betrayal at Krondor  A fan-made remake");
  ta.SetColor(15);
  ta.Draw(mediaToolkit->GetVideo(), 16, 16);
  mediaToolkit->GetVideo()->Refresh();
  mediaToolkit->GetClock()->Delay(1000);

  MousePointerManager::GetInstance()->AddPointer("POINTER.BMX");
  MousePointerManager::GetInstance()->AddPointer("POINTERG.BMX");
}

GameApplication::~GameApplication()
{
  delete MousePointerManager::GetInstance();
  delete mediaToolkit;
  delete ResourceManager::GetInstance();
  delete ResourcePath::GetInstance();
}

GameApplication*
GameApplication::GetInstance()
{
  if (!instance) {
    instance = new GameApplication();
  }
  return instance;
}

void
GameApplication::Intro()
{
  try {
    AnimationResource anim;
    ResourceManager::GetInstance()->Load(&anim, "INTRO.ADS");
    MovieResource ttm;
    ResourceManager::GetInstance()->Load(&ttm, anim.GetAnimationData(1).resource);
    MoviePlayer moviePlayer(mediaToolkit);
    moviePlayer.Play(&ttm.GetMovieTags(), true);
  } catch (Exception &e) {
    e.Print("GameApplication::Intro");
  }
}

void
GameApplication::Run()
{
  try {
    mediaToolkit->GetVideo()->SetPointerPosition(0, 0);
    OptionsDialog options(mediaToolkit);
    options.Run();
  } catch (Exception &e) {
    e.Print("GameApplication::Run");
  }
}
