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
#include "GameApplication.h"
#include "GameState.h"

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

GameStateContents* GameStateContents::instance = 0;

GameStateContents::GameStateContents(MediaToolkit *mtk)
{
  dialog = new Dialog(mtk);
  dialog->SetPalette("CONTENTS.PAL");
  dialog->SetScreen("CONT2.SCX");
  dialog->SetRequest("CONTENTS.DAT");
}

GameStateContents::~GameStateContents()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateContents*
GameStateContents::GetInstance(MediaToolkit *mtk)
{
  if (!instance) {
    instance = new GameStateContents(mtk);
  }
  return instance;
}

void
GameStateContents::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateContents::Execute(GameApplication *app)
{
  switch (dialog->Execute()) {
    case ACT_ESCAPE:
    case CONT_EXIT:
      ChangeState(app, app->GetPrevState());
      break;
    default:
      throw UnexpectedValue("GameStateContents::Execute");
      break;
  }
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
  ChangeState(app, GameStateOptions::GetInstance(app->GetMediaToolkit()));
}

GameStateLoad* GameStateLoad::instance = 0;

GameStateLoad::GameStateLoad(MediaToolkit *mtk)
{
  dialog = new Dialog(mtk);
  dialog->SetFont("GAME.FNT");
  dialog->SetLabel("LBL_LOAD.DAT");
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("OPTIONS2.SCX");
  dialog->SetRequest("REQ_LOAD.DAT");
}

GameStateLoad::~GameStateLoad()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateLoad*
GameStateLoad::GetInstance(MediaToolkit *mtk)
{
  if (!instance) {
    instance = new GameStateLoad(mtk);
  }
  return instance;
}

void
GameStateLoad::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateLoad::Execute(GameApplication *app)
{
  switch (dialog->Execute()) {
    case ACT_ESCAPE:
    case LOAD_CANCEL:
      ChangeState(app, app->GetPrevState());
      break;
    case LOAD_RESTORE:
      ChangeState(app, app->GetPrevState());
      break;
    default:
      throw UnexpectedValue("GameStateLoad::Execute");
      break;
  }
}

GameStateOptions* GameStateOptions::instance = 0;

GameStateOptions::GameStateOptions(MediaToolkit *mtk)
: firstTime(true)
{
  dialog = new Dialog(mtk);
  dialog->SetFont("GAME.FNT");
  dialog->SetPalette("OPTIONS.PAL");
}

GameStateOptions::~GameStateOptions()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateOptions*
GameStateOptions::GetInstance(MediaToolkit *mtk)
{
  if (!instance) {
    instance = new GameStateOptions(mtk);
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
  if (firstTime) {
    dialog->SetScreen("OPTIONS0.SCX");
    dialog->SetRequest("REQ_OPT0.DAT");
  } else {
    dialog->SetScreen("OPTIONS1.SCX");
    dialog->SetRequest("REQ_OPT1.DAT");
  }
  switch (dialog->Execute()) {
    case ACT_ESCAPE:
    case OPT_QUIT:
      app->QuitGame();
      break;
    case OPT_NEW_GAME:
      app->StartNewGame();
      firstTime = false;
      ChangeState(app, GameStateChapter::GetInstance());
      break;
    case OPT_CANCEL:
      ChangeState(app, app->GetPrevState());
      break;
    case OPT_CONTENTS:
      ChangeState(app, GameStateContents::GetInstance(app->GetMediaToolkit()));
      break;
    case OPT_PREFERENCES:
      ChangeState(app, GameStatePreferences::GetInstance(app->GetMediaToolkit()));
      break;
    case OPT_RESTORE:
      ChangeState(app, GameStateLoad::GetInstance(app->GetMediaToolkit()));
      break;
    case OPT_SAVE:
      ChangeState(app, GameStateSave::GetInstance(app->GetMediaToolkit()));
      break;
    default:
      throw UnexpectedValue("GameStatePreferences::Execute");
      break;
  }
}

GameStatePreferences* GameStatePreferences::instance = 0;

GameStatePreferences::GameStatePreferences(MediaToolkit *mtk)
{
  dialog = new Dialog(mtk);
  dialog->SetFont("GAME.FNT");
  dialog->SetLabel("LBL_PREF.DAT");
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("OPTIONS2.SCX");
  dialog->SetRequest("REQ_PREF.DAT");
}

GameStatePreferences::~GameStatePreferences()
{
  if (dialog) {
    delete dialog;
  }
}

GameStatePreferences*
GameStatePreferences::GetInstance(MediaToolkit *mtk)
{
  if (!instance) {
    instance = new GameStatePreferences(mtk);
  }
  return instance;
}

void
GameStatePreferences::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStatePreferences::Execute(GameApplication *app)
{
  switch (dialog->Execute()) {
    case ACT_ESCAPE:
    case PREF_CANCEL:
      ChangeState(app, app->GetPrevState());
      break;
    case PREF_OK:
      ChangeState(app, app->GetPrevState());
      break;
    case PREF_DEFAULTS:
      break;
    default:
      throw UnexpectedValue("GameStatePreferences::Execute");
      break;
  }
}

GameStateSave* GameStateSave::instance = 0;

GameStateSave::GameStateSave(MediaToolkit *mtk)
{
  dialog = new Dialog(mtk);
  dialog->SetFont("GAME.FNT");
  dialog->SetLabel("LBL_SAVE.DAT");
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("OPTIONS2.SCX");
  dialog->SetRequest("REQ_SAVE.DAT");
}

GameStateSave::~GameStateSave()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateSave*
GameStateSave::GetInstance(MediaToolkit *mtk)
{
  if (!instance) {
    instance = new GameStateSave(mtk);
  }
  return instance;
}

void
GameStateSave::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateSave::Execute(GameApplication *app)
{
  switch (dialog->Execute()) {
    case ACT_ESCAPE:
    case SAVE_CANCEL:
      ChangeState(app, app->GetPrevState());
      break;
    case SAVE_SAVE:
      ChangeState(app, app->GetPrevState());
      break;
    case SAVE_REMOVE_GAME:
      break;
    case SAVE_REMOVE_DIR:
      break;
    default:
      throw UnexpectedValue("GameStateSave::Execute");
      break;
  }
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
  app->PlayGame();
  ChangeState(app, GameStateOptions::GetInstance(app->GetMediaToolkit()));
}
