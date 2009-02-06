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

#ifndef GAME_STATE_H
#define GAME_STATE_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Dialog.h"
#include "DialogFactory.h"

class GameState
{
protected:
    DialogFactory dialogFactory;
    GameState *prevState;
    void ChangeState ( GameState *state, const bool savePreviousState = false );
public:
    GameState();
    virtual ~GameState();
    virtual void Enter();
    virtual void Leave();
    virtual void Execute();
};

class GameStateCamp
            : public GameState
{
private:
    Dialog *dialog;
    static GameStateCamp *instance;
protected:
    GameStateCamp();
public:
    ~GameStateCamp();
    static GameStateCamp* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

class GameStateCast
            : public GameState
{
private:
    Dialog *dialog;
    static GameStateCast *instance;
protected:
    GameStateCast();
public:
    ~GameStateCast();
    static GameStateCast* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

class GameStateChapter
            : public GameState
{
private:
    static GameStateChapter *instance;
protected:
    GameStateChapter();
public:
    ~GameStateChapter();
    static GameStateChapter* GetInstance();
    static void CleanUp();
    void Execute();
};

class GameStateCombat
            : public GameState
{
private:
    static GameStateCombat *instance;
protected:
    GameStateCombat();
public:
    ~GameStateCombat();
    static GameStateCombat* GetInstance();
    static void CleanUp();
    void Execute();
};

class GameStateContents
            : public GameState
{
private:
    Dialog *dialog;
    static GameStateContents *instance;
protected:
    GameStateContents();
public:
    ~GameStateContents();
    static GameStateContents* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

class GameStateFullMap
            : public GameState
{
private:
    Dialog *dialog;
    static GameStateFullMap *instance;
protected:
    GameStateFullMap();
public:
    ~GameStateFullMap();
    static GameStateFullMap* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

class GameStateInitialOptions
            : public GameState
{
private:
    Dialog *dialog;
    static GameStateInitialOptions *instance;
protected:
    GameStateInitialOptions();
public:
    ~GameStateInitialOptions();
    static GameStateInitialOptions* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

class GameStateIntro
            : public GameState
{
private:
    static GameStateIntro *instance;
protected:
    GameStateIntro();
public:
    ~GameStateIntro();
    static GameStateIntro* GetInstance();
    static void CleanUp();
    void Execute();
};

class GameStateInventory
            : public GameState
{
private:
    Dialog *dialog;
    static GameStateInventory *instance;
protected:
    GameStateInventory();
public:
    ~GameStateInventory();
    static GameStateInventory* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

class GameStateLoad
            : public GameState
{
private:
    Dialog *dialog;
    static GameStateLoad *instance;
protected:
    GameStateLoad();
public:
    ~GameStateLoad();
    static GameStateLoad* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

class GameStateMap
            : public GameState
{
private:
    Dialog *dialog;
    static GameStateMap *instance;
protected:
    GameStateMap();
public:
    ~GameStateMap();
    static GameStateMap* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

class GameStateOptions
            : public GameState
{
private:
    Dialog *dialog;
    static GameStateOptions *instance;
protected:
    GameStateOptions();
public:
    ~GameStateOptions();
    static GameStateOptions* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

class GameStatePreferences
            : public GameState
{
private:
    Dialog *dialog;
    static GameStatePreferences *instance;
protected:
    GameStatePreferences();
public:
    ~GameStatePreferences();
    static GameStatePreferences* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

class GameStateInfo
            : public GameState
{
private:
    Dialog *dialog;
    static GameStateInfo *instance;
protected:
    GameStateInfo();
public:
    ~GameStateInfo();
    static GameStateInfo* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

class GameStateSave
            : public GameState
{
private:
    Dialog *dialog;
    static GameStateSave *instance;
protected:
    GameStateSave();
public:
    ~GameStateSave();
    static GameStateSave* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

class GameStateWorld
            : public GameState
{
private:
    Dialog *dialog;
    static GameStateWorld *instance;
protected:
    GameStateWorld();
public:
    ~GameStateWorld();
    static GameStateWorld* GetInstance();
    static void CleanUp();
    void Enter();
    void Leave();
    void Execute();
};

#endif
