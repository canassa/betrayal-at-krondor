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

GameStateCamp* GameStateCamp::instance = 0;

GameStateCamp::GameStateCamp(MediaToolkit *mtk)
{
  dialog = new Dialog(mtk);
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("ENCAMP.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_CAMP.DAT");
}

GameStateCamp::~GameStateCamp()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateCamp*
GameStateCamp::GetInstance(MediaToolkit *mtk)
{
  if (!instance) {
    instance = new GameStateCamp(mtk);
  }
  return instance;
}

void
GameStateCamp::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateCamp::Execute(GameApplication *app)
{
  switch (dialog->Execute()) {
    case ACT_ESCAPE:
    case CAMP_EXIT:
      ChangeState(app, app->GetPrevState());
      break;
    case CAMP_UNTIL_HEALED:
    case CAMP_STOP:
      break;
    default:
      throw UnexpectedValue("GameStateCamp::Execute");
      break;
  }
}

GameStateCast* GameStateCast::instance = 0;

GameStateCast::GameStateCast(MediaToolkit *mtk)
{
  dialog = new Dialog(mtk);
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("FRAME.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_CAST.DAT");
}

GameStateCast::~GameStateCast()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateCast*
GameStateCast::GetInstance(MediaToolkit *mtk)
{
  if (!instance) {
    instance = new GameStateCast(mtk);
  }
  return instance;
}

void
GameStateCast::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateCast::Execute(GameApplication *app)
{
  switch (dialog->Execute()) {
    case ACT_ESCAPE:
    case CAST_EXIT:
      ChangeState(app, GameStateWorld::GetInstance(app->GetMediaToolkit()));
      break;
    case CAST_CAMP1:
    case CAST_CAMP2:
      ChangeState(app, GameStateCamp::GetInstance(app->GetMediaToolkit()));
      break;
    case CAST_TRIANGLE:
    case CAST_SQUARE:
    case CAST_CAST:
    case CAST_BOOKMARK:
      break;
    default:
      throw UnexpectedValue("GameStateCast::Execute");
      break;
  }
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
  ChangeState(app, GameStateWorld::GetInstance(app->GetMediaToolkit()));
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
  ChangeState(app, GameStateWorld::GetInstance(app->GetMediaToolkit()));
}

GameStateContents* GameStateContents::instance = 0;

GameStateContents::GameStateContents(MediaToolkit *mtk)
{
  dialog = new Dialog(mtk);
  dialog->SetPalette("CONTENTS.PAL");
  dialog->SetScreen("CONT2.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
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

GameStateFullMap* GameStateFullMap::instance = 0;

GameStateFullMap::GameStateFullMap(MediaToolkit *mtk)
{
  dialog = new Dialog(mtk);
  dialog->SetPalette("FULLMAP.PAL");
  dialog->SetScreen("FULLMAP.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_FMAP.DAT");
}

GameStateFullMap::~GameStateFullMap()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateFullMap*
GameStateFullMap::GetInstance(MediaToolkit *mtk)
{
  if (!instance) {
    instance = new GameStateFullMap(mtk);
  }
  return instance;
}

void
GameStateFullMap::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateFullMap::Execute(GameApplication *app)
{
  switch (dialog->Execute()) {
    case ACT_ESCAPE:
    case FMAP_EXIT:
      ChangeState(app, GameStateMap::GetInstance(app->GetMediaToolkit()));
      break;
    default:
      throw UnexpectedValue("GameStateFullMap::Execute");
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

GameStateMap* GameStateMap::instance = 0;

GameStateMap::GameStateMap(MediaToolkit *mtk)
{
  dialog = new Dialog(mtk);
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("FRAME.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_MAP.DAT");
}

GameStateMap::~GameStateMap()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateMap*
GameStateMap::GetInstance(MediaToolkit *mtk)
{
  if (!instance) {
    instance = new GameStateMap(mtk);
  }
  return instance;
}

void
GameStateMap::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateMap::Execute(GameApplication *app)
{
  switch (dialog->Execute()) {
    case ACT_ESCAPE:
    case MAP_MAIN:
      ChangeState(app, GameStateWorld::GetInstance(app->GetMediaToolkit()));
      break;
    case MAP_CAMP:
      ChangeState(app, GameStateCamp::GetInstance(app->GetMediaToolkit()));
      break;
    case MAP_FULLMAP:
      ChangeState(app, GameStateFullMap::GetInstance(app->GetMediaToolkit()));
      break;
    case MAP_UP:
    case MAP_DOWN:
    case MAP_LEFT:
    case MAP_RIGHT:
    case MAP_ZOOMIN:
    case MAP_ZOOMOUT:
    case MAP_UNKNOWN:
      break;
    default:
      throw UnexpectedValue("GameStateMap::Execute");
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
      ChangeState(app, GameStateWorld::GetInstance(app->GetMediaToolkit()));
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
      throw UnexpectedValue("GameStateOptions::Execute");
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

GameStateWorld::GameStateWorld(MediaToolkit *mtk)
{
  dialog = new Dialog(mtk);
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("FRAME.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_MAIN.DAT");
}

GameStateWorld::~GameStateWorld()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateWorld*
GameStateWorld::GetInstance(MediaToolkit *mtk)
{
  if (!instance) {
    instance = new GameStateWorld(mtk);
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
  switch (dialog->Execute()) {
    case ACT_ESCAPE:
    case MAIN_OPTIONS:
      ChangeState(app, GameStateOptions::GetInstance(app->GetMediaToolkit()));
      break;
    case MAIN_CAMP:
      ChangeState(app, GameStateCamp::GetInstance(app->GetMediaToolkit()));
      break;
    case MAIN_CAST:
      ChangeState(app, GameStateCast::GetInstance(app->GetMediaToolkit()));
      break;
    case MAIN_MAP:
      ChangeState(app, GameStateMap::GetInstance(app->GetMediaToolkit()));
      break;
    case MAIN_UP:
    case MAIN_DOWN:
    case MAIN_LEFT:
    case MAIN_RIGHT:
    case MAIN_BOOKMARK:
    case MAIN_UNKNOWN:
      break;
    default:
      throw UnexpectedValue("GameStateWorld::Execute");
      break;
  }
}
