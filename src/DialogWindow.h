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

#ifndef DIALOG_WINDOW_H
#define DIALOG_WINDOW_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "EventHandler.h"
#include "FontResource.h"
#include "MediaToolkit.h"
#include "PaletteResource.h"
#include "PanelWidget.h"
#include "RequestResource.h"
#include "ScreenResource.h"

class DialogWindow: public EventHandler {
  private:
    MediaToolkit *media;
    PanelWidget *panel;
  public:
    DialogWindow(MediaToolkit *mtk);
    ~DialogWindow();
    void Create(RequestResource& req, ScreenResource& scr, FontResource& fnt, WidgetCallBack *wcb);
    void Run(PaletteResource& pal);
    void HandleKeyboardEvent(int key, bool down);
    void HandleMouseButtonEvent(int button, int x, int y, bool down);
    void HandleUpdateEvent();
};

#endif

