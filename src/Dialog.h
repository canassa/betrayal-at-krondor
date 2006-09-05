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

#ifndef DIALOG_H
#define DIALOG_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "DialogWindow.h"
#include "EventListener.h"
#include "Party.h"

class Dialog
: public KeyboardEventListener
, public MouseButtonEventListener
, public UpdateEventListener
, public ActionEventListener
{
  protected:
    MediaToolkit *media;
    DialogWindow *window;
    PaletteResource *palette;
    WidgetResources widgetRes;
    unsigned int action;
    bool running;
  public:
    Dialog(MediaToolkit *mtk);
    virtual ~Dialog();
    void SetFont(const std::string &name);
    void SetLabel(const std::string &name);
    void SetPalette(const std::string &name);
    void SetScreen(const std::string &name);
    void SetIcons(const std::string &normalName, const std::string &pressedName);
    void SetCompass(const std::string &name, Orientation *orient);
    void SetHeads(const std::string &name);
    void SetRequest(const std::string &name);
    void SetMembers(Party *party, const int special);
    virtual unsigned int Execute() = 0;
    virtual void KeyPressed(const KeyboardEvent& kbe) = 0;
    virtual void KeyReleased(const KeyboardEvent& kbe) = 0;
    virtual void MouseButtonPressed(const MouseButtonEvent& mbe) = 0;
    virtual void MouseButtonReleased(const MouseButtonEvent& mbe) = 0;
    void Update(const UpdateEvent& ue);
    void ActionPerformed(const ActionEvent& ae);
};

class GameDialog
: public Dialog
{
  public:
    GameDialog(MediaToolkit *mtk);
    ~GameDialog();
    unsigned int Execute();
    void KeyPressed(const KeyboardEvent& kbe);
    void KeyReleased(const KeyboardEvent& kbe);
    void MouseButtonPressed(const MouseButtonEvent& mbe);
    void MouseButtonReleased(const MouseButtonEvent& mbe);
};

class OptionsDialog
: public Dialog
{
  public:
    OptionsDialog(MediaToolkit *mtk);
    ~OptionsDialog();
    unsigned int Execute();
    void KeyPressed(const KeyboardEvent& kbe);
    void KeyReleased(const KeyboardEvent& kbe);
    void MouseButtonPressed(const MouseButtonEvent& mbe);
    void MouseButtonReleased(const MouseButtonEvent& mbe);
};

#endif
