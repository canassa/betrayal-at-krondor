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
 * Copyright (C) 2005-2007  Guido de Jong <guidoj@users.sf.net>
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
        , delayed(false)
        , zone()
{
    MediaToolkit::GetInstance()->AddKeyboardListener(this);
    MediaToolkit::GetInstance()->AddPointerButtonListener(this);
    MediaToolkit::GetInstance()->AddTimerListener(this);
    zone.Load(number);
}

Chapter::~Chapter()
{
    MediaToolkit::GetInstance()->RemoveTimerListener(this);
    MediaToolkit::GetInstance()->RemovePointerButtonListener(this);
    MediaToolkit::GetInstance()->RemoveKeyboardListener(this);
}

void
Chapter::PlayIntro()
{
    try
    {
        AnimationResource anim;
        std::stringstream filenameStream;
        filenameStream << "CHAPTER" << number << ".ADS";
        FileManager::GetInstance()->Load(&anim, filenameStream.str());
        MovieResource ttm;
        FileManager::GetInstance()->Load(&ttm, anim.GetAnimationData(1).resource);
        MoviePlayer moviePlayer;
        moviePlayer.Play(&ttm.GetMovieChunks(), false);
    }
    catch (Exception &e)
    {
        e.Print("Chapter::PlayIntro");
    }
}

void
Chapter::PlayScene(const int scene)
{
    try
    {
        ScreenResource scr;
        FileManager::GetInstance()->Load(&scr, "CFRAME.SCX");
        scr.GetImage()->Draw(0, 0);
        AnimationResource anim;
        std::stringstream filenameStream;
        filenameStream << "C" << number << scene << ".ADS";
        FileManager::GetInstance()->Load(&anim, filenameStream.str());
        MovieResource ttm;
        FileManager::GetInstance()->Load(&ttm, anim.GetAnimationData(1).resource);
        MoviePlayer moviePlayer;
        moviePlayer.Play(&ttm.GetMovieChunks(), false);
    }
    catch (Exception &e)
    {
        e.Print("Chapter::PlayIntro");
    }
}

void
Chapter::ReadBook(const int scene)
{
    try
    {
        BookResource bok;
        std::stringstream filenameStream;
        filenameStream << "C" << number << scene << ".BOK";
        FileManager::GetInstance()->Load(&bok, filenameStream.str());
    }
    catch (Exception &e)
    {
        e.Print("Chapter::ReadBook");
    }
}

void
Chapter::ShowMap()
{
    try
    {
        PaletteResource *pal = new PaletteResource;
        FileManager::GetInstance()->Load(pal, "FULLMAP.PAL");
        ScreenResource *scr = new ScreenResource;
        FileManager::GetInstance()->Load(scr, "FULLMAP.SCX");
        scr->GetImage()->Draw(0, 0);
        Video *video = MediaToolkit::GetInstance()->GetVideo();
        video->FillRect(14, 161, 157, 27, BUTTON_COLOR_NORMAL);
        video->DrawVLine(13, 161, 29, SHADOW_COLOR);
        video->DrawHLine(13, 160, 160, LIGHT_COLOR);
        video->DrawVLine(171, 161, 28, LIGHT_COLOR);
        video->DrawHLine(14, 188, 157, SHADOW_COLOR);
        video->DrawVLine(12, 162, 26, COLOR_BLACK);
        video->DrawHLine(12, 189, 157, COLOR_BLACK);
        pal->GetPalette()->FadeIn(0, VIDEO_COLORS, 64, 5);
        MediaToolkit::GetInstance()->GetClock()->StartTimer(TMR_CHAPTER, 4000);
        delayed = true;
        while (delayed)
        {
            MediaToolkit::GetInstance()->WaitEvents();
        }
        pal->GetPalette()->FadeOut(0, VIDEO_COLORS, 64, 5);
        delete pal;
        delete scr;
    }
    catch (Exception &e)
    {
        e.Print("Chapter::ShowMap");
    }
}

int
Chapter::Get() const
{
    return number;
}

Zone&
Chapter::GetZone()
{
    return zone;
}

void
Chapter::Next()
{
    number++;
    zone.Load(number);
}

void
Chapter::Start(const bool maponly)
{
    try
    {
        if (!maponly)
        {
            PlayIntro();
            ReadBook(1);
            PlayScene(1);
        }
        ShowMap();
    }
    catch (Exception &e)
    {
        e.Print("Chapter::Start");
    }
}

void
Chapter::KeyPressed(const KeyboardEvent &kbe)
{
    switch (kbe.GetKey())
    {
        case KEY_ESCAPE:
        case KEY_RETURN:
        case KEY_SPACE:
            delayed = false;
            break;
        default:
            break;
    }
}

void
Chapter::KeyReleased(const KeyboardEvent &kbe)
{
    switch (kbe.GetKey())
    {
        default:
            break;
    }
}

void
Chapter::PointerButtonPressed(const PointerButtonEvent &pbe)
{
    switch (pbe.GetButton())
    {
        case PB_PRIMARY:
            delayed = false;
            break;
        default:
            break;
    }
}

void
Chapter::PointerButtonReleased(const PointerButtonEvent &pbe)
{
    switch (pbe.GetButton())
    {
        default:
            break;
    }
}

void
Chapter::TimerExpired(const TimerEvent &te)
{
    if (te.GetID() == TMR_CHAPTER)
    {
        delayed = false;
    }
}
