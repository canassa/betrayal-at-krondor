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

#ifndef OPTIONS_DIALOG_H
#define OPTIONS_DIALOG_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "DialogWindow.h"
#include "EventListener.h"

typedef enum _DialogType {
  DT_CONTENTS,
  DT_OPT0,
  DT_OPT1,
  DT_PREFERENCES,
  DT_RESTORE,
  DT_SAVE
} DialogType;

typedef enum _UserActionType {
  UA_CANCEL,
  UA_NEW_GAME,
  UA_QUIT,
  UA_RESTORE,
  UA_SAVE,
  UA_UNKNOWN
} UserActionType;

class OptionsDialog
: public KeyboardEventListener
, public MouseButtonEventListener
, public UpdateEventListener
, public ActionEventListener
{
  private:
    MediaToolkit *media;
    UserActionType userAction;
    DialogType dialogType;
    DialogWindow *window;
    bool firstTime;
    bool running;
    FontResource bookFont;
    FontResource gameFont;
    LabelResource lblLoad;
    LabelResource lblNull;
    LabelResource lblPref;
    LabelResource lblSave;
    PaletteResource contentsPalette;
    PaletteResource optionsPalette;
    ScreenResource contentsScreen;
    ScreenResource options0Screen;
    ScreenResource options1Screen;
    ScreenResource options2Screen;
    RequestResource reqCont;
    RequestResource reqLoad;
    RequestResource reqOpt0;
    RequestResource reqOpt1;
    RequestResource reqPref;
    RequestResource reqSave;
  public:
    OptionsDialog(MediaToolkit *mtk, const bool first);
    ~OptionsDialog();
    UserActionType GetUserAction();
    void KeyPressed(const KeyboardEvent& kbe);
    void KeyReleased(const KeyboardEvent& kbe);
    void MouseButtonPressed(const MouseButtonEvent& mbe);
    void MouseButtonReleased(const MouseButtonEvent& mbe);
    void Update(const UpdateEvent& ue);
    void ActionPerformed(const ActionEvent& ae);
};

#endif
