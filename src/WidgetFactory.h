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

#include <deque>

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
#include "LabelResource.h"
#include "MapViewWidget.h"
#include "PanelWidget.h"
#include "RequestResource.h"
#include "ScreenResource.h"
#include "TextButtonWidget.h"
#include "TickboxWidget.h"
#include "WorldViewWidget.h"

static const unsigned int MAX_ACTIVE_MEMBERS = 3;

typedef enum _GameViewType {
  GVT_WORLD,
  GVT_MAP,
  GVT_COMBAT
} GameViewType;

typedef struct _WidgetResources {
  RequestResource *request;
  ScreenResource *screen;
  LabelResource *label;
  FontResource *font;
  ImageResource *normal;
  ImageResource *pressed;
  ImageResource *compass;
  Orientation *orient;
  ImageResource *heads;
  PlayerCharacter *members[MAX_ACTIVE_MEMBERS];
  int playerCharacterGroup;
  Game *game;
  int gameViewGroup;
  GameViewType gameViewType;
  ActionEventListener *eventListener;
} WidgetResources;

class WidgetFactory {
  public:
    WidgetFactory();
    virtual ~WidgetFactory();
    TextButtonWidget* CreateTextButton(RequestData& data, FontResource* fnt, ActionEventListener *ael);
    ImageButtonWidget* CreateImageButton(RequestData& data, ImageResource *normal, ImageResource *pressed, ActionEventListener *ael);
    CharacterButtonWidget* CreateCharacterButton(RequestData& data, PlayerCharacter *pc, ImageResource *img, ActionEventListener *ael);
    ChoiceWidget* CreateChoice();
    TickboxWidget* CreateTickbox();
    CompassWidget* CreateCompass(ImageResource *img, Orientation* orient);
    CombatViewWidget* CreateCombatView(RequestData& data, Game *game);
    MapViewWidget* CreateMapView(RequestData& data, Game *game);
    WorldViewWidget* CreateWorldView(RequestData& data, Game *game);
    LabelWidget* CreateLabel(LabelData& data, FontResource* fnt, const int panelWidth);
    PanelWidget* CreatePanel(WidgetResources& widgetRes);
};

#endif

