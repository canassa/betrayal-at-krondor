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

#ifndef GAME_DIALOG_H
#define GAME_DIALOG_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "DialogWindow.h"
#include "EventListener.h"
#include "MediaToolkit.h"

class GameDialog
: public KeyboardEventListener
, public MouseButtonEventListener
, public UpdateEventListener
, public ActionEventListener
{
  private:
    MediaToolkit *media;
    DialogWindow *window;
    bool running;
    FontResource gameFont;
    LabelResource lblNull;
    PaletteResource optionsPalette;
    ScreenResource frameScreen;
    RequestResource reqMain;
  public:
    GameDialog(MediaToolkit *mtk);
    ~GameDialog();
    void Play();
    void KeyPressed(const KeyboardEvent& kbe);
    void KeyReleased(const KeyboardEvent& kbe);
    void MouseButtonPressed(const MouseButtonEvent& mbe);
    void MouseButtonReleased(const MouseButtonEvent& mbe);
    void Update(const UpdateEvent& ue);
    void ActionPerformed(const ActionEvent& ae);
};

#endif

