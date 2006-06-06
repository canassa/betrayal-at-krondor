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

#ifndef GAME_STATE_H
#define GAME_STATE_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Dialog.h"

class GameApplication;

class GameState
{
  protected:
    void ChangeState(GameApplication *app, GameState *state);
  public:
    GameState();
    virtual ~GameState();
    virtual void Execute(GameApplication *app);
};

class GameStateCamp
: public GameState
{
  private:
    Dialog *dialog;
    static GameStateCamp *instance;
  protected:
    GameStateCamp(GameApplication *app);
  public:
    ~GameStateCamp();
    static GameStateCamp* GetInstance(GameApplication *app);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStateCast
: public GameState
{
  private:
    Dialog *dialog;
    static GameStateCast *instance;
  protected:
    GameStateCast(GameApplication *app);
  public:
    ~GameStateCast();
    static GameStateCast* GetInstance(GameApplication *app);
    static void CleanUp();
    void Execute(GameApplication *app);
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
    void Execute(GameApplication *app);
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
    void Execute(GameApplication *app);
};

class GameStateContents
: public GameState
{
  private:
    Dialog *dialog;
    static GameStateContents *instance;
  protected:
    GameStateContents(GameApplication *app);
  public:
    ~GameStateContents();
    static GameStateContents* GetInstance(GameApplication *app);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStateFullMap
: public GameState
{
  private:
    Dialog *dialog;
    static GameStateFullMap *instance;
  protected:
    GameStateFullMap(GameApplication *app);
  public:
    ~GameStateFullMap();
    static GameStateFullMap* GetInstance(GameApplication *app);
    static void CleanUp();
    void Execute(GameApplication *app);
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
    void Execute(GameApplication *app);
};

class GameStateInventory
: public GameState
{
  private:
    Dialog *dialog;
    static GameStateInventory *instance;
  protected:
    GameStateInventory(GameApplication *app);
  public:
    ~GameStateInventory();
    static GameStateInventory* GetInstance(GameApplication *app);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStateLoad
: public GameState
{
  private:
    Dialog *dialog;
    static GameStateLoad *instance;
  protected:
    GameStateLoad(GameApplication *app);
  public:
    ~GameStateLoad();
    static GameStateLoad* GetInstance(GameApplication *app);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStateMap
: public GameState
{
  private:
    Dialog *dialog;
    static GameStateMap *instance;
  protected:
    GameStateMap(GameApplication *app);
  public:
    ~GameStateMap();
    static GameStateMap* GetInstance(GameApplication *app);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStateOptions
: public GameState
{
  private:
    bool firstTime;
    Dialog *dialog;
    static GameStateOptions *instance;
  protected:
    GameStateOptions(GameApplication *app);
  public:
    ~GameStateOptions();
    static GameStateOptions* GetInstance(GameApplication *app);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStatePreferences
: public GameState
{
  private:
    Dialog *dialog;
    static GameStatePreferences *instance;
  protected:
    GameStatePreferences(GameApplication *app);
  public:
    ~GameStatePreferences();
    static GameStatePreferences* GetInstance(GameApplication *app);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStateSave
: public GameState
{
  private:
    Dialog *dialog;
    static GameStateSave *instance;
  protected:
    GameStateSave(GameApplication *app);
  public:
    ~GameStateSave();
    static GameStateSave* GetInstance(GameApplication *app);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStateWorld
: public GameState
{
  private:
    Dialog *dialog;
    static GameStateWorld *instance;
  protected:
    GameStateWorld(GameApplication *app);
  public:
    ~GameStateWorld();
    static GameStateWorld* GetInstance(GameApplication *app);
    static void CleanUp();
    void Execute(GameApplication *app);
};

#endif
