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

#ifndef EQUIPMENT_ITEM_WIDGET_H
#define EQUIPMENT_ITEM_WIDGET_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "Image.h"
#include "TextWidget.h"
#include "Widget.h"

static const int MAX_EQUIPMENT_ITEM_WIDGET_WIDTH  = 80;
static const int MAX_EQUIPMENT_ITEM_WIDGET_HEIGHT = 58;

class EquipmentItemWidget
            : public Widget
{
private:
    Image *iconImage;
    TextWidget *label;
public:
    EquipmentItemWidget ( const Rectangle &r );
    virtual ~EquipmentItemWidget();
    void SetImage ( Image *icon );
    void SetLabel ( const std::string& s, Font *f );
    void Draw();
};

#endif
