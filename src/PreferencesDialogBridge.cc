/*
 * This program is free software you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY without even the implied warranty of
 * MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, GOOD TITLE or
 * NON INFRINGEMENT.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * Copyright (C) 2005-2007  Guido de Jong <guidoj@users.sf.net>
 */

#include "Preferences.h"
#include "PreferencesDialogBridge.h"
#include "RequestResource.h"

PreferencesDialogBridge* PreferencesDialogBridge::instance = 0;

PreferencesDialogBridge::PreferencesDialogBridge()
{
}

PreferencesDialogBridge::~PreferencesDialogBridge()
{
}

PreferencesDialogBridge*
PreferencesDialogBridge::GetInstance()
{
  if (!instance) {
    instance = new PreferencesDialogBridge();
  }
  return instance;
}


void
PreferencesDialogBridge::CleanUp()
{
  if (instance) {
    delete instance;
    instance = 0;
  }
}

bool
PreferencesDialogBridge::GetSelectState(const unsigned int action)
{
  switch (action) {
    case PREF_STEP_SMALL:
      return Preferences::GetInstance()->GetStepSize() == STS_SMALL;
      break;
    case PREF_STEP_MEDIUM:
      return Preferences::GetInstance()->GetStepSize() == STS_MEDIUM;
      break;
    case PREF_STEP_LARGE:
      return Preferences::GetInstance()->GetStepSize() == STS_LARGE;
      break;
    case PREF_TURN_SMALL:
      return Preferences::GetInstance()->GetTurnSize() == STS_SMALL;
      break;
    case PREF_TURN_MEDIUM:
      return Preferences::GetInstance()->GetTurnSize() == STS_MEDIUM;
      break;
    case PREF_TURN_LARGE:
      return Preferences::GetInstance()->GetTurnSize() == STS_LARGE;
      break;
    case PREF_DETAIL_MIN:
      return Preferences::GetInstance()->GetDetail() == LOD_MIN;
      break;
    case PREF_DETAIL_LOW:
      return Preferences::GetInstance()->GetDetail() == LOD_LOW;
      break;
    case PREF_DETAIL_HIGH:
      return Preferences::GetInstance()->GetDetail() == LOD_HIGH;
      break;
    case PREF_DETAIL_MAX:
      return Preferences::GetInstance()->GetDetail() == LOD_MAX;
      break;
    case PREF_TEXT_WAIT:
      return Preferences::GetInstance()->GetTextSpeed() == TS_WAIT;
      break;
    case PREF_TEXT_MEDIUM:
      return Preferences::GetInstance()->GetTextSpeed() == TS_MEDIUM;
      break;
    case PREF_TEXT_FAST:
      return Preferences::GetInstance()->GetTextSpeed() == TS_FAST;
      break;
    case PREF_SOUND:
      return Preferences::GetInstance()->GetSound();
      break;
    case PREF_MUSIC:
      return Preferences::GetInstance()->GetMusic();
      break;
    case PREF_COMBAT_MUSIC:
      return Preferences::GetInstance()->GetCombatMusic();
      break;
    case PREF_INTRODUCTION:
      return Preferences::GetInstance()->GetIntroduction();
      break;
   default:
     return false;
     break;
  }
}

void
PreferencesDialogBridge::SetSelectState(const unsigned int action)
{
  switch (action) {
    case PREF_STEP_SMALL:
      Preferences::GetInstance()->SetStepSize(STS_SMALL);
      break;
    case PREF_STEP_MEDIUM:
      Preferences::GetInstance()->SetStepSize(STS_MEDIUM);
      break;
    case PREF_STEP_LARGE:
      Preferences::GetInstance()->SetStepSize(STS_LARGE);
      break;
    case PREF_TURN_SMALL:
      Preferences::GetInstance()->SetTurnSize(STS_SMALL);
      break;
    case PREF_TURN_MEDIUM:
      Preferences::GetInstance()->SetTurnSize(STS_MEDIUM);
      break;
    case PREF_TURN_LARGE:
      Preferences::GetInstance()->SetTurnSize(STS_LARGE);
      break;
    case PREF_DETAIL_MIN:
      Preferences::GetInstance()->SetDetail(LOD_MIN);
      break;
    case PREF_DETAIL_LOW:
      Preferences::GetInstance()->SetDetail(LOD_LOW);
      break;
    case PREF_DETAIL_HIGH:
      Preferences::GetInstance()->SetDetail(LOD_HIGH);
      break;
    case PREF_DETAIL_MAX:
      Preferences::GetInstance()->SetDetail(LOD_MAX);
      break;
    case PREF_TEXT_WAIT:
      Preferences::GetInstance()->SetTextSpeed(TS_WAIT);
      break;
    case PREF_TEXT_MEDIUM:
      Preferences::GetInstance()->SetTextSpeed(TS_MEDIUM);
      break;
    case PREF_TEXT_FAST:
      Preferences::GetInstance()->SetTextSpeed(TS_FAST);
      break;
    case PREF_SOUND:
      Preferences::GetInstance()->SetSound(!Preferences::GetInstance()->GetSound());
      break;
    case PREF_MUSIC:
      Preferences::GetInstance()->SetMusic(!Preferences::GetInstance()->GetMusic());
      break;
    case PREF_COMBAT_MUSIC:
      Preferences::GetInstance()->SetCombatMusic(!Preferences::GetInstance()->GetCombatMusic());
      break;
    case PREF_INTRODUCTION:
      Preferences::GetInstance()->SetIntroduction(!Preferences::GetInstance()->GetIntroduction());
      break;
   default:
     break;
  }
}
