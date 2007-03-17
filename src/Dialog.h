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

#ifndef DIALOG_H
#define DIALOG_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "DialogWindow.h"
#include "EventListener.h"
#include "Observer.h"
#include "Palette.h"

class Dialog
: public ActionEventListener
, public MouseButtonEventListener
, public KeyboardEventListener
, public Observer
{
  protected:
    DialogWindow *window;
    Palette *palette;
    unsigned int action;
    bool running;
  public:
    Dialog(Palette *pal, DialogWindow *dialogwin);
    virtual ~Dialog();
    void Enter();
    void Leave();
    unsigned int Execute();
    void Update();
    void ActionPerformed(const ActionEvent& ae);
    void MouseButtonPressed(const MouseButtonEvent& mbe);
    void MouseButtonReleased(const MouseButtonEvent& mbe);
    virtual void KeyPressed(const KeyboardEvent& kbe) = 0;
    virtual void KeyReleased(const KeyboardEvent& kbe) = 0;
};

class GameDialog
: public Dialog
{
  public:
    GameDialog(Palette *pal, DialogWindow *dialogwin);
    ~GameDialog();
    void KeyPressed(const KeyboardEvent& kbe);
    void KeyReleased(const KeyboardEvent& kbe);
};

class OptionsDialog
: public Dialog
{
  public:
    OptionsDialog(Palette *pal, DialogWindow *dialogwin);
    ~OptionsDialog();
    void KeyPressed(const KeyboardEvent& kbe);
    void KeyReleased(const KeyboardEvent& kbe);
};

#endif
