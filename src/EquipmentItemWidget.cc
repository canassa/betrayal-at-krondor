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

#include "EquipmentItemWidget.h"
#include "Exception.h"

EquipmentItemWidget::EquipmentItemWidget(const Rectangle &r, const ObjectType t)
        : Widget(r)
        , type(t)
        , iconImage(0)
        , label(0)
{}

EquipmentItemWidget::~EquipmentItemWidget()
{
    if (label)
    {
        delete label;
    }
}

void
EquipmentItemWidget::SetImage(Image *icon)
{
    if (!icon)
    {
        throw NullPointer(__FILE__, __LINE__);
    }
    iconImage = icon;
}

void
EquipmentItemWidget::SetLabel(const std::string& s, Font *f)
{
    label = new TextWidget(Rectangle(rect.GetXPos(), rect.GetYPos(), rect.GetWidth(), rect.GetHeight()), f);
    label->SetText(s);
    label->SetColor(INFO_TEXT_COLOR);
    label->SetAlignment(HA_RIGHT, VA_BOTTOM);
}

void
EquipmentItemWidget::Draw()
{
    if (IsVisible())
    {
        if (iconImage)
        {
            iconImage->Draw(rect.GetXPos() + (rect.GetWidth() - iconImage->GetWidth()) / 2,
                            rect.GetYPos() + (rect.GetHeight() - iconImage->GetHeight()) / 2, 0);
        }
        if (label)
        {
            label->Draw();
        }
    }
}

void
EquipmentItemWidget::Drag(const int, const int)
{
}

void
EquipmentItemWidget::Drop(const int, const int)
{
}
