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

#include "MediaToolkit.h"
#include "Palette.h"
#include "PanelWidget.h"
#include "WidgetFactory.h"

class DialogWindow {
  private:
    PanelWidget *panel;
  public:
    DialogWindow(WidgetResources& widgetRes);
    ~DialogWindow();
    void Draw(Video *video);
    void FadeIn(Palette* pal, MediaToolkit *media);
    void FadeOut(Palette* pal, MediaToolkit *media);
    void LeftClickWidget(const bool toggle);
    void RightClickWidget(const bool toggle);
    void LeftClickWidget(const bool toggle, const int x, const int y);
    void RightClickWidget(const bool toggle, const int x, const int y);
    void SelectNextWidget(Video *video);
    void SelectPreviousWidget(Video *video);
};

#endif

