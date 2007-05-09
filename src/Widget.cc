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

#include "Widget.h"

Widget::Widget(const Rectangle &r)
: rect(r)
, visible(true)
{
}

Widget::~Widget()
{
}

Rectangle&
Widget::GetRectangle()
{
  return rect;
}

void
Widget::SetPosition(const int x, const int y)
{
  rect.SetXPos(x);
  rect.SetYPos(y);
}

void
Widget::SetVisible(const bool toggle)
{
  visible = toggle;
}

bool
Widget::IsVisible() const
{
  return visible;
}


ActiveWidget::ActiveWidget(const Rectangle &r, const int a)
: Widget(r)
, action(a)
, actionListeners()
{
}

ActiveWidget::~ActiveWidget()
{
  actionListeners.clear();
}

int
ActiveWidget::GetAction() const
{
  return action;
}

void
ActiveWidget::GenerateActionEvent(const int a)
{
  ActionEvent ae(a);
  for (std::list<ActionEventListener *>::iterator it = actionListeners.begin(); it != actionListeners.end(); ++it) {
    (*it)->ActionPerformed(ae);
  }
}

void
ActiveWidget::AddActionListener(ActionEventListener *ael)
{
  actionListeners.push_back(ael);
}

void
ActiveWidget::RemoveActionListener(ActionEventListener *ael)
{
  actionListeners.remove(ael);
}
