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

#include "ContainerWidget.h"

ContainerWidget::ContainerWidget(const int x, const int y, const int w, const int h)
: Widget(x, y, w, h)
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
  currentActiveWidget = activeWidgets.begin();
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
  currentActiveWidget = activeWidgets.begin();
}

void
ContainerWidget::DrawWidgets(Video *video)
{
  for (std::list<Widget *>::iterator it = widgets.begin(); it != widgets.end(); ++it) {
    (*it)->Draw(video);
  }
  for (std::list<ActiveWidget *>::iterator it = activeWidgets.begin(); it != activeWidgets.end(); ++it) {
    (*it)->Draw(video);
  }
}

void
ContainerWidget::Draw(Video *video)
{
  DrawWidgets(video);
}

void
ContainerWidget::NextWidget(Video *video)
{
  if (activeWidgets.size() > 0) {
    currentActiveWidget++;
    if (currentActiveWidget == activeWidgets.end()) {
      currentActiveWidget = activeWidgets.begin();
    }
    (*currentActiveWidget)->Focus(video);
  }
}

void
ContainerWidget::PreviousWidget(Video *video)
{
  if (activeWidgets.size() > 0) {
    if (currentActiveWidget == activeWidgets.begin()) {
      currentActiveWidget = activeWidgets.end();
    }
    currentActiveWidget--;
    (*currentActiveWidget)->Focus(video);
  }
}

void
ContainerWidget::LeftClickWidget(const bool toggle)
{
  if (activeWidgets.size() > 0) {
    (*currentActiveWidget)->LeftClick(toggle);
  }
}

void
ContainerWidget::RightClickWidget(const bool toggle)
{
  if (activeWidgets.size() > 0) {
    (*currentActiveWidget)->RightClick(toggle);
  }
}

void
ContainerWidget::LeftClickWidget(const bool toggle, const int x, const int y)
{
  for (std::list<ActiveWidget *>::iterator it = activeWidgets.begin(); it != activeWidgets.end(); ++it) {
    if ((*it)->Covers(x, y)) {
      (*it)->LeftClick(toggle);
    }
  }
}

void
ContainerWidget::RightClickWidget(const bool toggle, const int x, const int y)
{
  for (std::list<ActiveWidget *>::iterator it = activeWidgets.begin(); it != activeWidgets.end(); ++it) {
    if ((*it)->Covers(x, y)) {
      (*it)->RightClick(toggle);
    }
  }
}
