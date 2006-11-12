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

#include "Widget.h"

Widget::Widget(const int x, const int y, const int w, const int h)
: xpos(x)
, ypos(y)
, width(w)
, height(h)
, visible(true)
{
}

Widget::~Widget()
{
}

bool
Widget::Covers(const int x, const int y) const
{
  return ((xpos <= x) && (x < xpos + width) &&
          (ypos <= y) && (y < ypos + height));
}

int
Widget::GetXPos() const
{
  return xpos;
}

int
Widget::GetYPos() const
{
  return ypos;
}

int
Widget::GetXCenter() const
{
  return xpos + width / 2;
}

int
Widget::GetYCenter() const
{
  return ypos + height / 2;
}

int
Widget::GetWidth() const
{
  return width;
}

int
Widget::GetHeight() const
{
  return height;
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


ActiveWidget::ActiveWidget(const int x, const int y, const int w, const int h, const int a)
: Widget(x, y, w, h)
, action(a)
, actionListeners()
{
}

ActiveWidget::~ActiveWidget()
{
  actionListeners.clear();
}

void
ActiveWidget::SetPosition(const int x, const int y)
{
  xpos = x;
  ypos = y;
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
