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

#include "CharacterButtonWidget.h"
#include "Exception.h"
#include "GameApplication.h"
#include "PointerManager.h"

Image* CharacterButtonWidget::selectedImage = 0;

CharacterButtonWidget::CharacterButtonWidget(const Rectangle &r, const int a)
        : ButtonWidget(r, a)
        , character(0)
{}

CharacterButtonWidget::~CharacterButtonWidget()
{}

void
CharacterButtonWidget::SetCharacter(PlayerCharacter *pc)
{
    if (!pc)
    {
        throw NullPointer(__FILE__, __LINE__);
    }
    character = pc;
}

void
CharacterButtonWidget::SetImage(Image *selected)
{
    if (!selected)
    {
        throw NullPointer(__FILE__, __LINE__);
    }
    selectedImage = selected;
}

void
CharacterButtonWidget::Draw()
{
    if (IsVisible())
    {
        if (character)
        {
            character->GetButtonImage()->Draw(rect.GetXPos(), rect.GetYPos(), 0);
            if (character->IsSelected())
            {
                selectedImage->Draw(rect.GetXPos(), rect.GetYPos(), 0);
            }
        }
    }
}

void
CharacterButtonWidget::LeftClick(const bool toggle, const int, const int)
{
    if (IsVisible())
    {
        if (toggle)
        {
            GenerateActionEvent(GetAction());
        }
    }
}

void
CharacterButtonWidget::RightClick(const bool toggle, const int, const int)
{
    if (IsVisible())
    {
        if (toggle)
        {
            GenerateActionEvent(GetAction() + RIGHT_CLICK_OFFSET);
        }
    }
}

void
CharacterButtonWidget::Drop(const int, const int)
{
    InventoryItemWidget *widget = PointerManager::GetInstance()->GetDraggedWidget();
    if (widget)
    {
        InventoryItem *item = widget->GetInventoryItem();
        if (item)
        {
            GameApplication::GetInstance()->GetGame()->GetParty()->GetSelectedMember()->GetInventory()->Remove(item);
            character->GetInventory()->Add(item);
        }
    }
}
