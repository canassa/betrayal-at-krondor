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

Preferences globalPrefs;

Preferences::Preferences()
{
  SetDefaults();
}

Preferences::~Preferences()
{
}

void
Preferences::SetDefaults()
{
  stepSize = STS_SMALL;
  turnSize = STS_SMALL;
  textSpeed = TS_WAIT;
  detail = LOD_MAX;
  sound = true;
  music = true;
  combatMusic = true;
  introduction = true;
}

void
Preferences::Copy(const Preferences &prefs)
{
  stepSize = prefs.stepSize;
  turnSize = prefs.turnSize;
  textSpeed = prefs.textSpeed;
  detail = prefs.detail;
  sound = prefs.sound;
  music = prefs.music;
  combatMusic = prefs.combatMusic;
  introduction = prefs.introduction;
}

StepTurnSize
Preferences::GetStepSize() const
{
  return stepSize;
}

void
Preferences::SetStepSize(const StepTurnSize sz)
{
  stepSize = sz;
}

StepTurnSize
Preferences::GetTurnSize() const
{
  return turnSize;
}

void
Preferences::SetTurnSize(const StepTurnSize sz)
{
  turnSize = sz;
}

TextSpeed
Preferences::GetTextSpeed() const
{
  return textSpeed;
}

void
Preferences::SetTextSpeed(const TextSpeed ts)
{
  textSpeed = ts;
}

LevelOfDetail
Preferences::GetDetail() const
{
  return detail;
}

void
Preferences::SetDetail(const LevelOfDetail lod)
{
  detail = lod;
}

bool
Preferences::GetSound() const
{
  return sound;
}

void
Preferences::SetSound(const bool toggle)
{
  sound = toggle;
}

bool
Preferences::GetMusic() const
{
  return music;
}

void
Preferences::SetMusic(const bool toggle)
{
  music = toggle;
}

bool
Preferences::GetCombatMusic() const
{
  return combatMusic;
}

void
Preferences::SetCombatMusic(const bool toggle)
{
  combatMusic = toggle;
}

bool
Preferences::GetIntroduction() const
{
  return introduction;
}

void
Preferences::SetIntroduction(const bool toggle)
{
  introduction = toggle;
}
