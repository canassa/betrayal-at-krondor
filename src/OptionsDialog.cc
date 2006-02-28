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

#include "Exception.h"
#include "OptionsDialog.h"
#include "MousePointerManager.h"
#include "ResourceManager.h"
#include "WidgetFactory.h"

OptionsDialog::OptionsDialog(MediaToolkit *mtk)
: media(mtk)
, window(0)
{
  try {
    ResourceManager::GetInstance()->Load(&gameFont, "GAME.FNT");
    ResourceManager::GetInstance()->Load(&optionsPalette, "OPTIONS.PAL");
    ResourceManager::GetInstance()->Load(&optionsScreen, "OPTIONS0.SCX");
    ResourceManager::GetInstance()->Load(&reqOpt0, "REQ_OPT0.DAT");
    window = new DialogWindow(media);
    int x = 0;
    int y = 0;
    media->GetMousePosition(&x, &y);
    MousePointerManager::GetInstance()->SetCurrentPointer(NORMAL_POINTER);
    MousePointerManager::GetInstance()->GetCurrentPointer()->SetPosition(x, y);
    MousePointerManager::GetInstance()->GetCurrentPointer()->SetVisible(true);
  } catch (Exception &e) {
    e.Print("OptionsDialog::OptionsDialog");
    throw;
  }
}

OptionsDialog::~OptionsDialog()
{
  delete window;
}

void
OptionsDialog::Run()
{
  try {
    media->GetVideo()->Clear();
    window->Create(reqOpt0, optionsScreen, gameFont, this);
    window->Run(optionsPalette);
  } catch (Exception &e) {
    e.Print("OptionsDialog::Run");
    throw;
  }
}

void
OptionsDialog::ActionPerformed(const int action)
{
  switch (action) {
    default:
      printf("Action: %d\n", action);
      break;
  }
}
