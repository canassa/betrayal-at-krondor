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

#include "GameApplication.h"
#include "GameState.h"
#include "OptionsDialog.h"

GameState::GameState()
{
}

GameState::~GameState()
{
}

void
GameState::ChangeState(GameApplication *app, GameState *state)
{
  app->SetState(state);
}

void
GameState::Execute(GameApplication *app)
{
  app = app;
}

GameStateChapter* GameStateChapter::instance = 0;

GameStateChapter::GameStateChapter()
{
}

GameStateChapter::~GameStateChapter()
{
}

GameStateChapter*
GameStateChapter::GetInstance()
{
  if (!instance) {
    instance = new GameStateChapter();
  }
  return instance;
}

void
GameStateChapter::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateChapter::Execute(GameApplication *app)
{
  app->StartChapter();
  ChangeState(app, GameStateWorld::GetInstance());
}

GameStateCombat* GameStateCombat::instance = 0;

GameStateCombat::GameStateCombat()
{
}

GameStateCombat::~GameStateCombat()
{
}

GameStateCombat*
GameStateCombat::GetInstance()
{
  if (!instance) {
    instance = new GameStateCombat();
  }
  return instance;
}

void
GameStateCombat::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateCombat::Execute(GameApplication *app)
{
  ChangeState(app, GameStateWorld::GetInstance());
}

GameStateIntro* GameStateIntro::instance = 0;

GameStateIntro::GameStateIntro()
{
}

GameStateIntro::~GameStateIntro()
{
}

GameStateIntro*
GameStateIntro::GetInstance()
{
  if (!instance) {
    instance = new GameStateIntro();
  }
  return instance;
}

void
GameStateIntro::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateIntro::Execute(GameApplication *app)
{
  app->PlayIntro();
  ChangeState(app, GameStateOptions::GetInstance());
}

GameStateOptions* GameStateOptions::instance = 0;

GameStateOptions::GameStateOptions()
: firstTime(true)
{
}

GameStateOptions::~GameStateOptions()
{
}

GameStateOptions*
GameStateOptions::GetInstance()
{
  if (!instance) {
    instance = new GameStateOptions();
  }
  return instance;
}

void
GameStateOptions::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateOptions::Execute(GameApplication *app)
{
  switch (app->Options(firstTime)) {
    case UA_CANCEL:
      break;
    case UA_NEW_GAME:
      app->StartNewGame();
      ChangeState(app, GameStateChapter::GetInstance());
      break;
    case UA_QUIT:
      app->QuitGame();
      break;
    case UA_RESTORE:
      break;
    case UA_SAVE:
      break;
    case UA_UNKNOWN:
      break;
  }
  firstTime = false;
}

GameStateWorld* GameStateWorld::instance = 0;

GameStateWorld::GameStateWorld()
{
}

GameStateWorld::~GameStateWorld()
{
}

GameStateWorld*
GameStateWorld::GetInstance()
{
  if (!instance) {
    instance = new GameStateWorld();
  }
  return instance;
}

void
GameStateWorld::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateWorld::Execute(GameApplication *app)
{
  ChangeState(app, GameStateOptions::GetInstance());
}
