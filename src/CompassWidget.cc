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

#include "CompassWidget.h"

static const int COMPASS_WIDGET_XPOS   = 144;
static const int COMPASS_WIDGET_YPOS   = 121;
static const int COMPASS_WIDGET_WIDTH  = 32;
static const int COMPASS_WIDGET_HEIGHT = 11;

CompassWidget::CompassWidget(Camera *cam, Image *img)
: Widget(COMPASS_WIDGET_XPOS, COMPASS_WIDGET_YPOS, COMPASS_WIDGET_WIDTH, COMPASS_WIDGET_HEIGHT)
, camera(cam)
, compassImage(img)
, cachedImage(0)
{
  cachedImage = new Image(COMPASS_WIDGET_WIDTH, COMPASS_WIDGET_HEIGHT);
  camera->Attach(this);
  Update();
}

CompassWidget::~CompassWidget()
{
  camera->Detach(this);
  if (cachedImage) {
    delete cachedImage;
  }
}

void
CompassWidget::Draw()
{
  if (IsVisible()) {
    if (cachedImage){
      cachedImage->Draw(xpos, ypos);
    }
  }
}

void
CompassWidget::Update()
{
  if (compassImage) {
    int offset = -camera->GetHeading();
    int imagewidth = compassImage->GetWidth();
    compassImage->Draw(xpos + offset, ypos, xpos, ypos, width, height);
    if ((imagewidth + offset) < width) {
      compassImage->Draw(xpos + offset + imagewidth, ypos, xpos, ypos, width, height);
    }
  }
  if (cachedImage){
    cachedImage->Read(xpos, ypos);
  }
}
