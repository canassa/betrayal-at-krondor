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

#ifndef WIDGET_H
#define WIDGET_H

#include <list>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "EventListener.h"

static const int NO_SHADOW            = -1;
static const int SHADOW_COLOR         = 1;
static const int LIGHT_COLOR          = 4;
static const int TEXT_COLOR_NORMAL    = 10;
static const int TEXT_COLOR_DISABLED  = 11;
static const int TEXT_COLOR_PRESSED   = 6;
static const int BUTTON_COLOR_NORMAL  = 14;
static const int BUTTON_COLOR_PRESSED = 11;
static const int POPUP_COLOR          = 14;

static const int RIGHT_CLICK_OFFSET   = 256;

class Widget {
  protected:
    int xpos;
    int ypos;
    int width;
    int height;
  public:
    Widget(const int x, const int y, const int w, const int h);
    virtual ~Widget();
    bool Covers(const int x, const int y) const;
    int GetXPos() const;
    int GetYPos() const;
    int GetXCenter() const;
    int GetYCenter() const;
    int GetWidth() const;
    int GetHeight() const;
    virtual void Draw() = 0;
};

class ActiveWidget: public Widget {
  protected:
    int action;
    std::list<ActionEventListener *> actionListeners;
  public:
    ActiveWidget(const int x, const int y, const int w, const int h, const int a);
    ~ActiveWidget();
    void AddActionListener(ActionEventListener *ael);
    void RemoveActionListener(ActionEventListener *ael);
    virtual void Focus() = 0;
    virtual void LeftClick(const bool toggle) = 0;
    virtual void RightClick(const bool toggle) = 0;
};

#endif

