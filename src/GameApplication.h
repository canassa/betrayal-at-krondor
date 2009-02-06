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
 * Copyright (C) 2005-2009 Guido de Jong <guidoj@users.sf.net>
 */

#ifndef GAME_APPLICATION_H
#define GAME_APPLICATION_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "ConfigResource.h"
#include "EventListener.h"
#include "GameResource.h"
#include "GameState.h"

class GameApplication
            : public KeyboardEventListener
            , public PointerButtonEventListener
{
private:
    friend class GameState;
    bool done;
    bool inputGrabbed;
    ConfigResource *config;
    GameResource *game;
    GameState *state;
    int screenSaveCount;
    static GameApplication *instance;
    void SetState ( GameState *st );
protected:
    GameApplication();
public:
    ~GameApplication();
    static GameApplication* GetInstance();
    static void CleanUp();
    Preferences* GetPreferences();
    Game* GetGame();
    void PlayIntro();
    void StartNewGame();
    void QuitGame();
    void SaveConfig();
    void Run();
    void KeyPressed ( const KeyboardEvent& kbe );
    void KeyReleased ( const KeyboardEvent& kbe );
    void PointerButtonPressed ( const PointerButtonEvent& pbe );
    void PointerButtonReleased ( const PointerButtonEvent& pbe );
};

#endif
