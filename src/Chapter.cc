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

#include <sstream>

#include "AnimationResource.h"
#include "BookResource.h"
#include "Chapter.h"
#include "Exception.h"
#include "FileManager.h"
#include "GameApplication.h"
#include "MoviePlayer.h"

Chapter::Chapter(const int n)
: number(n)
{
}

Chapter::~Chapter()
{
}

void
Chapter::PlayIntro()
{
  try {
    AnimationResource anim;
    std::stringstream filenameStream;
    filenameStream << "CHAPTER" << number << ".ADS";
    FileManager::GetInstance()->Load(&anim, filenameStream.str());
    MovieResource ttm;
    FileManager::GetInstance()->Load(&ttm, anim.GetAnimationData(1).resource);
    MoviePlayer moviePlayer;
    moviePlayer.Play(&ttm.GetMovieTags(), false);
  } catch (Exception &e) {
    e.Print("Chapter::PlayIntro");
  }
}

void
Chapter::PlayScene(const int scene)
{
  try {
    ScreenResource scr;
    FileManager::GetInstance()->Load(&scr, "CFRAME.SCX");
    scr.GetImage()->Draw(MediaToolkit::GetInstance()->GetVideo(), 0, 0);
    AnimationResource anim;
    std::stringstream filenameStream;
    filenameStream << "C" << number << scene << ".ADS";
    FileManager::GetInstance()->Load(&anim, filenameStream.str());
    MovieResource ttm;
    FileManager::GetInstance()->Load(&ttm, anim.GetAnimationData(1).resource);
    MoviePlayer moviePlayer;
    moviePlayer.Play(&ttm.GetMovieTags(), false);
  } catch (Exception &e) {
    e.Print("Chapter::PlayIntro");
  }
}

void
Chapter::ReadBook(const int scene)
{
  try {
    BookResource bok;
    std::stringstream filenameStream;
    filenameStream << "C" << number << scene << ".BOK";
    FileManager::GetInstance()->Load(&bok, filenameStream.str());
    MediaToolkit::GetInstance()->AddKeyboardListener(this);
    MediaToolkit::GetInstance()->AddTimerListener(this);
    MediaToolkit::GetInstance()->RemoveTimerListener(this);
    MediaToolkit::GetInstance()->RemoveKeyboardListener(this);
  } catch (Exception &e) {
    e.Print("Chapter::ReadBook");
  }
}

void
Chapter::ShowMap()
{
  try {
    ScreenResource scr;
    FileManager::GetInstance()->Load(&scr, "FULLMAP.SCX");
    scr.GetImage()->Draw(MediaToolkit::GetInstance()->GetVideo(), 0, 0);
    PaletteResource pal;
    FileManager::GetInstance()->Load(&pal, "FULLMAP.PAL");
    MediaToolkit::GetInstance()->AddKeyboardListener(this);
    MediaToolkit::GetInstance()->AddMouseButtonListener(this);
    MediaToolkit::GetInstance()->AddTimerListener(this);
    pal.FadeIn(MediaToolkit::GetInstance(), 0, VIDEO_COLORS, 64, 5);
    MediaToolkit::GetInstance()->GetClock()->StartTimer(TMR_CHAPTER, 4000);
    MediaToolkit::GetInstance()->WaitEventLoop();
    pal.FadeOut(MediaToolkit::GetInstance(), 0, VIDEO_COLORS, 64, 5);
    MediaToolkit::GetInstance()->RemoveTimerListener(this);
    MediaToolkit::GetInstance()->RemoveMouseButtonListener(this);
    MediaToolkit::GetInstance()->RemoveKeyboardListener(this);
  } catch (Exception &e) {
    e.Print("Chapter::ShowMap");
  }
}

void
Chapter::KeyPressed(const KeyboardEvent &kbe)
{
  switch (kbe.GetKey()) {
    case KEY_ESCAPE:
    case KEY_RETURN:
    case KEY_SPACE:
      MediaToolkit::GetInstance()->TerminateEventLoop();
      break;
    default:
      break;
  }
}

void
Chapter::KeyReleased(const KeyboardEvent &kbe)
{
  switch (kbe.GetKey()) {
    default:
      break;
  }
}

void
Chapter::MouseButtonPressed(const MouseButtonEvent &mbe)
{
  switch (mbe.GetButton()) {
    case MB_LEFT:
      MediaToolkit::GetInstance()->TerminateEventLoop();
      break;
    default:
      break;
  }
}

void
Chapter::MouseButtonReleased(const MouseButtonEvent &mbe)
{
  switch (mbe.GetButton()) {
    default:
      break;
  }
}

void
Chapter::TimerExpired(const TimerEvent &te)
{
  if (te.GetID() == TMR_CHAPTER) {
    MediaToolkit::GetInstance()->TerminateEventLoop();
  }
}
