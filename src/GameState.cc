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

GameStateCamp::GameStateCamp(GameApplication *app)
{
  dialog = new Dialog(app->GetMediaToolkit());
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
GameStateCamp::GetInstance(GameApplication *app)
{
  if (!instance) {
    instance = new GameStateCamp(app);
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
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case CAMP_EXIT:
      ChangeState(app, app->GetPrevState());
      break;
    case CAMP_UNTIL_HEALED:
    case CAMP_STOP:
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStateCast* GameStateCast::instance = 0;

GameStateCast::GameStateCast(GameApplication *app)
{
  dialog = new Dialog(app->GetMediaToolkit());
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("FRAME.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_CAST.DAT");
  dialog->SetHeads("HEADS.BMX");
  dialog->SetMembers(app->GetGame()->GetParty(), SPECIAL_TYPE1);
}

GameStateCast::~GameStateCast()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateCast*
GameStateCast::GetInstance(GameApplication *app)
{
  if (!instance) {
    instance = new GameStateCast(app);
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
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case CAST_EXIT:
      app->GetGame()->GetParty()->SelectMember(-1);
      ChangeState(app, GameStateWorld::GetInstance(app));
      break;
    case CAST_CAMP1:
    case CAST_CAMP2:
      ChangeState(app, GameStateCamp::GetInstance(app));
      break;
    case CAST_MEMBER1:
      app->GetGame()->GetParty()->SelectMember(0);
      break;
    case CAST_MEMBER2:
      app->GetGame()->GetParty()->SelectMember(1);
      break;
    case CAST_MEMBER3:
      app->GetGame()->GetParty()->SelectMember(2);
      break;
    case CAST_TRIANGLE:
    case CAST_SQUARE:
    case CAST_CAST:
    case CAST_BOOKMARK:
    case CAST_MEMBER1 + RIGHT_CLICK_OFFSET:
    case CAST_MEMBER2 + RIGHT_CLICK_OFFSET:
    case CAST_MEMBER3 + RIGHT_CLICK_OFFSET:
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
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
  ChangeState(app, GameStateWorld::GetInstance(app));
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
  ChangeState(app, GameStateWorld::GetInstance(app));
}

GameStateContents* GameStateContents::instance = 0;

GameStateContents::GameStateContents(GameApplication *app)
{
  dialog = new Dialog(app->GetMediaToolkit());
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
GameStateContents::GetInstance(GameApplication *app)
{
  if (!instance) {
    instance = new GameStateContents(app);
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
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case CONT_EXIT:
      ChangeState(app, app->GetPrevState());
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStateFullMap* GameStateFullMap::instance = 0;

GameStateFullMap::GameStateFullMap(GameApplication *app)
{
  dialog = new Dialog(app->GetMediaToolkit());
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
GameStateFullMap::GetInstance(GameApplication *app)
{
  if (!instance) {
    instance = new GameStateFullMap(app);
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
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case FMAP_EXIT:
      ChangeState(app, GameStateMap::GetInstance(app));
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
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
  ChangeState(app, GameStateOptions::GetInstance(app));
}

GameStateInventory* GameStateInventory::instance = 0;

GameStateInventory::GameStateInventory(GameApplication *app)
{
  dialog = new Dialog(app->GetMediaToolkit());
  dialog->SetFont("GAME.FNT");
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("FRAME.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_INV.DAT");
  dialog->SetHeads("HEADS.BMX");
  dialog->SetMembers(app->GetGame()->GetParty(), SPECIAL_TYPE2);
}

GameStateInventory::~GameStateInventory()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateInventory*
GameStateInventory::GetInstance(GameApplication *app)
{
  if (!instance) {
    instance = new GameStateInventory(app);
  }
  return instance;
}

void
GameStateInventory::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

void
GameStateInventory::Execute(GameApplication *app)
{
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case INV_EXIT:
      app->GetGame()->GetParty()->SelectMember(-1);
      ChangeState(app, app->GetPrevState());
      break;
    case INV_MEMBER1:
      app->GetGame()->GetParty()->SelectMember(0);
      break;
    case INV_MEMBER2:
      app->GetGame()->GetParty()->SelectMember(1);
      break;
    case INV_MEMBER3:
      app->GetGame()->GetParty()->SelectMember(2);
      break;
    case INV_UNKNOWN:
    case INV_MORE_INFO:
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStateLoad* GameStateLoad::instance = 0;

GameStateLoad::GameStateLoad(GameApplication *app)
{
  dialog = new Dialog(app->GetMediaToolkit());
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
GameStateLoad::GetInstance(GameApplication *app)
{
  if (!instance) {
    instance = new GameStateLoad(app);
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
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case LOAD_CANCEL:
      ChangeState(app, app->GetPrevState());
      break;
    case LOAD_RESTORE:
      ChangeState(app, app->GetPrevState());
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStateMap* GameStateMap::instance = 0;

GameStateMap::GameStateMap(GameApplication *app)
{
  dialog = new Dialog(app->GetMediaToolkit());
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("FRAME.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_MAP.DAT");
  dialog->SetHeads("HEADS.BMX");
  dialog->SetMembers(app->GetGame()->GetParty(), SPECIAL_TYPE1);
}

GameStateMap::~GameStateMap()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateMap*
GameStateMap::GetInstance(GameApplication *app)
{
  if (!instance) {
    instance = new GameStateMap(app);
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
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case MAP_MAIN:
      ChangeState(app, GameStateWorld::GetInstance(app));
      break;
    case MAP_CAMP:
      ChangeState(app, GameStateCamp::GetInstance(app));
      break;
    case MAP_FULLMAP:
      ChangeState(app, GameStateFullMap::GetInstance(app));
      break;
    case MAP_UP:
    case MAP_DOWN:
    case MAP_LEFT:
    case MAP_RIGHT:
    case MAP_ZOOMIN:
    case MAP_ZOOMOUT:
    case MAP_UNKNOWN:
    case MAP_MEMBER1:
    case MAP_MEMBER2:
    case MAP_MEMBER3:
    case MAP_MEMBER1 + RIGHT_CLICK_OFFSET:
    case MAP_MEMBER2 + RIGHT_CLICK_OFFSET:
    case MAP_MEMBER3 + RIGHT_CLICK_OFFSET:
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStateOptions* GameStateOptions::instance = 0;

GameStateOptions::GameStateOptions(GameApplication *app)
: firstTime(true)
{
  dialog = new Dialog(app->GetMediaToolkit());
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
GameStateOptions::GetInstance(GameApplication *app)
{
  if (!instance) {
    instance = new GameStateOptions(app);
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
  unsigned int action = dialog->Execute();
  switch (action) {
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
      ChangeState(app, GameStateWorld::GetInstance(app));
      break;
    case OPT_CONTENTS:
      ChangeState(app, GameStateContents::GetInstance(app));
      break;
    case OPT_PREFERENCES:
      ChangeState(app, GameStatePreferences::GetInstance(app));
      break;
    case OPT_RESTORE:
      ChangeState(app, GameStateLoad::GetInstance(app));
      break;
    case OPT_SAVE:
      ChangeState(app, GameStateSave::GetInstance(app));
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStatePreferences* GameStatePreferences::instance = 0;

GameStatePreferences::GameStatePreferences(GameApplication *app)
{
  dialog = new Dialog(app->GetMediaToolkit());
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
GameStatePreferences::GetInstance(GameApplication *app)
{
  if (!instance) {
    instance = new GameStatePreferences(app);
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
  unsigned int action = dialog->Execute();
  switch (action) {
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
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStateSave* GameStateSave::instance = 0;

GameStateSave::GameStateSave(GameApplication *app)
{
  dialog = new Dialog(app->GetMediaToolkit());
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
GameStateSave::GetInstance(GameApplication *app)
{
  if (!instance) {
    instance = new GameStateSave(app);
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
  unsigned int action = dialog->Execute();
  switch (action) {
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
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStateWorld* GameStateWorld::instance = 0;

GameStateWorld::GameStateWorld(GameApplication *app)
{
  dialog = new Dialog(app->GetMediaToolkit());
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("FRAME.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_MAIN.DAT");
  dialog->SetHeads("HEADS.BMX");
  dialog->SetMembers(app->GetGame()->GetParty(), SPECIAL_TYPE1);
}

GameStateWorld::~GameStateWorld()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateWorld*
GameStateWorld::GetInstance(GameApplication *app)
{
  if (!instance) {
    instance = new GameStateWorld(app);
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
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case MAIN_OPTIONS:
      ChangeState(app, GameStateOptions::GetInstance(app));
      break;
    case MAIN_CAMP:
      ChangeState(app, GameStateCamp::GetInstance(app));
      break;
    case MAIN_CAST:
      app->GetGame()->GetParty()->SelectMember(0);
      ChangeState(app, GameStateCast::GetInstance(app));
      break;
    case MAIN_MAP:
      ChangeState(app, GameStateMap::GetInstance(app));
      break;
    case MAIN_MEMBER1:
      app->GetGame()->GetParty()->SelectMember(0);
      ChangeState(app, GameStateInventory::GetInstance(app));
      break;
    case MAIN_MEMBER2:
      app->GetGame()->GetParty()->SelectMember(1);
      ChangeState(app, GameStateInventory::GetInstance(app));
      break;
    case MAIN_MEMBER3:
      app->GetGame()->GetParty()->SelectMember(2);
      ChangeState(app, GameStateInventory::GetInstance(app));
      break;
    case MAIN_UP:
    case MAIN_DOWN:
    case MAIN_LEFT:
    case MAIN_RIGHT:
    case MAIN_BOOKMARK:
    case MAIN_UNKNOWN:
    case MAIN_MEMBER1 + RIGHT_CLICK_OFFSET:
    case MAIN_MEMBER2 + RIGHT_CLICK_OFFSET:
    case MAIN_MEMBER3 + RIGHT_CLICK_OFFSET:
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}
