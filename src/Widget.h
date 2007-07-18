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

#ifndef WIDGET_H
#define WIDGET_H

#include <list>

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Event.h"
#include "EventListener.h"
#include "Geometry.h"

static const int NO_SHADOW            = -1;
static const int COLOR_BLACK          = 0;
static const int SHADOW_COLOR         = 1;
static const int LIGHT_COLOR          = 4;
static const int TEXT_COLOR_NORMAL    = 10;
static const int TEXT_COLOR_DISABLED  = 11;
static const int TEXT_COLOR_PRESSED   = 6;
static const int BUTTON_COLOR_NORMAL  = 14;
static const int BUTTON_COLOR_PRESSED = 11;
static const int POPUP_COLOR          = 14;
static const int INFO_TEXT_COLOR      = 159;

static const int INVENTORY_OFFSET     = 256;
static const int RIGHT_CLICK_OFFSET   = 512;
static const int RELEASE_OFFSET       = 1024;

class Widget {
  protected:
    Rectangle rect;
    bool visible;
  public:
    Widget(const Rectangle &r);
    virtual ~Widget();
    Rectangle& GetRectangle();
    void SetPosition(const int x, const int y);
    void SetVisible(const bool toggle);
    bool IsVisible() const;
    virtual void Draw() = 0;
};

class ActiveWidget
: public Widget {
  protected:
    int action;
    bool draggable;
    bool focusable;
    std::list<ActionEventListener *> actionListeners;
  public:
    ActiveWidget(const Rectangle &r, const int a);
    virtual ~ActiveWidget();
    int GetAction() const;
    bool IsDraggable() const;
    void SetDraggable(const bool toggle);
    bool IsFocusable() const;
    void SetFocusable(const bool toggle);
    void AddActionListener(ActionEventListener *ael);
    void RemoveActionListener(ActionEventListener *ael);
    void GenerateActionEvent(const int a);
    void GenerateActionEvent(const int a, const int x, const int y);
    void GenerateActionEvent(const ActionEvent& ae);
    void Focus();
    virtual void Reset();
    virtual void LeftClick(const bool toggle, const int x, const int y) = 0;
    virtual void RightClick(const bool toggle, const int x, const int y) = 0;
};

#endif
