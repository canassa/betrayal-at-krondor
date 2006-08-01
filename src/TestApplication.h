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

#ifndef TEST_APPLICATION_H
#define TEST_APPLICATION_H

#include <string>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "ImageResource.h"
#include "FontResource.h"
#include "MediaToolkit.h"
#include "MovieResource.h"
#include "PaletteResource.h"
#include "ScreenResource.h"
#include "SoundResource.h"
#include "TileWorldResource.h"

class TestApplication
: public KeyboardEventListener
, public TimerEventListener
{
  private:
    MediaToolkit *mediaToolkit;
    PaletteResource pal;
    FontResource fnt;
    ImageResource img;
    ScreenResource scr;
    SoundResource snd;
    MovieResource ttm;
    TileWorldResource wld;
    static TestApplication *instance;
  protected:
    TestApplication();
  public:
    ~TestApplication();
    static TestApplication* GetInstance();
    static void CleanUp();
    void ActivatePalette();
    void ActivatePalette(const std::string& name);
    void ShowImage(const std::string& name);
    void ShowScreen(const std::string& name);
    void DrawFont(const std::string& name);
    void PlayMovie(const std::string& name);
    void PlaySound(const unsigned int index);
    void WalkWorld(const std::string& zone, const std::string& tile);
    void KeyPressed(const KeyboardEvent &kbe);
    void KeyReleased(const KeyboardEvent &kbe);
    void TimerExpired(const TimerEvent &te);
};

#endif
