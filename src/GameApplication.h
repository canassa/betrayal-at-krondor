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

#ifndef GAME_APPLICATION_H
#define GAME_APPLICATION_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Chapter.h"
#include "EventListener.h"
#include "GameState.h"
#include "MediaToolkit.h"

class GameApplication
: public KeyboardEventListener
, public MouseButtonEventListener
{
  private:
    friend class GameState;
    MediaToolkit *mediaToolkit;
    bool done;
    bool inputGrabbed;
    GameState *state;
    GameState *prevState;
    Chapter chapter;
    int screenSaveCount;
    static GameApplication *instance;
    void SetState(GameState *st);
  protected:
    GameApplication();
  public:
    ~GameApplication();
    static GameApplication* GetInstance();
    static void CleanUp();
    MediaToolkit* GetMediaToolkit();
    GameState* GetPrevState();
    void PlayIntro();
    void StartChapter();
    void StartNewGame();
    void QuitGame();
    void Run();
    void KeyPressed(const KeyboardEvent& kbe);
    void KeyReleased(const KeyboardEvent& kbe);
    void MouseButtonPressed(const MouseButtonEvent& mbe);
    void MouseButtonReleased(const MouseButtonEvent& mbe);
};

#endif

