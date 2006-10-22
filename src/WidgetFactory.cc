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

#include "WidgetFactory.h"

WidgetFactory::WidgetFactory()
{
}

WidgetFactory::~WidgetFactory()
{
}

TextButtonWidget*
WidgetFactory::CreateTextButton(RequestData& data, FontResource &fnt, ActionEventListener *ael)
{
  TextButtonWidget *button = new TextButtonWidget(data.xpos, data.ypos, data.width, data.height, data.action);
  button->SetVisible(data.visible);
  button->SetLabel(data.label, fnt);
  button->AddActionListener(ael);
  return button;
}

ImageButtonWidget*
WidgetFactory::CreateImageButton(RequestData& data, ImageResource& normal, ImageResource& pressed, ActionEventListener *ael)
{
  ImageButtonWidget *button = new ImageButtonWidget(data.xpos, data.ypos, data.width, data.height, data.action);
  button->SetVisible(data.visible);
  Image *normalImage = 0;
  Image *pressedImage = 0;
  if (data.image >= 0) {
    normalImage = normal.GetImage(data.image);
    pressedImage = pressed.GetImage(data.image);
  }
  button->SetImage(normalImage, pressedImage);
  button->AddActionListener(ael);
  return button;
}

CharacterButtonWidget*
WidgetFactory::CreateCharacterButton(RequestData& data, PlayerCharacter *pc, ImageResource& img, ActionEventListener *ael)
{
  CharacterButtonWidget *button = new CharacterButtonWidget(data.xpos, data.ypos, data.width, data.height, data.action);
  button->SetVisible(true);
  button->SetCharacter(pc);
  button->SetImage(img.GetImage(SELECTED_IMAGE));
  button->AddActionListener(ael);
  return button;
}

ChoiceWidget*
WidgetFactory::CreateChoice()
{
  return 0;
}

TickboxWidget*
WidgetFactory::CreateTickbox()
{
  return 0;
}

CompassWidget*
WidgetFactory::CreateCompass(Camera *cam, Image *img)
{
  CompassWidget *compass = new CompassWidget(cam, img);
  return compass;
}

CombatViewWidget*
WidgetFactory::CreateCombatView(RequestData& data, Game *game)
{
  return new CombatViewWidget(data.xpos, data.ypos, data.width, data.height, game);
}

MapViewWidget*
WidgetFactory::CreateMapView(RequestData& data, Game *game)
{
  return new MapViewWidget(data.xpos, data.ypos, data.width, data.height, game);
}

WorldViewWidget*
WidgetFactory::CreateWorldView(RequestData& data, Game *game)
{
  return new WorldViewWidget(data.xpos, data.ypos, data.width, data.height, game);
}

LabelWidget*
WidgetFactory::CreateLabel(LabelData& data, FontResource& fnt, const int panelWidth)
{
  unsigned int width = 1;
  switch (data.type) {
    case LBL_STANDARD:
      for (unsigned int i = 0; i < data.label.length(); i++) {
        width += fnt.GetWidth((unsigned int)data.label[i] - fnt.GetFirst());
      }
      break;
    case LBL_TITLE:
      width = panelWidth;
      break;
    default:
      break;
  }
  LabelWidget *label = new LabelWidget(data.xpos, data.ypos, width, fnt.GetHeight() + 1, fnt);
  label->SetText(data.label);
  label->SetColor(data.color);
  if (data.type == LBL_TITLE) {
    label->SetShadow(data.shadow);
    label->SetAlignment(HA_CENTER, VA_TOP);
  }
  return label;
}

BadgeWidget*
WidgetFactory::CreateBadge(const int x, const int y, const int w, const int h, const std::string& s, FontResource& fnt)
{
  BadgeWidget *badge = new BadgeWidget(x, y, w, h);
  badge->SetLabel(s, fnt);
  return badge;
}

ImageWidget*
WidgetFactory::CreateImage(const int x, const int y, const int w, const int h, Image *img, const Flipping flip)
{
  ImageWidget *image = new ImageWidget(x, y, w, h, img);
  switch (flip) {
    case HORIZONTAL:
      image->HorizontalFlip();
      break;
    case VERTICAL:
      image->VerticalFlip();
      break;
    default:
      break;
  }
  return image;
}

PortraitWidget*
WidgetFactory::CreatePortrait(const int x, const int y, const int w, const int h, PlayerCharacter *pc, Image *hb, Image *vb)
{
  PortraitWidget *portrait = new PortraitWidget(x, y, w, h, pc);
  portrait->SetBorders(hb, vb);
  return portrait;
}

RatingsWidget*
WidgetFactory::CreateRatings(const int x, const int y, const int w, const int h, PlayerCharacter *pc, Image *hb, Image *vb)
{
  RatingsWidget *ratings = new RatingsWidget(x, y, w, h, pc);
  ratings->SetBorders(hb, vb);
  return ratings;
}

SkillsWidget*
WidgetFactory::CreateSkills(const int x, const int y, const int w, const int h, PlayerCharacter *pc, Image *sw, Image *bl)
{
  SkillsWidget *skills = new SkillsWidget(x, y, w, h, pc, sw, bl);
  return skills;
}

PanelWidget*
WidgetFactory::CreatePanel(const int x, const int y, const int w, const int h, Image *img)
{
  PanelWidget *panel = new PanelWidget(x, y, w, h);
  panel->SetBackground(img);
  return panel;
}
