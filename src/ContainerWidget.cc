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
, widgetVec()
, currentWidget(-1)
{
}

ContainerWidget::~ContainerWidget()
{
  for (unsigned int i = 0; i < widgetVec.size(); i++) {
    delete widgetVec[i];
  }
  widgetVec.clear();
}

void
ContainerWidget::AddWidget(Widget *w)
{
  widgetVec.push_back(w);
}

void
ContainerWidget::DrawWidgets(Video *video)
{
  for (unsigned int i = 0; i < widgetVec.size(); i++) {
    widgetVec[i]->Draw(video);
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
  if (widgetVec.size() > 0) {
    currentWidget++;
    if ((unsigned int)currentWidget == widgetVec.size()) {
      currentWidget = 0;
    }
    widgetVec[currentWidget]->Focus(video);
  }
}

void
ContainerWidget::Activate(const bool toggle)
{
  if ((currentWidget >= 0) && ((unsigned int)currentWidget < widgetVec.size())) {
    widgetVec[currentWidget]->Activate(toggle);
  }
}

void
ContainerWidget::Activate(const int x, const int y, const bool toggle)
{
  for (unsigned int i = 0; i < widgetVec.size(); i++) {
    if (widgetVec[i]->Covers(x, y)) {
      widgetVec[i]->Activate(toggle);
    }
  }
}
