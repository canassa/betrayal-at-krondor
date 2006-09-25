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

#include "GameViewWidget.h"
#include "MediaToolkit.h"

GameViewWidget::GameViewWidget(const int x, const int y, const int w, const int h, Game *g)
: ContainerWidget(x, y, w, h)
, game(g)
, image(0)
, cacheValid(false)
{
  image = new Image(w, h);
}

GameViewWidget::~GameViewWidget()
{
}

void
GameViewWidget::Draw()
{
  if (cacheValid) {
    image->Draw(xpos, ypos);
  } else {
    Redraw();
    image->Read(xpos, ypos);
    cacheValid = true;
  }
  DrawChildWidgets();
}

void
GameViewWidget::KeyPressed(const KeyboardEvent& kbe)
{
  switch (kbe.GetKey()){
    default:
      cacheValid = false;
      break;
  }
}

void
GameViewWidget::KeyReleased(const KeyboardEvent& kbe)
{
  switch (kbe.GetKey()){
    default:
      break;
  }
}

void
GameViewWidget::MouseButtonPressed(const MouseButtonEvent& mbe)
{
  switch (mbe.GetButton()){
    default:
      cacheValid = false;
      break;
  }
}

void
GameViewWidget::MouseButtonReleased(const MouseButtonEvent& mbe)
{
  switch (mbe.GetButton()){
    default:
      break;
  }
}
