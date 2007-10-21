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

#include "ChoiceWidget.h"
#include "Exception.h"
#include "MediaToolkit.h"
#include "PreferencesDialogBridge.h"

ChoiceWidget::ChoiceWidget(const Rectangle &r, const int a)
        : ActiveWidget(r, a)
        , normalImage(0)
        , selectedImage(0)
{}

ChoiceWidget::~ChoiceWidget()
{}

void
ChoiceWidget::SetImage(Image *normal, Image *selected)
{
    if ((!normal) || (!selected))
    {
        throw NullPointer(__FILE__, __LINE__);
    }
    normalImage = normal;
    selectedImage = selected;
}

void
ChoiceWidget::Draw()
{
    if (IsVisible())
    {
        if (PreferencesDialogBridge::GetInstance()->GetSelectState(action))
        {
            selectedImage->Draw(rect.GetXPos(), rect.GetYPos(), 0);
        }
        else
        {
            normalImage->Draw(rect.GetXPos(), rect.GetYPos(), 0);
        }
    }
}

void
ChoiceWidget::LeftClick(const bool toggle, const int x, const int y)
{
    if (IsVisible())
    {
        if (toggle)
        {
            ActionEvent ae(action, x, y);
            for (std::list<ActionEventListener *>::iterator it = actionListeners.begin(); it != actionListeners.end(); ++it)
            {
                (*it)->ActionPerformed(ae);
            }
        }
    }
}

void
ChoiceWidget::RightClick(const bool toggle, const int, const int)
{
    if (IsVisible())
    {
        if (toggle)
        {}
    }
}

void
ChoiceWidget::Drag(const int, const int)
{}

void
ChoiceWidget::Drop(const int, const int)
{}
