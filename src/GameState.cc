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
GameState::ChangeState(GameState *state)
{
  GameApplication::GetInstance()->SetState(state);
}

void
GameState::Enter()
{
}

void
GameState::Leave()
{
}

void
GameState::Execute()
{
}

GameStateCamp* GameStateCamp::instance = 0;

GameStateCamp::GameStateCamp()
{
  dialog = new GameDialog();
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
GameStateCamp::GetInstance()
{
  if (!instance) {
    instance = new GameStateCamp();
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
GameStateCamp::Enter()
{
  dialog->Enter();
}

void
GameStateCamp::Leave()
{
  dialog->Leave();
}

void
GameStateCamp::Execute()
{
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case CAMP_EXIT:
      ChangeState(GameApplication::GetInstance()->GetPrevState());
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

GameStateCast::GameStateCast()
{
  dialog = new GameDialog();
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("FRAME.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_CAST.DAT");
  dialog->SetHeads("HEADS.BMX");
  dialog->SetMembers(GameApplication::GetInstance()->GetGame()->GetParty(), GROUP2);
  dialog->SetCamera(GameApplication::GetInstance()->GetGame()->GetCamera());
  dialog->SetCompass("COMPASS.BMX");
}

GameStateCast::~GameStateCast()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateCast*
GameStateCast::GetInstance()
{
  if (!instance) {
    instance = new GameStateCast();
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
GameStateCast::Enter()
{
  dialog->Enter();
}

void
GameStateCast::Leave()
{
  dialog->Leave();
}

void
GameStateCast::Execute()
{
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case CAST_EXIT:
      GameApplication::GetInstance()->GetGame()->GetParty()->SelectMember(-1);
      ChangeState(GameStateWorld::GetInstance());
      break;
    case CAST_CAMP1:
    case CAST_CAMP2:
      ChangeState(GameStateCamp::GetInstance());
      break;
    case CAST_MEMBER1:
      GameApplication::GetInstance()->GetGame()->GetParty()->SelectMember(0);
      break;
    case CAST_MEMBER2:
      GameApplication::GetInstance()->GetGame()->GetParty()->SelectMember(1);
      break;
    case CAST_MEMBER3:
      GameApplication::GetInstance()->GetGame()->GetParty()->SelectMember(2);
      break;
    case ACT_UP:
    case ACT_DOWN:
    case ACT_LEFT:
    case ACT_RIGHT:
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
GameStateChapter::Execute()
{
  GameApplication::GetInstance()->GetGame()->GetChapter()->Start();
  ChangeState(GameStateWorld::GetInstance());
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
GameStateCombat::Execute()
{
  ChangeState(GameStateWorld::GetInstance());
}

GameStateContents* GameStateContents::instance = 0;

GameStateContents::GameStateContents()
{
  dialog = new OptionsDialog();
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
GameStateContents::GetInstance()
{
  if (!instance) {
    instance = new GameStateContents();
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
GameStateContents::Enter()
{
  dialog->Enter();
}

void
GameStateContents::Leave()
{
  dialog->Leave();
}

void
GameStateContents::Execute()
{
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case CONT_EXIT:
      ChangeState(GameApplication::GetInstance()->GetPrevState());
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStateFullMap* GameStateFullMap::instance = 0;

GameStateFullMap::GameStateFullMap()
{
  dialog = new GameDialog();
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
GameStateFullMap::GetInstance()
{
  if (!instance) {
    instance = new GameStateFullMap();
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
GameStateFullMap::Enter()
{
  dialog->Enter();
}

void
GameStateFullMap::Leave()
{
  dialog->Leave();
}

void
GameStateFullMap::Execute()
{
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case FMAP_EXIT:
      ChangeState(GameStateMap::GetInstance());
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
GameStateIntro::Execute()
{
  GameApplication::GetInstance()->PlayIntro();
  ChangeState(GameStateOptions::GetInstance());
}

GameStateInventory* GameStateInventory::instance = 0;

GameStateInventory::GameStateInventory()
{
  dialog = new GameDialog();
  dialog->SetFont("GAME.FNT");
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("FRAME.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_INV.DAT");
  dialog->SetHeads("HEADS.BMX");
  dialog->SetMembers(GameApplication::GetInstance()->GetGame()->GetParty(), GROUP3);
  dialog->SetCamera(GameApplication::GetInstance()->GetGame()->GetCamera());
  dialog->SetCompass("COMPASS.BMX");
}

GameStateInventory::~GameStateInventory()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateInventory*
GameStateInventory::GetInstance()
{
  if (!instance) {
    instance = new GameStateInventory();
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
GameStateInventory::Enter()
{
  dialog->Enter();
}

void
GameStateInventory::Leave()
{
  dialog->Leave();
}

void
GameStateInventory::Execute()
{
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case INV_EXIT:
      GameApplication::GetInstance()->GetGame()->GetParty()->SelectMember(-1);
      ChangeState(GameApplication::GetInstance()->GetPrevState());
      break;
    case INV_MEMBER1:
      GameApplication::GetInstance()->GetGame()->GetParty()->SelectMember(0);
      break;
    case INV_MEMBER2:
      GameApplication::GetInstance()->GetGame()->GetParty()->SelectMember(1);
      break;
    case INV_MEMBER3:
      GameApplication::GetInstance()->GetGame()->GetParty()->SelectMember(2);
      break;
    case ACT_UP:
    case ACT_DOWN:
    case ACT_LEFT:
    case ACT_RIGHT:
    case INV_UNKNOWN:
    case INV_MORE_INFO:
    case INV_MEMBER1 + RIGHT_CLICK_OFFSET:
    case INV_MEMBER2 + RIGHT_CLICK_OFFSET:
    case INV_MEMBER3 + RIGHT_CLICK_OFFSET:
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStateLoad* GameStateLoad::instance = 0;

GameStateLoad::GameStateLoad()
{
  dialog = new OptionsDialog();
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
GameStateLoad::GetInstance()
{
  if (!instance) {
    instance = new GameStateLoad();
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
GameStateLoad::Enter()
{
  dialog->Enter();
}

void
GameStateLoad::Leave()
{
  dialog->Leave();
}

void
GameStateLoad::Execute()
{
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case LOAD_CANCEL:
      ChangeState(GameApplication::GetInstance()->GetPrevState());
      break;
    case LOAD_RESTORE:
      ChangeState(GameApplication::GetInstance()->GetPrevState());
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStateMap* GameStateMap::instance = 0;

GameStateMap::GameStateMap()
{
  dialog = new GameDialog();
  dialog->SetPalette("OPTIONS.PAL");
  dialog->SetScreen("FRAME.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_MAP.DAT");
  dialog->SetHeads("HEADS.BMX");
  dialog->SetMembers(GameApplication::GetInstance()->GetGame()->GetParty(), GROUP2);
  dialog->SetCamera(GameApplication::GetInstance()->GetGame()->GetCamera());
  dialog->SetCompass("COMPASS.BMX");
  dialog->SetGameView(GameApplication::GetInstance()->GetGame(), GROUP3, GVT_MAP);
}

GameStateMap::~GameStateMap()
{
  if (dialog) {
    delete dialog;
  }
}

GameStateMap*
GameStateMap::GetInstance()
{
  if (!instance) {
    instance = new GameStateMap();
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
GameStateMap::Enter()
{
  dialog->Enter();
}

void
GameStateMap::Leave()
{
  dialog->Leave();
}

void
GameStateMap::Execute()
{
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case MAP_MAIN:
      ChangeState(GameStateWorld::GetInstance());
      break;
    case MAP_CAMP:
      ChangeState(GameStateCamp::GetInstance());
      break;
    case MAP_FULLMAP:
      ChangeState(GameStateFullMap::GetInstance());
      break;
    case ACT_UP:
    case MAP_UP:
    case ACT_DOWN:
    case MAP_DOWN:
    case ACT_LEFT:
    case MAP_LEFT:
    case ACT_RIGHT:
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

GameStateOptions::GameStateOptions()
: firstTime(true)
{
  dialog = new OptionsDialog();
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
GameStateOptions::Enter()
{
  if (firstTime) {
    dialog->SetScreen("OPTIONS0.SCX");
    dialog->SetRequest("REQ_OPT0.DAT");
  } else {
    dialog->SetScreen("OPTIONS1.SCX");
    dialog->SetRequest("REQ_OPT1.DAT");
  }
  dialog->Enter();
}

void
GameStateOptions::Leave()
{
  dialog->Leave();
}

void
GameStateOptions::Execute()
{
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case OPT_QUIT:
      GameApplication::GetInstance()->QuitGame();
      break;
    case OPT_NEW_GAME:
      GameApplication::GetInstance()->StartNewGame();
      firstTime = false;
      ChangeState(GameStateChapter::GetInstance());
      break;
    case OPT_CANCEL:
      ChangeState(GameStateWorld::GetInstance());
      break;
    case OPT_CONTENTS:
      ChangeState(GameStateContents::GetInstance());
      break;
    case OPT_PREFERENCES:
      ChangeState(GameStatePreferences::GetInstance());
      break;
    case OPT_RESTORE:
      ChangeState(GameStateLoad::GetInstance());
      break;
    case OPT_SAVE:
      ChangeState(GameStateSave::GetInstance());
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStatePreferences* GameStatePreferences::instance = 0;

GameStatePreferences::GameStatePreferences()
{
  dialog = new OptionsDialog();
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
GameStatePreferences::GetInstance()
{
  if (!instance) {
    instance = new GameStatePreferences();
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
GameStatePreferences::Enter()
{
  dialog->Enter();
}

void
GameStatePreferences::Leave()
{
  dialog->Leave();
}

void
GameStatePreferences::Execute()
{
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case PREF_CANCEL:
      ChangeState(GameApplication::GetInstance()->GetPrevState());
      break;
    case PREF_OK:
      ChangeState(GameApplication::GetInstance()->GetPrevState());
      break;
    case PREF_DEFAULTS:
      break;
    default:
      throw UnexpectedValue(__FILE__, __LINE__, action);
      break;
  }
}

GameStateSave* GameStateSave::instance = 0;

GameStateSave::GameStateSave()
{
  dialog = new OptionsDialog();
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
GameStateSave::GetInstance()
{
  if (!instance) {
    instance = new GameStateSave();
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
GameStateSave::Enter()
{
  dialog->Enter();
}

void
GameStateSave::Leave()
{
  dialog->Leave();
}

void
GameStateSave::Execute()
{
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case SAVE_CANCEL:
      ChangeState(GameApplication::GetInstance()->GetPrevState());
      break;
    case SAVE_SAVE:
      ChangeState(GameApplication::GetInstance()->GetPrevState());
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

GameStateWorld::GameStateWorld()
{
  std::stringstream name;
  name << "Z" << std::setw(2) << std::setfill('0') << GameApplication::GetInstance()->GetGame()->GetChapter()->Get() << ".PAL";
  dialog = new GameDialog();
  dialog->SetPalette(name.str());
  dialog->SetScreen("FRAME.SCX");
  dialog->SetIcons("BICONS1.BMX", "BICONS2.BMX");
  dialog->SetRequest("REQ_MAIN.DAT");
  dialog->SetHeads("HEADS.BMX");
  dialog->SetMembers(GameApplication::GetInstance()->GetGame()->GetParty(), GROUP2);
  dialog->SetCamera(GameApplication::GetInstance()->GetGame()->GetCamera());
  dialog->SetCompass("COMPASS.BMX");
  dialog->SetGameView(GameApplication::GetInstance()->GetGame(), GROUP3, GVT_WORLD);
}

GameStateWorld::~GameStateWorld()
{
  if (dialog) {
    delete dialog;
  }
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
GameStateWorld::Enter()
{
  dialog->Enter();
}

void
GameStateWorld::Leave()
{
  dialog->Leave();
}

void
GameStateWorld::Execute()
{
  unsigned int action = dialog->Execute();
  switch (action) {
    case ACT_ESCAPE:
    case MAIN_OPTIONS:
      ChangeState(GameStateOptions::GetInstance());
      break;
    case MAIN_CAMP:
      ChangeState(GameStateCamp::GetInstance());
      break;
    case MAIN_CAST:
      GameApplication::GetInstance()->GetGame()->GetParty()->SelectMember(0);
      ChangeState(GameStateCast::GetInstance());
      break;
    case MAIN_MAP:
      ChangeState(GameStateMap::GetInstance());
      break;
    case MAIN_MEMBER1:
      GameApplication::GetInstance()->GetGame()->GetParty()->SelectMember(0);
      ChangeState(GameStateInventory::GetInstance());
      break;
    case MAIN_MEMBER2:
      GameApplication::GetInstance()->GetGame()->GetParty()->SelectMember(1);
      ChangeState(GameStateInventory::GetInstance());
      break;
    case MAIN_MEMBER3:
      GameApplication::GetInstance()->GetGame()->GetParty()->SelectMember(2);
      ChangeState(GameStateInventory::GetInstance());
      break;
    case ACT_LEFT:
    case MAIN_LEFT:
      GameApplication::GetInstance()->GetGame()->GetCamera()->Turn(TURN_LEFT);
      break;
    case ACT_RIGHT:
    case MAIN_RIGHT:
      GameApplication::GetInstance()->GetGame()->GetCamera()->Turn(TURN_RIGHT);
      break;
    case ACT_UP:
    case MAIN_UP:
    case ACT_DOWN:
    case MAIN_DOWN:
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
