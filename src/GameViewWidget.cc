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
 * Copyright (C) 2005-2009 Guido de Jong <guidoj@users.sf.net>
 */

#include "GameViewWidget.h"

GameViewWidget::GameViewWidget(const Rectangle &r, Game *g)
        : ContainerWidget(r)
        , game(g)
        , cachedImage(0)
{
    cachedImage = new Image(rect.GetWidth(), rect.GetHeight());
}

GameViewWidget::~GameViewWidget()
{
    if (cachedImage)
    {
        delete cachedImage;
    }
}

void
GameViewWidget::Draw()
{
    if (IsVisible())
    {
        if (cachedImage)
        {
            cachedImage->Draw(rect.GetXPos(), rect.GetYPos());
        }
        DrawChildWidgets();
    }
}

void
GameViewWidget::Update()
{
    Redraw();
    if (cachedImage)
    {
        cachedImage->Read(rect.GetXPos(), rect.GetYPos());
    }
}
