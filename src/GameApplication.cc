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

#include <iomanip>
#include <sstream>

#include "AnimationResource.h"
#include "Exception.h"
#include "FileManager.h"
#include "FontResource.h"
#include "GameApplication.h"
#include "GamePath.h"
#include "MousePointerManager.h"
#include "MoviePlayer.h"
#include "MovieResource.h"
#include "PaletteResource.h"
#include "ResourcePath.h"
#include "ScreenResource.h"
#include "SDL_Toolkit.h"
#include "TextArea.h"

GameApplication* GameApplication::instance = 0;

GameApplication::GameApplication()
: mediaToolkit(SDL_Toolkit::GetInstance())
, done(false)
, inputGrabbed(false)
, game(0)
, state(GameStateIntro::GetInstance())
, prevState(0)
, chapter(mediaToolkit)
, screenSaveCount(0)
{
  mediaToolkit->GetVideo()->SetScaling(2);
  mediaToolkit->GetVideo()->CreateScreen(VIDEO_WIDTH, VIDEO_HEIGHT);
  mediaToolkit->GetVideo()->Clear();
  game = new Game();
  GamePath::GetInstance();

  PaletteResource pal;
  pal.Fill();
  pal.Activate(mediaToolkit->GetVideo(), 0, VIDEO_COLORS);
  FontResource fnt;
  FileManager::GetInstance()->Load(&fnt, "GAME.FNT");
  TextArea ta(240, 16, fnt);
  ta.SetText("xBaK: Betrayal at Krondor  A fan-made remake");
  ta.SetColor(15);
  ta.Draw(mediaToolkit->GetVideo(), 16, 16);
  mediaToolkit->GetVideo()->Refresh();
  mediaToolkit->GetClock()->Delay(500);
  mediaToolkit->AddKeyboardListener(this);
  mediaToolkit->AddMouseButtonListener(this);

  MousePointerManager::GetInstance()->AddPointer("POINTER.BMX");
  MousePointerManager::GetInstance()->AddPointer("POINTERG.BMX");
  MousePointerManager::GetInstance()->Register(mediaToolkit);
}

GameApplication::~GameApplication()
{
  mediaToolkit->RemoveKeyboardListener(this);
  MousePointerManager::CleanUp();
  delete game;
  delete mediaToolkit;
  SoundResource::CleanUp();
  FileManager::CleanUp();
  ResourcePath::CleanUp();
  GamePath::CleanUp();
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
GameApplication::CleanUp()
{
  GameStateCast::CleanUp();
  GameStateCamp::CleanUp();
  GameStateChapter::CleanUp();
  GameStateCombat::CleanUp();
  GameStateContents::CleanUp();
  GameStateFullMap::CleanUp();
  GameStateIntro::CleanUp();
  GameStateLoad::CleanUp();
  GameStateMap::CleanUp();
  GameStateOptions::CleanUp();
  GameStatePreferences::CleanUp();
  GameStateSave::CleanUp();
  GameStateWorld::CleanUp();
  if (instance) {
    delete instance;
    instance = 0;
  }
}

MediaToolkit *
GameApplication::GetMediaToolkit()
{
  return mediaToolkit;
}

Game *
GameApplication::GetGame()
{
  return game;
}

GameState *
GameApplication::GetPrevState()
{
  return prevState;
}

void
GameApplication::SetState(GameState *st)
{
  prevState = state;
  state = st;
}

void
GameApplication::PlayIntro()
{
  try {
    AnimationResource anim;
    FileManager::GetInstance()->Load(&anim, "INTRO.ADS");
    MovieResource ttm;
    FileManager::GetInstance()->Load(&ttm, anim.GetAnimationData(1).resource);
    MoviePlayer moviePlayer(mediaToolkit);
    moviePlayer.Play(&ttm.GetMovieTags(), true);
  } catch (Exception &e) {
    e.Print("GameApplication::Intro");
  }
}

void
GameApplication::StartChapter()
{
  try {
    chapter.PlayIntro();
    chapter.ReadBook(1);
    chapter.PlayScene(1);
    chapter.ShowMap();
  } catch (Exception &e) {
    e.Print("GameApplication::StartChapter");
  }
}

void
GameApplication::StartNewGame()
{
  chapter.SetCurrent(1);
}

void
GameApplication::QuitGame()
{
  done = true;
}

void
GameApplication::Run()
{
  try {
    done = false;
    while (!done) {
      state->Execute(this);
    }
  } catch (Exception &e) {
    e.Print("GameApplication::Run");
  }
}

void
GameApplication::KeyPressed(const KeyboardEvent& kbe)
{
  switch (kbe.GetKey()){
    case KEY_F11:
      {
        screenSaveCount++;
        std::stringstream filenameStream;
        filenameStream << "xbak_" << std::setw(3) << std::setfill('0') << screenSaveCount << ".bmp";
        mediaToolkit->GetVideo()->SaveScreenShot(filenameStream.str());
      }
      break;
    case KEY_F12:
      inputGrabbed = !inputGrabbed;
      mediaToolkit->GetVideo()->GrabInput(inputGrabbed);
      break;
    default:
      break;
  }
}

void
GameApplication::KeyReleased(const KeyboardEvent& kbe)
{
  switch (kbe.GetKey()){
    default:
      break;
  }
}

void
GameApplication::MouseButtonPressed(const MouseButtonEvent& mbe)
{
  switch (mbe.GetButton()){
    case MB_LEFT:
    case MB_RIGHT:
      if (!inputGrabbed) {
        inputGrabbed = true;
        mediaToolkit->GetVideo()->GrabInput(true);
      }
      break;
    case MB_MIDDLE:
      if (inputGrabbed) {
        inputGrabbed = false;
        mediaToolkit->GetVideo()->GrabInput(false);
      }
      break;
    default:
      break;
  }
}

void
GameApplication::MouseButtonReleased(const MouseButtonEvent& mbe)
{
  switch (mbe.GetButton()){
    default:
      break;
  }
}
