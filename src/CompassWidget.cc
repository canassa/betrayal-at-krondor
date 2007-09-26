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

#include "CompassWidget.h"

static const int COMPASS_WIDGET_XPOS   = 144;
static const int COMPASS_WIDGET_YPOS   = 121;
static const int COMPASS_WIDGET_WIDTH  = 32;
static const int COMPASS_WIDGET_HEIGHT = 11;

static const Rectangle COMPASS_WIDGET_RECTANGLE = Rectangle(COMPASS_WIDGET_XPOS, COMPASS_WIDGET_YPOS, COMPASS_WIDGET_WIDTH, COMPASS_WIDGET_HEIGHT);

CompassWidget::CompassWidget(Camera *cam, Image *img)
        : Widget(COMPASS_WIDGET_RECTANGLE)
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
    if (cachedImage)
    {
        delete cachedImage;
    }
}

void
CompassWidget::Draw()
{
    if (IsVisible())
    {
        if (cachedImage)
        {
            cachedImage->Draw(rect.GetXPos(), rect.GetYPos());
        }
    }
}

void
CompassWidget::Update()
{
    if (compassImage)
    {
        int offset = camera->GetHeading();
        int imagewidth = compassImage->GetWidth();
        compassImage->Draw(rect.GetXPos() - offset, rect.GetYPos(), offset, 0, rect.GetWidth(), rect.GetHeight());
        if ((imagewidth - offset) < rect.GetWidth())
        {
            compassImage->Draw(rect.GetXPos() - offset + imagewidth, rect.GetYPos(), 0, 0, rect.GetWidth() - imagewidth + offset, rect.GetHeight());
        }
    }
    if (cachedImage)
    {
        cachedImage->Read(rect.GetXPos(), rect.GetYPos());
    }
}

void
CompassWidget::Drag(const int, const int)
{
}

void
CompassWidget::Drop(const int, const int)
{
}
