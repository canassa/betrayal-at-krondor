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

#include "ContainerWidget.h"

ContainerWidget::ContainerWidget(const Rectangle &r)
: Widget(r)
, widgets()
, activeWidgets()
, currentActiveWidget()
{
}

ContainerWidget::~ContainerWidget()
{
  for (std::list<Widget *>::iterator it = widgets.begin(); it != widgets.end(); ++it) {
    delete (*it);
  }
  widgets.clear();
  for (std::list<ActiveWidget *>::iterator it = activeWidgets.begin(); it != activeWidgets.end(); ++it) {
    delete (*it);
  }
  activeWidgets.clear();
}

void
ContainerWidget::AddWidget(Widget *w)
{
  widgets.push_back(w);
}

void
ContainerWidget::AddActiveWidget(ActiveWidget *aw)
{
  activeWidgets.push_back(aw);
  currentActiveWidget = activeWidgets.end();
}

void
ContainerWidget::RemoveWidget(Widget *w)
{
  widgets.remove(w);
}

void
ContainerWidget::RemoveActiveWidget(ActiveWidget *aw)
{
  activeWidgets.remove(aw);
  currentActiveWidget = activeWidgets.end();
}

void
ContainerWidget::DrawChildWidgets()
{
  for (std::list<Widget *>::iterator it = widgets.begin(); it != widgets.end(); ++it) {
    (*it)->Draw();
  }
  for (std::list<ActiveWidget *>::iterator it = activeWidgets.begin(); it != activeWidgets.end(); ++it) {
    (*it)->Draw();
  }
}

void
ContainerWidget::Draw()
{
  if (IsVisible()) {
    DrawChildWidgets();
  }
}

void
ContainerWidget::NextWidget()
{
  if (activeWidgets.size() > 0) {
    do {
      if (currentActiveWidget != activeWidgets.end()) {
        currentActiveWidget++;
      }
      if (currentActiveWidget == activeWidgets.end()) {
        currentActiveWidget = activeWidgets.begin();
      }
    } while (!((*currentActiveWidget)->IsVisible()));
    (*currentActiveWidget)->Focus();
  }
}

void
ContainerWidget::PreviousWidget()
{
  if (activeWidgets.size() > 0) {
    do {
      if (currentActiveWidget == activeWidgets.begin()) {
        currentActiveWidget = activeWidgets.end();
      }
      currentActiveWidget--;
    } while (!((*currentActiveWidget)->IsVisible()));
    (*currentActiveWidget)->Focus();
  }
}

void
ContainerWidget::LeftClickWidget(const bool toggle)
{
  if ((activeWidgets.size() > 0) && (currentActiveWidget != activeWidgets.end())) {
    (*currentActiveWidget)->LeftClick(toggle);
  }
}

void
ContainerWidget::RightClickWidget(const bool toggle)
{
  if ((activeWidgets.size() > 0) && (currentActiveWidget != activeWidgets.end())) {
    (*currentActiveWidget)->RightClick(toggle);
  }
}

void
ContainerWidget::LeftClickWidget(const bool toggle, const int x, const int y)
{
  for (std::list<ActiveWidget *>::iterator it = activeWidgets.begin(); it != activeWidgets.end(); ++it) {
    Vector2D p(x, y);
    if ((*it)->GetRectangle().IsInside(p)) {
      (*it)->LeftClick(toggle);
    }
  }
}

void
ContainerWidget::RightClickWidget(const bool toggle, const int x, const int y)
{
  for (std::list<ActiveWidget *>::iterator it = activeWidgets.begin(); it != activeWidgets.end(); ++it) {
    Vector2D p(x, y);
    if ((*it)->GetRectangle().IsInside(p)) {
      (*it)->RightClick(toggle);
    }
  }
}

void
ContainerWidget::MouseOverWidget(const int x, const int y)
{
  for (std::list<ActiveWidget *>::iterator it = activeWidgets.begin(); it != activeWidgets.end(); ++it) {
    Vector2D p(x, y);
    if (!(*it)->GetRectangle().IsInside(p)) {
      (*it)->LeftClick(false);
    }
  }
}
