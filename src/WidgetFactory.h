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

#ifndef WIDGET_FACTORY_H
#define WIDGET_FACTORY_H

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "CharacterButtonWidget.h"
#include "ChoiceWidget.h"
#include "CombatViewWidget.h"
#include "CompassWidget.h"
#include "Game.h"
#include "ImageButtonWidget.h"
#include "ImageResource.h"
#include "ImageWidget.h"
#include "LabelResource.h"
#include "MapViewWidget.h"
#include "PanelWidget.h"
#include "RequestResource.h"
#include "ScreenResource.h"
#include "TextButtonWidget.h"
#include "TickboxWidget.h"
#include "WorldViewWidget.h"

class WidgetFactory {
  public:
    WidgetFactory();
    virtual ~WidgetFactory();
    TextButtonWidget* CreateTextButton(RequestData& data, FontResource& fnt, ActionEventListener *ael);
    ImageButtonWidget* CreateImageButton(RequestData& data, ImageResource& normal, ImageResource& pressed, ActionEventListener *ael);
    CharacterButtonWidget* CreateCharacterButton(RequestData& data, PlayerCharacter *pc, ImageResource& img, ActionEventListener *ael);
    ChoiceWidget* CreateChoice();
    TickboxWidget* CreateTickbox();
    CompassWidget* CreateCompass(Camera *cam, Image *img);
    CombatViewWidget* CreateCombatView(RequestData& data, Game *game);
    MapViewWidget* CreateMapView(RequestData& data, Game *game);
    WorldViewWidget* CreateWorldView(RequestData& data, Game *game);
    LabelWidget* CreateLabel(LabelData& data, FontResource& fnt, const int panelWidth);
    ImageWidget* CreateImage(const int x, const int y, const int w, const int h, Image *img, const Flipping flip = NONE);
    PanelWidget* CreatePanel(const int x, const int y, const int w, const int h, Image *img);
};

#endif

