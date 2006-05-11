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

class GameStateChapter: public GameState
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

class GameStateCombat: public GameState
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

class GameStateContents: public GameState
{
  private:
    Dialog *dialog;
    static GameStateContents *instance;
  protected:
    GameStateContents(MediaToolkit *mtk);
  public:
    ~GameStateContents();
    static GameStateContents* GetInstance(MediaToolkit *mtk);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStateIntro: public GameState
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

class GameStateLoad: public GameState
{
  private:
    Dialog *dialog;
    static GameStateLoad *instance;
  protected:
    GameStateLoad(MediaToolkit *mtk);
  public:
    ~GameStateLoad();
    static GameStateLoad* GetInstance(MediaToolkit *mtk);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStateOptions: public GameState
{
  private:
    bool firstTime;
    Dialog *dialog;
    static GameStateOptions *instance;
  protected:
    GameStateOptions(MediaToolkit *mtk);
  public:
    ~GameStateOptions();
    static GameStateOptions* GetInstance(MediaToolkit *mtk);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStatePreferences: public GameState
{
  private:
    Dialog *dialog;
    static GameStatePreferences *instance;
  protected:
    GameStatePreferences(MediaToolkit *mtk);
  public:
    ~GameStatePreferences();
    static GameStatePreferences* GetInstance(MediaToolkit *mtk);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStateSave: public GameState
{
  private:
    Dialog *dialog;
    static GameStateSave *instance;
  protected:
    GameStateSave(MediaToolkit *mtk);
  public:
    ~GameStateSave();
    static GameStateSave* GetInstance(MediaToolkit *mtk);
    static void CleanUp();
    void Execute(GameApplication *app);
};

class GameStateWorld: public GameState
{
  private:
    Dialog *dialog;
    static GameStateWorld *instance;
  protected:
    GameStateWorld(MediaToolkit *mtk);
  public:
    ~GameStateWorld();
    static GameStateWorld* GetInstance(MediaToolkit *mtk);
    static void CleanUp();
    void Execute(GameApplication *app);
};

#endif
