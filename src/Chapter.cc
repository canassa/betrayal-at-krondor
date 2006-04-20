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
#include "MoviePlayer.h"
#include "ResourceManager.h"

Chapter::Chapter(MediaToolkit *mtk)
: media(mtk)
, number(0)
{
}

Chapter::~Chapter()
{
}

void
Chapter::SetCurrent(const int n)
{
  number = n;
}

void
Chapter::PlayIntro()
{
  try {
    AnimationResource anim;
    std::stringstream filenameStream;
    filenameStream << "CHAPTER" << number << ".ADS";
    ResourceManager::GetInstance()->Load(&anim, filenameStream.str());
    MovieResource ttm;
    ResourceManager::GetInstance()->Load(&ttm, anim.GetAnimationData(1).resource);
    MoviePlayer moviePlayer(media);
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
    ResourceManager::GetInstance()->Load(&scr, "CFRAME.SCX");
    scr.GetImage()->Draw(media->GetVideo(), 0, 0);
    AnimationResource anim;
    std::stringstream filenameStream;
    filenameStream << "C" << number << scene << ".ADS";
    ResourceManager::GetInstance()->Load(&anim, filenameStream.str());
    MovieResource ttm;
    ResourceManager::GetInstance()->Load(&ttm, anim.GetAnimationData(1).resource);
    MoviePlayer moviePlayer(media);
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
    ResourceManager::GetInstance()->Load(&bok, filenameStream.str());
  } catch (Exception &e) {
    e.Print("Chapter::ReadBook");
  }
}

void
Chapter::ShowMap()
{
  try {
    ScreenResource scr;
    ResourceManager::GetInstance()->Load(&scr, "FULLMAP.SCX");
    scr.GetImage()->Draw(media->GetVideo(), 0, 0);
    PaletteResource pal;
    ResourceManager::GetInstance()->Load(&pal, "FULLMAP.PAL");
    pal.FadeIn(media->GetVideo(), 0, VIDEO_COLORS, 64, 10, media->GetClock());
    media->GetClock()->Delay(2000);
    pal.FadeOut(media->GetVideo(), 0, VIDEO_COLORS, 64, 10, media->GetClock());
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
